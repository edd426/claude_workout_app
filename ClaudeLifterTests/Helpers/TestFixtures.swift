import Foundation
import SwiftData
@testable import ClaudeLifter

enum TestFixtures {
    // MARK: - Exercises

    static func makeExercise(
        name: String = "Bench Press",
        force: String? = "push",
        level: String? = "intermediate",
        mechanic: String? = "compound",
        equipment: String? = "barbell",
        primaryMuscles: [String] = ["chest"],
        secondaryMuscles: [String] = ["triceps", "shoulders"],
        isCustom: Bool = false,
        externalId: String? = nil
    ) -> Exercise {
        Exercise(
            name: name,
            force: force,
            level: level,
            mechanic: mechanic,
            equipment: equipment,
            instructions: ["Lie on bench", "Lower bar to chest", "Press up"],
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            isCustom: isCustom,
            externalId: externalId ?? name.lowercased().replacingOccurrences(of: " ", with: "_")
        )
    }

    static func makeSquat() -> Exercise {
        makeExercise(
            name: "Barbell Squat",
            force: "push",
            level: "intermediate",
            mechanic: "compound",
            equipment: "barbell",
            primaryMuscles: ["quadriceps"],
            secondaryMuscles: ["glutes", "hamstrings"],
            externalId: "barbell_squat"
        )
    }

    static func makeDeadlift() -> Exercise {
        makeExercise(
            name: "Deadlift",
            force: "pull",
            level: "intermediate",
            mechanic: "compound",
            equipment: "barbell",
            primaryMuscles: ["hamstrings", "glutes"],
            secondaryMuscles: ["lower back"],
            externalId: "deadlift"
        )
    }

    // MARK: - WorkoutSets

    static func makeSet(
        order: Int = 1,
        weight: Double? = 60.0,
        weightUnit: WeightUnit = .kg,
        reps: Int? = 8,
        isCompleted: Bool = true,
        completedAt: Date? = Date()
    ) -> WorkoutSet {
        WorkoutSet(
            order: order,
            weight: weight,
            weightUnit: weightUnit,
            reps: reps,
            isCompleted: isCompleted,
            completedAt: completedAt
        )
    }

    // MARK: - Workouts

    static func makeWorkout(
        name: String = "Push Day",
        startedAt: Date = Date(timeIntervalSinceNow: -3600),
        completedAt: Date? = Date(timeIntervalSinceNow: -600),
        templateId: UUID? = nil
    ) -> Workout {
        Workout(
            name: name,
            startedAt: startedAt,
            templateId: templateId,
            completedAt: completedAt
        )
    }

    // MARK: - WorkoutExercise with sets

    @MainActor
    static func makeWorkoutExercise(
        exercise: Exercise,
        order: Int = 0,
        sets: [(weight: Double, reps: Int)] = [(60, 8), (65, 6)],
        in context: ModelContext
    ) -> WorkoutExercise {
        let we = WorkoutExercise(order: order, exercise: exercise)
        context.insert(we)
        for (i, s) in sets.enumerated() {
            let workoutSet = WorkoutSet(order: i, weight: s.weight, weightUnit: .kg, reps: s.reps, isCompleted: true, completedAt: Date())
            context.insert(workoutSet)
            we.sets.append(workoutSet)
        }
        return we
    }

    // MARK: - Templates

    static func makeTemplate(
        name: String = "Wednesday Push Day",
        timesPerformed: Int = 0
    ) -> WorkoutTemplate {
        WorkoutTemplate(name: name, timesPerformed: timesPerformed)
    }

    // MARK: - Training Preferences

    static func makeTrainingPreference(
        key: String = "training_style",
        value: String = "hypertrophy",
        source: String? = "user_stated"
    ) -> TrainingPreference {
        TrainingPreference(key: key, value: value, source: source)
    }

    // MARK: - Chat Messages

    static func makeChatMessage(
        role: MessageRole = .user,
        content: String = "How many sets should I do?",
        workoutId: UUID? = nil
    ) -> AIChatMessage {
        AIChatMessage(role: role, content: content, workoutId: workoutId)
    }

    // MARK: - Insights

    static func makeInsight(
        content: String = "You haven't trained legs in 2 weeks.",
        type: InsightType = .warning
    ) -> ProactiveInsight {
        ProactiveInsight(content: content, type: type)
    }
}
