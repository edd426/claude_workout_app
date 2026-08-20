import Foundation

enum TemplateChangeApplyError: Error, LocalizedError, Equatable {
    case templateNotFound
    case conflict
    case unresolvedExercise(String)

    var errorDescription: String? {
        switch self {
        case .templateNotFound:
            return "That template no longer exists, so it wasn't updated. Your workout is saved."
        case .conflict:
            return "The template changed somewhere else since this workout started, so nothing was applied. Your workout is saved."
        case .unresolvedExercise(let name):
            return "\(name) couldn't be found in your library, so the template wasn't updated. Your workout is saved."
        }
    }
}

/// Applies a reviewed subset of a `TemplateChangeSet` to its template (#130).
///
/// Three rules, in order of importance:
///
/// 1. **The workout is already saved before this runs.** Nothing here can undo,
///    hide or delay it. A failure costs a template update and nothing else,
///    which is why every error message says so.
/// 2. **All or nothing.** The template is rebuilt in memory and saved once, so
///    a partial application is not a state the user can end up in.
/// 3. **Re-fetch and re-check first.** The template is read fresh and its
///    revision compared again — the review sheet may have sat on screen while
///    the Coach or the MCP inbox changed the same template.
@MainActor
struct TemplateChangeApplier {
    private let templateRepository: any TemplateRepository
    private let exerciseRepository: any ExerciseRepository

    init(
        templateRepository: any TemplateRepository,
        exerciseRepository: any ExerciseRepository
    ) {
        self.templateRepository = templateRepository
        self.exerciseRepository = exerciseRepository
    }

    /// - Parameters:
    ///   - changes: only the changes the user actually selected.
    ///   - changeSet: the full set, for its template id and captured revision.
    ///   - capturedRevision: the template's `lastModified` when the workout
    ///     started, re-checked here rather than trusted from detection time.
    func apply(
        _ changes: [TemplateChange],
        from changeSet: TemplateChangeSet,
        capturedRevision: Date?
    ) async throws {
        guard !changes.isEmpty else { return }

        guard let template = try await templateRepository.fetch(id: changeSet.templateId) else {
            throw TemplateChangeApplyError.templateNotFound
        }
        if let capturedRevision, template.lastModified > capturedRevision {
            throw TemplateChangeApplyError.conflict
        }

        // Work on a plain list first: every reference is resolved and every
        // edit applied in memory before anything is written.
        var planned = template.exercises.sorted { $0.order < $1.order }

        for change in changes {
            switch change {
            case .removedExercise(let removal):
                planned.removeAll { $0.id == removal.sourceTemplateExerciseId }

            case .setCountChanged(let change):
                planned.first { $0.id == change.sourceTemplateExerciseId }?
                    .defaultSets = change.to

            case .cueChanged(let change):
                planned.first { $0.id == change.sourceTemplateExerciseId }?
                    .notes = change.to

            case .reordered(let reorder):
                // Reindex to the order the workout ran, keeping any template
                // exercise the workout never mentioned at the end rather than
                // dropping it.
                var byId = Dictionary(
                    planned.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                var reordered: [TemplateExercise] = []
                for id in reorder.sourceTemplateExerciseIds {
                    if let te = byId.removeValue(forKey: id) {
                        reordered.append(te)
                    }
                }
                reordered.append(contentsOf: planned.filter { byId[$0.id] != nil })
                planned = reordered

            case .addedExercise(let addition):
                let exercise = try await resolve(addition)
                planned.append(TemplateExercise(
                    order: planned.count,
                    exercise: exercise,
                    defaultSets: addition.sets,
                    defaultReps: addition.reps ?? 8,
                    defaultWeight: nil,
                    defaultRestSeconds: addition.restSeconds,
                    notes: nil
                ))
            }
        }

        // Normalise ordering so the template never carries gaps or duplicates,
        // whatever combination of changes was selected.
        for (index, te) in planned.enumerated() {
            te.order = index
        }

        template.exercises = planned
        template.updatedAt = .now
        template.recordChange()
        try await templateRepository.save(template)
    }

    /// Resolve by `externalId` first — the stable catalog id — and fall back to
    /// the local UUID for a custom exercise, which has no external id.
    private func resolve(
        _ addition: TemplateChange.AddedExercise
    ) async throws -> Exercise {
        if let externalId = addition.externalId,
           let match = try await exerciseRepository.fetchByExternalId(externalId) {
            return match
        }
        if let match = try await exerciseRepository.fetch(id: addition.exerciseId) {
            return match
        }
        throw TemplateChangeApplyError.unresolvedExercise(addition.name)
    }
}
