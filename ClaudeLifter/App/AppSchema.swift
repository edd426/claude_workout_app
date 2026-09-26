import Foundation
import SwiftData

/// Single source of truth for the app's persisted model types.
///
/// Every `ModelContainer` in the app — production, recovery, and tests — must be
/// built from this schema. Adding a model? Add it HERE, bump the version, and add
/// a `MigrationStage` to `ClaudeLifterMigrationPlan`. Never list model types inline
/// at a container call site again (that triplication is how issue #72 happened).
enum ClaudeLifterSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self, ExerciseTag.self, WorkoutSet.self,
            WorkoutExercise.self, TemplateExercise.self, Workout.self,
            WorkoutTemplate.self, AIChatMessage.self, ProactiveInsight.self,
            TrainingPreference.self, PersonalRecord.self
        ]
    }
}

/// V2 (issue #80): adds `BodyWeightEntry`. V1 above is IMMUTABLE history —
/// never edit an existing version's model list; add a new version and a stage.
enum ClaudeLifterSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self, ExerciseTag.self, WorkoutSet.self,
            WorkoutExercise.self, TemplateExercise.self, Workout.self,
            WorkoutTemplate.self, AIChatMessage.self, ProactiveInsight.self,
            TrainingPreference.self, PersonalRecord.self,
            BodyWeightEntry.self
        ]
    }
}

/// V3 (issue #135): adds `ExerciseReport`. V1 and V2 above are IMMUTABLE
/// history — never edit an existing version's model list.
enum ClaudeLifterSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self, ExerciseTag.self, WorkoutSet.self,
            WorkoutExercise.self, TemplateExercise.self, Workout.self,
            WorkoutTemplate.self, AIChatMessage.self, ProactiveInsight.self,
            TrainingPreference.self, PersonalRecord.self,
            BodyWeightEntry.self, ExerciseReport.self
        ]
    }
}

/// V4 (issue #128): adds template provenance as two NEW models rather than as
/// properties on `Workout` / `WorkoutExercise`.
///
/// That shape is forced, and the reason is worth knowing before anyone tries
/// again. The `models` lists above name **live** Swift types, so they are not
/// frozen history: adding a property to `Workout` changes what V1, V2 and V3
/// mean as well as V4. All four then hash identically and SwiftData refuses the
/// container with `NSInvalidArgumentException: Duplicate version checksums
/// detected` — a hard crash on the first launch after the update, not a
/// recoverable migration failure.
///
/// So with live types, a new version can only differ by its model LIST. A
/// property-only change cannot be versioned here at all without freezing
/// copies of every affected model (and everything they relate to).
///
/// Provenance is a frozen snapshot anyway, so a separate model is the better
/// shape regardless: it cannot be mutated by ordinary workout edits, and it
/// references the workout by plain UUID rather than a SwiftData relationship —
/// deliberately, since a relationship would mean a stored property on
/// `Workout` and reintroduce the exact problem.
///
/// V1–V3 above are IMMUTABLE history — never edit an existing version's list.
enum ClaudeLifterSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self, ExerciseTag.self, WorkoutSet.self,
            WorkoutExercise.self, TemplateExercise.self, Workout.self,
            WorkoutTemplate.self, AIChatMessage.self, ProactiveInsight.self,
            TrainingPreference.self, PersonalRecord.self,
            BodyWeightEntry.self, ExerciseReport.self,
            WorkoutTemplateBaseline.self, WorkoutExerciseBaseline.self
        ]
    }
}

/// The schema version the app currently runs.
typealias CurrentSchema = ClaudeLifterSchemaV4

enum ClaudeLifterMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            ClaudeLifterSchemaV1.self, ClaudeLifterSchemaV2.self,
            ClaudeLifterSchemaV3.self, ClaudeLifterSchemaV4.self
        ]
    }

    /// V1→V2 is purely additive (one new model), so lightweight migration
    /// suffices. A schema change without a stage here fails container
    /// creation — which quarantines instead of wiping (issue #72).
    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: ClaudeLifterSchemaV1.self,
        toVersion: ClaudeLifterSchemaV2.self
    )

    /// V2→V3 is purely additive (one new model), so lightweight again.
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: ClaudeLifterSchemaV2.self,
        toVersion: ClaudeLifterSchemaV3.self
    )

    /// V3→V4 adds two new models and touches no existing one, so lightweight —
    /// the same shape as V1→V2 and V2→V3. Verified against a real on-disk V3
    /// store in `TemplateProvenanceMigrationTests`; an in-memory container does
    /// not exercise migration at all and would have passed either way.
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: ClaudeLifterSchemaV3.self,
        toVersion: ClaudeLifterSchemaV4.self
    )
}
