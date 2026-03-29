import Testing
import SwiftData
import Foundation
@testable import ClaudeLifter

@Suite("Exercise Model Tests")
struct ExerciseModelTests {
    @Test("Exercise can be created and inserted")
    @MainActor
    func createExercise() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Exercise>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Bench Press")
    }

    @Test("Exercise default values are correct")
    func exerciseDefaults() {
        let exercise = Exercise(name: "Squat")
        #expect(exercise.isCustom == false)
        #expect(exercise.instructions.isEmpty)
        #expect(exercise.primaryMuscles.isEmpty)
        #expect(exercise.secondaryMuscles.isEmpty)
        #expect(exercise.tags.isEmpty)
        #expect(exercise.force == nil)
        #expect(exercise.level == nil)
        #expect(exercise.mechanic == nil)
        #expect(exercise.equipment == nil)
        #expect(exercise.externalId == nil)
        #expect(exercise.notes == nil)
    }

    @Test("Exercise with all fields")
    func exerciseAllFields() {
        let exercise = Exercise(
            name: "Deadlift",
            force: "pull",
            level: "intermediate",
            mechanic: "compound",
            equipment: "barbell",
            instructions: ["Stand with feet hip-width", "Grip the bar"],
            primaryMuscles: ["hamstrings", "glutes"],
            secondaryMuscles: ["lower back"],
            isCustom: false,
            externalId: "deadlift_barbell"
        )
        #expect(exercise.name == "Deadlift")
        #expect(exercise.force == "pull")
        #expect(exercise.level == "intermediate")
        #expect(exercise.mechanic == "compound")
        #expect(exercise.equipment == "barbell")
        #expect(exercise.instructions.count == 2)
        #expect(exercise.primaryMuscles == ["hamstrings", "glutes"])
        #expect(exercise.secondaryMuscles == ["lower back"])
        #expect(exercise.externalId == "deadlift_barbell")
    }
}

@Suite("ExerciseTag Model Tests")
struct ExerciseTagModelTests {
    @Test("ExerciseTag can be created")
    func createTag() {
        let tag = ExerciseTag(category: "muscle_group", value: "chest")
        #expect(tag.category == "muscle_group")
        #expect(tag.value == "chest")
    }

    @Test("ExerciseTag can be inserted and fetched")
    @MainActor
    func insertTag() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let tag = ExerciseTag(category: "equipment", value: "barbell")
        context.insert(tag)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ExerciseTag>())
        #expect(fetched.count == 1)
        #expect(fetched[0].value == "barbell")
    }
}

@Suite("WorkoutSet Model Tests")
struct WorkoutSetModelTests {
    @Test("WorkoutSet default values")
    func defaults() {
        let set = WorkoutSet(order: 1)
        #expect(set.order == 1)
        #expect(set.weight == nil)
        #expect(set.weightUnit == .kg)
        #expect(set.reps == nil)
        #expect(set.isCompleted == false)
        #expect(set.completedAt == nil)
        #expect(set.notes == nil)
    }

    @Test("WorkoutSet with weight and reps")
    func withWeightAndReps() {
        let set = WorkoutSet(order: 1, weight: 60.0, weightUnit: .kg, reps: 8)
        #expect(set.weight == 60.0)
        #expect(set.reps == 8)
    }

    @Test("WorkoutSet can be inserted and fetched")
    @MainActor
    func insertSet() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let set = WorkoutSet(order: 1, weight: 80.0, weightUnit: .kg, reps: 5)
        context.insert(set)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<WorkoutSet>())
        #expect(fetched.count == 1)
        #expect(fetched[0].weight == 80.0)
        #expect(fetched[0].reps == 5)
    }
}

@Suite("WorkoutExercise Model Tests")
struct WorkoutExerciseModelTests {
    @Test("WorkoutExercise default values")
    @MainActor
    func defaults() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Pull-up")
        context.insert(exercise)
        let we = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(we)
        try context.save()

        #expect(we.order == 0)
        #expect(we.restSeconds == 90)
        #expect(we.notes == nil)
        #expect(we.sets.isEmpty)
    }
}

