import Foundation
import SwiftData

/// A substitute listed on a template exercise: "if the rack is taken, do this
/// instead." Backs the one-tap swap when a machine is occupied.
///
/// `templateExerciseId` is a plain UUID, NOT a relationship. A relationship
/// would need a stored property (or inverse) on `TemplateExercise`, and a
/// property-only change to an existing model cannot be versioned in this app
/// (see the note on `ClaudeLifterSchemaV4`). The cost is that nothing deletes
/// these automatically: `SwiftDataTemplateRepository` removes orphans on every
/// template save and delete.
///
/// The exercise is referenced by `externalId` (catalog id, or a `custom:` id),
/// never by `Exercise.id`, which is minted per install and meaningless after a
/// reinstall. Same rule as the MCP write path (`infra/MCP_WRITE_PATH.md`).
///
/// Schema V5, a NEW model.
@Model
final class ExerciseAlternative: SyncableModel {
    @Attribute(.unique) var id: UUID
    var templateExerciseId: UUID
    var externalId: String
    /// Position among this template exercise's alternatives, from 0.
    var order: Int
    /// e.g. "if the rack is taken".
    var note: String?
    var syncStatusRaw: String = "pending"
    var lastModified: Date

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        templateExerciseId: UUID,
        externalId: String,
        order: Int,
        note: String? = nil,
        syncStatus: SyncStatus = .pending,
        lastModified: Date = .now
    ) {
        self.id = id
        self.templateExerciseId = templateExerciseId
        self.externalId = externalId
        self.order = order
        self.note = note
        self.syncStatusRaw = syncStatus.rawValue
        self.lastModified = lastModified
    }
}

/// Input for `ExerciseAlternativeRepository.replaceAlternatives`: what to list,
/// in order. Mirrors the inbox payload shape `{externalId, note?}`.
struct AlternativeSpec: Equatable, Sendable {
    let externalId: String
    let note: String?

    init(externalId: String, note: String? = nil) {
        self.externalId = externalId
        self.note = note
    }
}
