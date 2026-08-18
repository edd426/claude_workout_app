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

/// The schema version the app currently runs.
typealias CurrentSchema = ClaudeLifterSchemaV3

enum ClaudeLifterMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            ClaudeLifterSchemaV1.self, ClaudeLifterSchemaV2.self,
            ClaudeLifterSchemaV3.self
        ]
    }

    /// V1→V2 is purely additive (one new model), so lightweight migration
    /// suffices. A schema change without a stage here fails container
    /// creation — which quarantines instead of wiping (issue #72).
    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
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
}
