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

    // MARK: - Exercise → DTO

    @Test("Exercise maps to ExerciseDTO including tags")
    @MainActor
    func exerciseToDTO() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "My Machine Press", isCustom: true)
        exercise.notes = "pin 7"
        context.insert(exercise)
        let tag = ExerciseTag(category: "muscle_group", value: "chest")
        context.insert(tag)
        exercise.tags = [tag]
        try context.save()

        let dto = SyncMapper.toDTO(exercise)
        #expect(dto.id == exercise.id)
        #expect(dto.name == "My Machine Press")
        #expect(dto.isCustom == true)
        #expect(dto.notes == "pin 7")
        #expect(dto.primaryMuscles == exercise.primaryMuscles)
        #expect(dto.tags.count == 1)
        #expect(dto.tags[0].category == "muscle_group")
        #expect(dto.tags[0].value == "chest")
    }

    @Test("createExercise builds an Exercise from ExerciseDTO (tags attached by caller)")
    func createExerciseFromDTO() {
        let dto = ExerciseDTO(
            id: UUID(), name: "Cloud Custom", force: "pull", level: "advanced",
            mechanic: "compound", equipment: "machine",
            instructions: ["Pull hard"], primaryMuscles: ["back"],
            secondaryMuscles: ["biceps"], isCustom: true, externalId: nil,
            notes: "seat 3", imageURL: nil, photoURL: nil,
            tags: [ExerciseTagDTO(category: "equipment", value: "machine")]
        )
        let exercise = SyncMapper.createExercise(from: dto)
        #expect(exercise.id == dto.id)
        #expect(exercise.name == "Cloud Custom")
        #expect(exercise.isCustom == true)
        #expect(exercise.equipment == "machine")
        #expect(exercise.notes == "seat 3")
        #expect(exercise.instructions == ["Pull hard"])
        // Tags are deliberately NOT attached here — SwiftData relationship
        // objects are attached after the exercise is inserted into a context.
        #expect(exercise.tags.isEmpty)
    }

    // MARK: - BodyWeightEntry ↔ DTO

    @Test("BodyWeightEntry maps to BodyWeightEntryDTO")
    func bodyWeightEntryToDTO() {
        let sampleUUID = UUID()
        let entry = BodyWeightEntry(
            weightKg: 83.2,
            recordedAt: Date(timeIntervalSinceReferenceDate: 500),
            source: "healthkit",
            healthKitSampleUUID: sampleUUID
        )
        let dto = SyncMapper.toDTO(entry)
        #expect(dto.id == entry.id)
        #expect(dto.weightKg == 83.2)
        #expect(dto.recordedAt == entry.recordedAt)
        #expect(dto.source == "healthkit")
        #expect(dto.healthKitSampleUUID == sampleUUID)
        #expect(dto.lastModified == entry.lastModified)
    }

    @Test("createBodyWeightEntry builds a synced entry from DTO")
    func createBodyWeightEntryFromDTO() {
        let dto = BodyWeightEntryDTO(
            id: UUID(), weightKg: 78.9,
            recordedAt: Date(timeIntervalSinceReferenceDate: 600),
            source: "manual", healthKitSampleUUID: nil,
            lastModified: Date(timeIntervalSinceReferenceDate: 601)
        )
        let entry = SyncMapper.createBodyWeightEntry(from: dto)
        #expect(entry.id == dto.id)
        #expect(entry.weightKg == 78.9)
        #expect(entry.recordedAt == dto.recordedAt)
        #expect(entry.source == "manual")
        #expect(entry.healthKitSampleUUID == nil)
        #expect(entry.syncStatus == .synced)
        #expect(entry.lastModified == dto.lastModified)
    }

    // MARK: - TrainingPreference → DTO (still used by BackupService)

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

    // MARK: - Name-based fallback for MCP-created templates

    @Test("createTemplate uses exerciseName fallback when ID not found")
    @MainActor
    func createTemplateUsesNameFallbackWhenIdNotFound() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Insert an exercise with a known name but different ID than the DTO will reference
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)
        try context.save()

        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        // DTO references a random UUID that doesn't exist locally, but includes exerciseName
        let teDTO = TemplateExerciseDTO(
            id: UUID(), exerciseId: UUID(), exerciseName: "Bench Press", order: 0,
            defaultSets: 3, defaultReps: 10, defaultWeight: 60.0,
            defaultRestSeconds: 90, notes: nil
        )
        let templateDTO = TemplateDTO(
            id: UUID(), name: "MCP Template", notes: nil,
            createdAt: Date(), updatedAt: Date(), lastPerformedAt: nil,
            timesPerformed: 0, lastModified: Date(), exercises: [teDTO]
        )

        let template = try await SyncMapper.createTemplate(from: templateDTO, exerciseRepository: exerciseRepo)

        // Should have resolved via name fallback
        #expect(template.exercises.count == 1)
        #expect(template.exercises[0].exercise?.name == "Bench Press")
    }

    @Test("createWorkout uses exerciseName fallback when ID not found")
    @MainActor
    func createWorkoutUsesNameFallbackWhenIdNotFound() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Squat")
        context.insert(exercise)
        try context.save()

        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        let setDTO = WorkoutSetDTO(
            id: UUID(), order: 0, weight: 100.0, weightUnit: "kg",
            reps: 5, isCompleted: true, completedAt: Date(), notes: nil
        )
        let weDTO = WorkoutExerciseDTO(
            id: UUID(), exerciseId: UUID(), exerciseName: "Squat", order: 0,
            notes: nil, restSeconds: 120, sets: [setDTO]
        )
        let workoutDTO = WorkoutDTO(
            id: UUID(), templateId: nil, name: "MCP Workout",
            startedAt: Date(), completedAt: nil, notes: nil,
            lastModified: Date(), exercises: [weDTO]
        )

        let workout = try await SyncMapper.createWorkout(from: workoutDTO, exerciseRepository: exerciseRepo)

        #expect(workout.exercises.count == 1)
        #expect(workout.exercises[0].exercise?.name == "Squat")
    }
}
