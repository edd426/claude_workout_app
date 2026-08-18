import Foundation

enum InboxApplyError: Error, LocalizedError {
    case malformedPayload(String)
    case unknownOperation(String)
    case invalidOperationId(String)
    case invalidTemplateId(String)
    case templateNotFound(String)
    case unresolvedExerciseIds([String])
    case invalidCustomExternalId(String)
    case invalidReportId(String)
    case reportNotFound(String)
    case invalidReportStatus(String)

    var errorDescription: String? {
        switch self {
        case .malformedPayload(let reason):
            return "Malformed inbox payload: \(reason)"
        case .unknownOperation(let operation):
            return "Unknown inbox operation: \(operation)"
        case .invalidOperationId(let id):
            return "Invalid inbox operation id: \(id)"
        case .invalidTemplateId(let id):
            return "Invalid template id: \(id)"
        case .templateNotFound(let id):
            return "Template not found: \(id)"
        case .unresolvedExerciseIds(let ids):
            return "Unresolved exercise externalIds: \(ids.joined(separator: ", "))"
        case .invalidCustomExternalId(let id):
            return "Invalid custom exercise externalId: \(id)"
        case .invalidReportId(let id):
            return "Invalid report id: \(id)"
        case .reportNotFound(let id):
            return "Report not found: \(id)"
        case .invalidReportStatus(let status):
            return "Invalid report status: \(status) (expected acknowledged or resolved)"
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
    private let reportRepository: any ExerciseReportRepository

    init(
        templateRepository: any TemplateRepository,
        exerciseRepository: any ExerciseRepository,
        reportRepository: any ExerciseReportRepository
    ) {
        self.templateRepository = templateRepository
        self.exerciseRepository = exerciseRepository
        self.reportRepository = reportRepository
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

    /// Applies one server-durable approval after an explicit user decision.
    func approve(_ operation: InboxOperationDTO) async -> InboxAckResult {
        do {
            let approvalRequired = try approvalRequirement(for: operation.op)
            try validateApprovalFlag(
                operation,
                expected: approvalRequired
            )
            guard approvalRequired else {
                throw InboxApplyError.malformedPayload(
                    "Operation does not require approval"
                )
            }
            guard operation.status == "awaitingApproval" else {
                throw InboxApplyError.malformedPayload(
                    "Expected awaitingApproval status, got \(operation.status)"
                )
            }
            try await apply(operation)
            return InboxAckResult(id: operation.id, status: .applied)
        } catch {
            return InboxAckResult(
                id: operation.id,
                status: .failed,
                error: error.localizedDescription
            )
        }
    }

    /// Declining an approval is intentionally repository-free.
    func decline(_ operation: InboxOperationDTO) -> InboxAckResult {
        do {
            let approvalRequired = try approvalRequirement(for: operation.op)
            try validateApprovalFlag(
                operation,
                expected: approvalRequired
            )
            guard approvalRequired,
                  operation.status == "awaitingApproval" else {
                throw InboxApplyError.malformedPayload(
                    "Expected an approval-required awaitingApproval operation"
                )
            }
            return InboxAckResult(id: operation.id, status: .rejected)
        } catch {
            return InboxAckResult(
                id: operation.id,
                status: .failed,
                error: error.localizedDescription
            )
        }
    }

    private func process(_ operation: InboxOperationDTO) async throws -> InboxAckResult {
        guard operation.status == "pending" else {
            throw InboxApplyError.malformedPayload(
                "Expected pending status, got \(operation.status)"
            )
        }
        let approvalRequired = try approvalRequirement(for: operation.op)
        try validateApprovalFlag(operation, expected: approvalRequired)
        guard !approvalRequired else {
            return InboxAckResult(
                id: operation.id,
                status: .awaitingApproval
            )
        }

        try await apply(operation)
        return InboxAckResult(id: operation.id, status: .applied)
    }

    private func apply(_ operation: InboxOperationDTO) async throws {
        switch operation.op {
        case "createTemplate":
            let payload = try decode(CreateTemplatePayload.self, from: operation.payload)
            try await createTemplate(
                payload,
                id: try entityID(for: operation)
            )

        case "createCustomExercise":
            let payload = try decode(CreateCustomExercisePayload.self, from: operation.payload)
            try await createCustomExercise(
                payload,
                id: try entityID(for: operation)
            )

        case "resolveExerciseReport":
            let payload = try decode(
                ResolveExerciseReportPayload.self, from: operation.payload
            )
            try await resolveExerciseReport(payload)

        case "updateTemplate":
            let payload = try decode(UpdateTemplatePayload.self, from: operation.payload)
            try validateUpdatePayload(payload)
            try await updateTemplate(payload)

        case "deleteTemplate":
            let payload = try decode(DeleteTemplatePayload.self, from: operation.payload)
            try validateDeletePayload(payload)
            try await deleteTemplate(payload)

        default:
            throw InboxApplyError.unknownOperation(operation.op)
        }
    }

    private func createTemplate(
        _ payload: CreateTemplatePayload,
        id: UUID
    ) async throws {
        try validateTemplatePayload(name: payload.name, exercises: payload.exercises)
        guard try await templateRepository.fetch(id: id) == nil else {
            return
        }
        let resolved = try await resolve(payload.exercises)
        let template = WorkoutTemplate(
            id: id,
            name: payload.name,
            notes: payload.notes
        )
        template.exercises = makeTemplateExercises(from: resolved)
        try await templateRepository.save(template)
    }

    private func createCustomExercise(
        _ payload: CreateCustomExercisePayload,
        id: UUID
    ) async throws {
        let name = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw InboxApplyError.malformedPayload(
                "Custom exercise name must not be empty"
            )
        }
        guard let externalId = payload.externalId,
              isValidCustomExternalId(externalId, operationId: id) else {
            throw InboxApplyError.invalidCustomExternalId(
                payload.externalId ?? "<missing>"
            )
        }
        guard try await exerciseRepository.fetch(id: id) == nil else {
            return
        }
        let exercise = Exercise(
            id: id,
            name: name,
            equipment: payload.equipment,
            instructions: payload.instructions ?? [],
            primaryMuscles: payload.primaryMuscles ?? [],
            secondaryMuscles: payload.secondaryMuscles ?? [],
            isCustom: true,
            externalId: externalId,
            notes: payload.notes
        )
        try await exerciseRepository.save(exercise)
    }

    /// Closing out a report is deliberately approval-free: the whole point of
    /// the status lifecycle is that the AI can clear the backlog without a
    /// second confirmation step, and the write is trivially reversible.
    private func resolveExerciseReport(
        _ payload: ResolveExerciseReportPayload
    ) async throws {
        guard let id = UUID(uuidString: payload.id) else {
            throw InboxApplyError.invalidReportId(payload.id)
        }
        guard let report = try await reportRepository.fetch(id: id) else {
            throw InboxApplyError.reportNotFound(payload.id)
        }

        let status: ReportStatus
        switch payload.status {
        case nil, ReportStatus.resolved.rawValue:
            status = .resolved
        case ReportStatus.acknowledged.rawValue:
            status = .acknowledged
        case let other?:
            // `.open` is rejected too: an inbox operation exists to close a
            // report, never to reopen one behind the user's back.
            throw InboxApplyError.invalidReportStatus(other)
        }

        report.status = status
        if let resolution = payload.resolution {
            report.resolution = resolution
        }
        report.recordChange()
        try await reportRepository.save(report)
    }

    private func approvalRequirement(for operation: String) throws -> Bool {
        switch operation {
        case "updateTemplate", "deleteTemplate":
            return true
        case "createTemplate", "createCustomExercise", "resolveExerciseReport":
            return false
        default:
            throw InboxApplyError.unknownOperation(operation)
        }
    }

    private func validateApprovalFlag(
        _ operation: InboxOperationDTO,
        expected: Bool
    ) throws {
        guard operation.requiresApproval == expected else {
            throw InboxApplyError.malformedPayload(
                "\(operation.op) approval flag mismatch: "
                    + "stored \(operation.requiresApproval), expected \(expected)"
            )
        }
    }

    private func isValidCustomExternalId(
        _ externalId: String,
        operationId: UUID
    ) -> Bool {
        let parts = externalId.split(
            separator: ":",
            omittingEmptySubsequences: false
        )
        guard parts.count == 3,
              parts[0] == "custom",
              (1...64).contains(parts[1].count),
              parts[1].range(
                of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#,
                options: .regularExpression
              ) != nil,
              let suffix = UUID(uuidString: String(parts[2])) else {
            return false
        }
        return suffix == operationId
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

    private func entityID(for operation: InboxOperationDTO) throws -> UUID {
        guard let id = UUID(uuidString: operation.id) else {
            throw InboxApplyError.invalidOperationId(operation.id)
        }
        return id
    }

}
