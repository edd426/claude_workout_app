import Foundation

enum InboxApplyError: Error, LocalizedError {
    case malformedPayload(String)
    case unknownOperation(String)
    case invalidTemplateId(String)
    case templateNotFound(String)
    case unresolvedExerciseIds([String])

    var errorDescription: String? {
        switch self {
        case .malformedPayload(let reason):
            return "Malformed inbox payload: \(reason)"
        case .unknownOperation(let operation):
            return "Unknown inbox operation: \(operation)"
        case .invalidTemplateId(let id):
            return "Invalid template id: \(id)"
        case .templateNotFound(let id):
            return "Template not found: \(id)"
        case .unresolvedExerciseIds(let ids):
            return "Unresolved exercise externalIds: \(ids.joined(separator: ", "))"
        }
    }
}

/// Applies durable inbox operations to phone-owned repositories.
///
/// This service has no networking and no ModelContext dependency. Every
/// operation is decoded and handled independently, and all exercise references
/// are resolved before a template is mutated or saved.
@MainActor
final class InboxApplier {
    private let templateRepository: any TemplateRepository
    private let exerciseRepository: any ExerciseRepository

    init(
        templateRepository: any TemplateRepository,
        exerciseRepository: any ExerciseRepository
    ) {
        self.templateRepository = templateRepository
        self.exerciseRepository = exerciseRepository
    }

    /// Process every operation even when an earlier one is malformed or fails.
    func process(_ operations: [InboxOperationDTO]) async -> [InboxAckResult] {
        var results: [InboxAckResult] = []
        results.reserveCapacity(operations.count)

        for operation in operations {
            do {
                results.append(try await process(operation))
            } catch {
                results.append(
                    InboxAckResult(
                        id: operation.id,
                        status: .failed,
                        error: error.localizedDescription
                    )
                )
            }
        }
        return results
    }

    private func process(_ operation: InboxOperationDTO) async throws -> InboxAckResult {
        guard operation.status == "pending" else {
            throw InboxApplyError.malformedPayload(
                "Expected pending status, got \(operation.status)"
            )
        }

        switch operation.op {
        case "createTemplate":
            let payload = try decode(CreateTemplatePayload.self, from: operation.payload)
            try await createTemplate(payload)
            return InboxAckResult(id: operation.id, status: .applied)

        case "createCustomExercise":
            let payload = try decode(CreateCustomExercisePayload.self, from: operation.payload)
            try await createCustomExercise(payload)
            return InboxAckResult(id: operation.id, status: .applied)

        case "updateTemplate":
            let payload = try decode(UpdateTemplatePayload.self, from: operation.payload)
            try validateUpdatePayload(payload)
            try await updateTemplate(payload)
            return InboxAckResult(id: operation.id, status: .applied)

        case "deleteTemplate":
            let payload = try decode(DeleteTemplatePayload.self, from: operation.payload)
            try validateDeletePayload(payload)
            try await deleteTemplate(payload)
            return InboxAckResult(id: operation.id, status: .applied)

        default:
            throw InboxApplyError.unknownOperation(operation.op)
        }
    }

    private func createTemplate(_ payload: CreateTemplatePayload) async throws {
        try validateTemplatePayload(name: payload.name, exercises: payload.exercises)
        let resolved = try await resolve(payload.exercises)
        let template = WorkoutTemplate(name: payload.name, notes: payload.notes)
        template.exercises = makeTemplateExercises(from: resolved)
        try await templateRepository.save(template)
    }

