import Foundation

// Wire format DTOs for sync API

struct WorkoutSetDTO: Codable, Sendable {
    let id: UUID
    let order: Int
    let weight: Double?
    let weightUnit: String  // "kg" or "lbs"
    let reps: Int?
    let isCompleted: Bool
    let completedAt: Date?
    let notes: String?
}

struct WorkoutExerciseDTO: Codable, Sendable {
    let id: UUID
    let exerciseId: UUID
    let exerciseName: String?
    let order: Int
    let notes: String?
    let restSeconds: Int
    let sets: [WorkoutSetDTO]

    init(
        id: UUID,
        exerciseId: UUID,
        exerciseName: String? = nil,
        order: Int,
        notes: String?,
        restSeconds: Int,
        sets: [WorkoutSetDTO]
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.order = order
        self.notes = notes
        self.restSeconds = restSeconds
        self.sets = sets
    }
}

struct WorkoutDTO: Codable, Sendable {
    let id: UUID
    let templateId: UUID?
    let name: String
    let startedAt: Date
    let completedAt: Date?
    let notes: String?
    let lastModified: Date
    let exercises: [WorkoutExerciseDTO]
}

struct TemplateExerciseDTO: Codable, Sendable {
    let id: UUID
    let exerciseId: UUID
    let exerciseName: String?
    let order: Int
    let defaultSets: Int
    let defaultReps: Int
    let defaultWeight: Double?
    let defaultRestSeconds: Int
    let notes: String?

    init(
        id: UUID,
        exerciseId: UUID,
        exerciseName: String? = nil,
        order: Int,
        defaultSets: Int,
        defaultReps: Int,
        defaultWeight: Double?,
        defaultRestSeconds: Int,
        notes: String?
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.order = order
        self.defaultSets = defaultSets
        self.defaultReps = defaultReps
        self.defaultWeight = defaultWeight
        self.defaultRestSeconds = defaultRestSeconds
        self.notes = notes
    }
}

struct TemplateDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let lastPerformedAt: Date?
    let timesPerformed: Int
    let lastModified: Date
    let exercises: [TemplateExerciseDTO]
}

struct ChatMessageDTO: Codable, Sendable {
    let id: UUID
    let workoutId: UUID?
    let role: String  // "user", "assistant", "system"
    let content: String
    let timestamp: Date
}

struct InsightDTO: Codable, Sendable {
    let id: UUID
    let content: String
    let type: String  // "suggestion", "warning", "encouragement"
    let generatedAt: Date
    let isRead: Bool
    let lastModified: Date
}

struct PreferenceDTO: Codable, Sendable {
    let id: UUID
    let key: String
    let value: String
    let source: String?
    let lastModified: Date
}

// Sync request/response types

struct SyncPullRequest: Codable, Sendable {
    let lastSyncTimestamp: Date?
    let collections: [String]
}

struct SyncPullResponse: Codable, Sendable {
    let workouts: [WorkoutDTO]
    let templates: [TemplateDTO]
    let chat: [ChatMessageDTO]
    let insights: [InsightDTO]
    let preferences: [PreferenceDTO]
    let serverTimestamp: Date
}

struct SyncPushRequest: Codable, Sendable {
    let workouts: [WorkoutDTO]
    let templates: [TemplateDTO]
    let chat: [ChatMessageDTO]
    let insights: [InsightDTO]
    let preferences: [PreferenceDTO]
}

struct SyncPushResponse: Codable, Sendable {
    let accepted: Int
    let conflicts: Int
    let serverTimestamp: Date
}
