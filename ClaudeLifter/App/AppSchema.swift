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

/// The schema version the app currently runs.
typealias CurrentSchema = ClaudeLifterSchemaV1

enum ClaudeLifterMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ClaudeLifterSchemaV1.self]
    }

    /// Empty until a V2 exists. A schema change without a stage here will fail
    /// container creation — which now quarantines instead of wiping (issue #72).
    static var stages: [MigrationStage] {
        []
    }
}
