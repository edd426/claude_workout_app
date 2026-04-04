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

    // MARK: - Factory methods (create from DTO)

    @Test("createWorkout creates Workout from WorkoutDTO with exercises and sets")
    @MainActor
    func createWorkoutFromDTO() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)
        try context.save()

        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        let setDTO = WorkoutSetDTO(
            id: UUID(), order: 0, weight: 80.0, weightUnit: "kg",
            reps: 5, isCompleted: true, completedAt: Date(), notes: nil
        )
        let weDTO = WorkoutExerciseDTO(
            id: UUID(), exerciseId: exercise.id, order: 0,
            notes: "flat bench", restSeconds: 120, sets: [setDTO]
        )
        let workoutDTO = WorkoutDTO(
            id: UUID(), templateId: nil, name: "Server Push Day",
            startedAt: Date(), completedAt: Date(), notes: "from server",
            lastModified: Date(), exercises: [weDTO]
        )

        let workout = try await SyncMapper.createWorkout(from: workoutDTO, exerciseRepository: exerciseRepo)

        #expect(workout.id == workoutDTO.id)
        #expect(workout.name == "Server Push Day")
        #expect(workout.notes == "from server")
        #expect(workout.syncStatus == .synced)
        #expect(workout.exercises.count == 1)
        #expect(workout.exercises[0].exercise?.id == exercise.id)
        #expect(workout.exercises[0].sets.count == 1)
        #expect(workout.exercises[0].sets[0].weight == 80.0)
        #expect(workout.exercises[0].sets[0].reps == 5)
    }

    @Test("createWorkout skips exercises with unknown exerciseId")
    @MainActor
    func createWorkoutSkipsUnknownExercise() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        let weDTO = WorkoutExerciseDTO(
            id: UUID(), exerciseId: UUID(), order: 0,
            notes: nil, restSeconds: 90, sets: []
        )
        let workoutDTO = WorkoutDTO(
            id: UUID(), templateId: nil, name: "Ghost Workout",
            startedAt: Date(), completedAt: nil, notes: nil,
            lastModified: Date(), exercises: [weDTO]
        )

        let workout = try await SyncMapper.createWorkout(from: workoutDTO, exerciseRepository: exerciseRepo)
        #expect(workout.exercises.count == 0)
    }

    @Test("createTemplate creates WorkoutTemplate from TemplateDTO with exercises")
    @MainActor
    func createTemplateFromDTO() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Squat")
        context.insert(exercise)
        try context.save()

        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        let teDTO = TemplateExerciseDTO(
            id: UUID(), exerciseId: exercise.id, order: 0,
            defaultSets: 4, defaultReps: 6, defaultWeight: 100.0,
            defaultRestSeconds: 180, notes: "go deep"
        )
        let templateDTO = TemplateDTO(
            id: UUID(), name: "Server Leg Day", notes: "heavy squats",
            createdAt: Date(), updatedAt: Date(), lastPerformedAt: nil,
            timesPerformed: 5, lastModified: Date(), exercises: [teDTO]
        )

        let template = try await SyncMapper.createTemplate(from: templateDTO, exerciseRepository: exerciseRepo)

        #expect(template.id == templateDTO.id)
        #expect(template.name == "Server Leg Day")
        #expect(template.timesPerformed == 5)
        #expect(template.syncStatus == .synced)
        #expect(template.exercises.count == 1)
        #expect(template.exercises[0].exercise?.id == exercise.id)
        #expect(template.exercises[0].defaultSets == 4)
        #expect(template.exercises[0].defaultWeight == 100.0)
    }

    @Test("createInsight creates ProactiveInsight from InsightDTO")
    func createInsightFromDTO() {
        let dto = InsightDTO(
            id: UUID(), content: "Train legs!", type: "warning",
            generatedAt: Date(), isRead: true, lastModified: Date()
        )
        let insight = SyncMapper.createInsight(from: dto)
        #expect(insight.id == dto.id)
        #expect(insight.content == "Train legs!")
        #expect(insight.type == .warning)
        #expect(insight.isRead == true)
        #expect(insight.syncStatus == .synced)
    }

    @Test("createPreference creates TrainingPreference from PreferenceDTO")
    func createPreferenceFromDTO() {
        let dto = PreferenceDTO(
            id: UUID(), key: "injury", value: "bad left shoulder",
            source: "user_stated", lastModified: Date()
        )
        let pref = SyncMapper.createPreference(from: dto)
        #expect(pref.id == dto.id)
        #expect(pref.key == "injury")
        #expect(pref.value == "bad left shoulder")
        #expect(pref.source == "user_stated")
        #expect(pref.syncStatus == .synced)
    }

    // MARK: - Nested merge (applyDTO with exercises)

    @Test("applyDTO merges workout exercises: inserts new, updates existing, removes deleted")
    @MainActor
    func applyWorkoutDTOMergesExercises() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exerciseA = TestFixtures.makeExercise(name: "Bench Press")
        let exerciseB = TestFixtures.makeExercise(name: "Squat")
        context.insert(exerciseA)
        context.insert(exerciseB)

        let workout = TestFixtures.makeWorkout(name: "Push Day")
        context.insert(workout)

        // Existing exercise that will be updated
        let existingWE = TestFixtures.makeWorkoutExercise(
            exercise: exerciseA, order: 0, sets: [(60, 8)], in: context
        )
        workout.exercises.append(existingWE)

        // Another existing exercise that will be removed (not in remote)
        let removedWE = WorkoutExercise(order: 1, exercise: exerciseB)
        context.insert(removedWE)
        workout.exercises.append(removedWE)
        try context.save()

        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        // DTO has: existing exercise (updated order), plus a new exercise
        let existingSetDTO = WorkoutSetDTO(
            id: existingWE.sets[0].id, order: 0, weight: 70.0, weightUnit: "kg",
            reps: 6, isCompleted: true, completedAt: Date(), notes: nil
        )
        let existingWEDTO = WorkoutExerciseDTO(
            id: existingWE.id, exerciseId: exerciseA.id, order: 0,
            notes: "updated notes", restSeconds: 60, sets: [existingSetDTO]
        )
        let newSetDTO = WorkoutSetDTO(
            id: UUID(), order: 0, weight: 100.0, weightUnit: "kg",
            reps: 3, isCompleted: true, completedAt: Date(), notes: nil
        )
        let newWEDTO = WorkoutExerciseDTO(
            id: UUID(), exerciseId: exerciseB.id, order: 1,
            notes: "new from server", restSeconds: 120, sets: [newSetDTO]
        )

        let dto = WorkoutDTO(
            id: workout.id, templateId: nil, name: "Updated Push Day",
            startedAt: workout.startedAt, completedAt: nil, notes: nil,
            lastModified: Date(timeIntervalSinceNow: 100),
            exercises: [existingWEDTO, newWEDTO]
        )

        try await SyncMapper.applyDTO(dto, to: workout, exerciseRepository: exerciseRepo)

        #expect(workout.name == "Updated Push Day")
        #expect(workout.exercises.count == 2)

        // Check existing exercise was updated
        let updated = workout.exercises.first { $0.id == existingWE.id }
        #expect(updated != nil)
        #expect(updated?.notes == "updated notes")
        #expect(updated?.restSeconds == 60)
        #expect(updated?.sets[0].weight == 70.0)
        #expect(updated?.sets[0].reps == 6)

        // Check new exercise was inserted
        let inserted = workout.exercises.first { $0.id == newWEDTO.id }
        #expect(inserted != nil)
        #expect(inserted?.exercise?.id == exerciseB.id)
        #expect(inserted?.sets.count == 1)
        #expect(inserted?.sets[0].weight == 100.0)

        // Check removed exercise is gone
        let removed = workout.exercises.first { $0.id == removedWE.id }
        #expect(removed == nil)
    }

    @Test("applyDTO merges template exercises: inserts new, updates existing, removes deleted")
    @MainActor
    func applyTemplateDTOMergesExercises() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "OHP")
        context.insert(exercise)

        let template = TestFixtures.makeTemplate(name: "Push Day")
        context.insert(template)

        let existingTE = TemplateExercise(order: 0, exercise: exercise, defaultSets: 3, defaultReps: 8)
        context.insert(existingTE)
        template.exercises.append(existingTE)
        try context.save()

        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        let updatedTEDTO = TemplateExerciseDTO(
            id: existingTE.id, exerciseId: exercise.id, order: 0,
            defaultSets: 5, defaultReps: 5, defaultWeight: 60.0,
            defaultRestSeconds: 120, notes: "updated"
        )
        let dto = TemplateDTO(
            id: template.id, name: "Updated Push Day", notes: nil,
            createdAt: template.createdAt, updatedAt: Date(),
            lastPerformedAt: nil, timesPerformed: 10,
            lastModified: Date(timeIntervalSinceNow: 100),
            exercises: [updatedTEDTO]
        )

        try await SyncMapper.applyDTO(dto, to: template, exerciseRepository: exerciseRepo)

        #expect(template.name == "Updated Push Day")
        #expect(template.exercises.count == 1)
        #expect(template.exercises[0].defaultSets == 5)
        #expect(template.exercises[0].defaultReps == 5)
        #expect(template.exercises[0].defaultWeight == 60.0)
    }
}