@Suite("TemplateExercise Model Tests")
struct TemplateExerciseModelTests {
    @Test("TemplateExercise default values")
    @MainActor
    func defaults() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Squat")
        context.insert(exercise)
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 4, defaultReps: 8)
        context.insert(te)
        try context.save()

        #expect(te.order == 0)
        #expect(te.defaultSets == 4)
        #expect(te.defaultReps == 8)
        #expect(te.defaultWeight == nil)
        #expect(te.defaultRestSeconds == 90)
        #expect(te.notes == nil)
    }
}

@Suite("Workout Model Tests")
struct WorkoutModelTests {
    @Test("Workout default values")
    func defaults() {
        let workout = Workout(name: "Push Day", startedAt: .now)
        #expect(workout.name == "Push Day")
        #expect(workout.completedAt == nil)
        #expect(workout.syncStatus == .pending)
        #expect(workout.exercises.isEmpty)
        #expect(workout.templateId == nil)
        #expect(workout.notes == nil)
    }

    @Test("Workout can be inserted and fetched")
    @MainActor
    func insertWorkout() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let workout = Workout(name: "Leg Day", startedAt: .now)
        context.insert(workout)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Workout>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Leg Day")
    }

    @Test("Workout with templateId")
    func withTemplateId() {
        let templateId = UUID()
        let workout = Workout(name: "Push", startedAt: .now, templateId: templateId)
        #expect(workout.templateId == templateId)
    }
}

@Suite("WorkoutTemplate Model Tests")
struct WorkoutTemplateModelTests {
    @Test("WorkoutTemplate default values")
    func defaults() {
        let template = WorkoutTemplate(name: "Monday Push")
        #expect(template.name == "Monday Push")
        #expect(template.notes == nil)
        #expect(template.lastPerformedAt == nil)
        #expect(template.timesPerformed == 0)
        #expect(template.exercises.isEmpty)
    }

    @Test("WorkoutTemplate can be inserted and fetched")
    @MainActor
    func insertTemplate() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(name: "Upper Body A")
        context.insert(template)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Upper Body A")
    }
}

@Suite("AIChatMessage Model Tests")
struct AIChatMessageModelTests {
    @Test("AIChatMessage can be created")
    func create() {
        let msg = AIChatMessage(role: .user, content: "How many sets?")
        #expect(msg.role == .user)
        #expect(msg.content == "How many sets?")
        #expect(msg.workoutId == nil)
        #expect(msg.syncStatus == .pending)
    }

    @Test("AIChatMessage can be inserted and fetched")
    @MainActor
    func insert() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let msg = AIChatMessage(role: .assistant, content: "Try 3 sets of 10.")
        context.insert(msg)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AIChatMessage>())
        #expect(fetched.count == 1)
        #expect(fetched[0].content == "Try 3 sets of 10.")
    }
}

@Suite("ProactiveInsight Model Tests")
struct ProactiveInsightModelTests {
    @Test("ProactiveInsight default values")
    func defaults() {
        let insight = ProactiveInsight(content: "You haven't trained legs in 2 weeks.", type: .warning)
        #expect(insight.content == "You haven't trained legs in 2 weeks.")
        #expect(insight.type == .warning)
        #expect(insight.isRead == false)
    }

    @Test("ProactiveInsight can be inserted and fetched")
    @MainActor
    func insert() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let insight = ProactiveInsight(content: "Great progress on bench!", type: .encouragement)
        context.insert(insight)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ProactiveInsight>())
        #expect(fetched.count == 1)
        #expect(fetched[0].type == .encouragement)
    }
}

@Suite("TrainingPreference Model Tests")
struct TrainingPreferenceModelTests {
    @Test("TrainingPreference can be created")
    func create() {
        let pref = TrainingPreference(key: "training_style", value: "hypertrophy")
        #expect(pref.key == "training_style")
        #expect(pref.value == "hypertrophy")
        #expect(pref.source == nil)
    }

    @Test("TrainingPreference can be inserted and fetched")
    @MainActor
    func insert() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let pref = TrainingPreference(key: "injury", value: "bad left shoulder", source: "user_stated")
        context.insert(pref)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TrainingPreference>())
        #expect(fetched.count == 1)
        #expect(fetched[0].key == "injury")
        #expect(fetched[0].source == "user_stated")
    }
}
