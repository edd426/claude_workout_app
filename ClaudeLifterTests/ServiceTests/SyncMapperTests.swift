import Testing
import Foundation
@testable import ClaudeLifter

@Suite("SyncMapper Tests")
struct SyncMapperTests {
    // MARK: - Workout → DTO

    @Test("Workout maps to WorkoutDTO correctly")
    func workoutToDTO() {
        let workout = TestFixtures.makeWorkout(name: "Push Day")
        let dto = SyncMapper.toDTO(workout)
        #expect(dto.id == workout.id)
        #expect(dto.name == workout.name)
        #expect(dto.templateId == workout.templateId)
        #expect(dto.notes == workout.notes)
        #expect(dto.lastModified == workout.lastModified)
    }

    @Test("Workout with exercises maps nested exercise DTOs")
    @MainActor
    func workoutWithExercisesToDTO() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)

        let workout = TestFixtures.makeWorkout(name: "Push Day")
        context.insert(workout)

        let we = TestFixtures.makeWorkoutExercise(
            exercise: exercise,
            order: 0,
            sets: [(60, 8), (65, 6)],
            in: context
        )
        workout.exercises.append(we)
        try context.save()

        let dto = SyncMapper.toDTO(workout)
        #expect(dto.exercises.count == 1)
        #expect(dto.exercises[0].exerciseId == exercise.id)
        #expect(dto.exercises[0].sets.count == 2)
    }

    @Test("WorkoutSet maps weight unit as string")
    @MainActor
    func workoutSetWeightUnit() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise()
        context.insert(exercise)

        let workout = TestFixtures.makeWorkout()
        context.insert(workout)

        let we = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(we)
        workout.exercises.append(we)

        let set = WorkoutSet(order: 0, weight: 100.0, weightUnit: .lbs, reps: 5, isCompleted: true, completedAt: .now)
        context.insert(set)
        we.sets.append(set)
        try context.save()

        let dto = SyncMapper.toDTO(workout)
        #expect(dto.exercises[0].sets[0].weightUnit == "lbs")
    }

    // MARK: - Template → DTO

    @Test("WorkoutTemplate maps to TemplateDTO correctly")
    func templateToDTO() {
        let template = TestFixtures.makeTemplate(name: "Wednesday Push Day", timesPerformed: 3)
        let dto = SyncMapper.toDTO(template)
        #expect(dto.id == template.id)
        #expect(dto.name == template.name)
        #expect(dto.timesPerformed == template.timesPerformed)
        #expect(dto.notes == template.notes)
        #expect(dto.lastModified == template.lastModified)
    }

    // MARK: - AIChatMessage → DTO

    @Test("AIChatMessage maps to ChatMessageDTO correctly")
    func chatMessageToDTO() {
        let msg = TestFixtures.makeChatMessage(role: .assistant, content: "Great progress!")
        let dto = SyncMapper.toDTO(msg)
        #expect(dto.id == msg.id)
        #expect(dto.role == "assistant")
        #expect(dto.content == msg.content)
        #expect(dto.workoutId == msg.workoutId)
        #expect(dto.timestamp == msg.timestamp)
    }

    @Test("AIChatMessage user role maps to 'user' string")
    func chatMessageUserRole() {
        let msg = AIChatMessage(role: .user, content: "How much?")
        let dto = SyncMapper.toDTO(msg)
        #expect(dto.role == "user")
    }

    @Test("AIChatMessage system role maps to 'system' string")
    func chatMessageSystemRole() {
        let msg = AIChatMessage(role: .system, content: "You are a trainer.")
        let dto = SyncMapper.toDTO(msg)
        #expect(dto.role == "system")
    }

    // MARK: - ProactiveInsight → DTO

    @Test("ProactiveInsight maps to InsightDTO correctly")
    func insightToDTO() {
        let insight = TestFixtures.makeInsight(content: "Train legs!", type: .warning)
        let dto = SyncMapper.toDTO(insight)
        #expect(dto.id == insight.id)
        #expect(dto.content == insight.content)
        #expect(dto.type == "warning")
        #expect(dto.isRead == insight.isRead)
        #expect(dto.lastModified == insight.lastModified)
    }

    @Test("InsightType suggestion maps to 'suggestion' string")
    func insightSuggestionType() {
        let insight = ProactiveInsight(content: "Try dropsets", type: .suggestion)
        let dto = SyncMapper.toDTO(insight)
        #expect(dto.type == "suggestion")
    }

    @Test("InsightType encouragement maps to 'encouragement' string")
    func insightEncouragementType() {
        let insight = ProactiveInsight(content: "Great week!", type: .encouragement)
        let dto = SyncMapper.toDTO(insight)
        #expect(dto.type == "encouragement")
    }

    // MARK: - TrainingPreference → DTO

    @Test("TrainingPreference maps to PreferenceDTO correctly")
    func preferenceToDTO() {
        let pref = TestFixtures.makeTrainingPreference(key: "style", value: "strength", source: "user_stated")
        let dto = SyncMapper.toDTO(pref)
        #expect(dto.id == pref.id)
        #expect(dto.key == pref.key)
        #expect(dto.value == pref.value)
        #expect(dto.source == pref.source)
        #expect(dto.lastModified == pref.lastModified)
    }

    // MARK: - applyDTO (reverse mapping)

    @Test("applyDTO updates workout fields from WorkoutDTO")
    func applyWorkoutDTO() {
        let workout = TestFixtures.makeWorkout(name: "Old Name")
        let newModified = Date(timeIntervalSinceNow: 100)
        let dto = WorkoutDTO(
            id: workout.id,
            templateId: nil,
            name: "New Name",
            startedAt: workout.startedAt,
            completedAt: nil,
            notes: "updated notes",
            lastModified: newModified,
            exercises: []
        )
        SyncMapper.applyDTO(dto, to: workout)
        #expect(workout.name == "New Name")
        #expect(workout.notes == "updated notes")
        #expect(workout.lastModified == newModified)
        #expect(workout.syncStatus == .synced)
    }

    @Test("applyDTO marks workout as synced")
    func applyWorkoutDTOMarksSynced() {
        let workout = TestFixtures.makeWorkout()
        #expect(workout.syncStatus == .pending)
        let dto = WorkoutDTO(
            id: workout.id,
            templateId: nil,
            name: workout.name,
            startedAt: workout.startedAt,
            completedAt: nil,
            notes: nil,
            lastModified: .now,
            exercises: []
        )
        SyncMapper.applyDTO(dto, to: workout)
        #expect(workout.syncStatus == .synced)
    }
}