    private func createCustomExercise(
        _ payload: CreateCustomExercisePayload
    ) async throws {
        let name = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw InboxApplyError.malformedPayload(
                "Custom exercise name must not be empty"
            )
        }
        let exercise = Exercise(
            name: name,
            equipment: payload.equipment,
            instructions: payload.instructions ?? [],
            primaryMuscles: payload.primaryMuscles ?? [],
            secondaryMuscles: payload.secondaryMuscles ?? [],
            isCustom: true,
            externalId: "custom:\(slug(name))",
            notes: payload.notes
        )
        try await exerciseRepository.save(exercise)
    }

    private func updateTemplate(_ payload: UpdateTemplatePayload) async throws {
        guard let id = UUID(uuidString: payload.id) else {
            throw InboxApplyError.invalidTemplateId(payload.id)
        }
        guard let template = try await templateRepository.fetch(id: id) else {
            throw InboxApplyError.templateNotFound(payload.id)
        }

        var replacementExercises: [TemplateExercise]?
        if let exercises = payload.exercises {
            try validateTemplatePayload(name: payload.name ?? template.name, exercises: exercises)
            replacementExercises = makeTemplateExercises(
                from: try await resolve(exercises)
            )
        }

        if let name = payload.name {
            template.name = name
        }
        if let notes = payload.notes {
            template.notes = notes
        }
        if let replacementExercises {
            template.exercises = replacementExercises
        }
        template.updatedAt = .now
        template.recordChange()
        try await templateRepository.save(template)
    }

    private func deleteTemplate(_ payload: DeleteTemplatePayload) async throws {
        guard let id = UUID(uuidString: payload.id) else {
            throw InboxApplyError.invalidTemplateId(payload.id)
        }
        // Desired state is already reached if a prior apply succeeded but its
        // acknowledgement response was lost.
        guard let template = try await templateRepository.fetch(id: id) else {
            return
        }
        try await templateRepository.delete(template)
    }

    private typealias ResolvedExercise = (
        payload: InboxTemplateExercisePayload,
        exercise: Exercise
    )

    private func resolve(
        _ payloads: [InboxTemplateExercisePayload]
    ) async throws -> [ResolvedExercise] {
        var resolved: [ResolvedExercise] = []
        var unresolved: [String] = []

        for payload in payloads {
            if let exercise = try await exerciseRepository.fetchByExternalId(
                payload.externalId
            ) {
                resolved.append((payload, exercise))
            } else {
                unresolved.append(payload.externalId)
            }
        }

        guard unresolved.isEmpty else {
            throw InboxApplyError.unresolvedExerciseIds(unresolved)
        }
        return resolved.sorted { $0.payload.order < $1.payload.order }
    }

    private func makeTemplateExercises(
        from resolved: [ResolvedExercise]
    ) -> [TemplateExercise] {
        resolved.map { item in
            TemplateExercise(
                order: item.payload.order,
                exercise: item.exercise,
                defaultSets: item.payload.defaultSets,
                defaultReps: item.payload.defaultReps,
                defaultWeight: item.payload.defaultWeight,
                defaultRestSeconds: item.payload.defaultRestSeconds ?? 90,
                notes: item.payload.notes
            )
        }
    }

    private func validateTemplatePayload(
        name: String,
        exercises: [InboxTemplateExercisePayload]
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InboxApplyError.malformedPayload(
                "Template name must not be empty"
            )
        }

        var orders = Set<Int>()
        for exercise in exercises {
            guard !exercise.externalId.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                throw InboxApplyError.malformedPayload(
                    "Exercise externalId must not be empty"
                )
            }
            guard exercise.order >= 0, orders.insert(exercise.order).inserted else {
                throw InboxApplyError.malformedPayload(
                    "Exercise orders must be unique non-negative integers"
                )
            }
            guard exercise.defaultSets > 0, exercise.defaultReps > 0 else {
                throw InboxApplyError.malformedPayload(
                    "Exercise sets and reps must be positive"
                )
            }
            if let weight = exercise.defaultWeight, !weight.isFinite {
                throw InboxApplyError.malformedPayload(
                    "Exercise defaultWeight must be finite"
                )
            }
            if let rest = exercise.defaultRestSeconds, rest < 0 {
                throw InboxApplyError.malformedPayload(
                    "Exercise defaultRestSeconds must be non-negative"
                )
            }
        }
    }

    private func validateUpdatePayload(
        _ payload: UpdateTemplatePayload
    ) throws {
        guard !payload.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InboxApplyError.malformedPayload(
                "Template id must not be empty"
            )
        }
        if let name = payload.name,
           name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw InboxApplyError.malformedPayload(
                "Template name must not be empty"
            )
        }
    }

    private func validateDeletePayload(
        _ payload: DeleteTemplatePayload
    ) throws {
        guard !payload.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InboxApplyError.malformedPayload(
                "Template id must not be empty"
            )
        }
        guard !payload.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InboxApplyError.malformedPayload(
                "Template name must not be empty"
            )
        }
    }

    private func decode<Payload: Decodable>(
        _ type: Payload.Type,
        from payload: InboxJSONValue
    ) throws -> Payload {
        do {
            return try payload.decode(type)
        } catch {
            throw InboxApplyError.malformedPayload(error.localizedDescription)
        }
    }

    private func slug(_ name: String) -> String {
        let folded = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let pieces = folded.unicodeScalars.split {
            !CharacterSet.alphanumerics.contains($0)
        }
        let slug = pieces
            .map { String(String.UnicodeScalarView($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
        return slug.isEmpty ? "exercise" : slug
    }
}
