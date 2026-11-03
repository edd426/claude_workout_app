import Foundation
import SwiftData

/// Synthetic data for screenshots of the Today screen (`-UITesting
/// -seedTodayDemo`). The in-memory UI-test store only. Every name and number
/// here is made up; none of it is anyone's real training or body data.
@MainActor
enum TodayDemoSeed {
    static func seed(context: ModelContext, settings: SettingsManager, now: Date = .now) {
        let calendar = Calendar.current
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let weekStart = mondayCalendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)

        let library = exercises()
        library.values.forEach { context.insert($0) }
        let templates = makeTemplates(library: library)
        templates.forEach { context.insert($0) }

        // Last week: every weekday template done once, so each has a date.
        for (index, template) in templates.enumerated() where index < 4 {
            let day = calendar.date(byAdding: .day, value: index - 7, to: weekStart) ?? now
            insertWorkout(from: template, on: day, setsPerExercise: 3, context: context)
        }
        // This week so far: Monday's session, if Monday has passed.
        let monday = calendar.date(byAdding: .hour, value: 7, to: weekStart) ?? weekStart
        if monday < now, let legs = templates.first {
            insertWorkout(from: legs, on: monday, setsPerExercise: 3, context: context)
        }

        insertBodyWeight(context: context, now: now, calendar: calendar)
        settings.weightGoalPercentPerWeek = -0.25

        context.insert(ExerciseReport(category: .bug, detail: "Rest timer chimed twice after the last set."))
        context.insert(ExerciseReport(
            category: .swapRequest,
            detail: "The leg press is often taken; suggest a hack squat instead.",
            exerciseName: "Leg Press"
        ))
        let answered = ExerciseReport(category: .dataError, detail: "Calf raise shows the wrong muscle.")
        answered.status = .acknowledged
        answered.resolution = "Fixed in the next build: muscle corrected to calves."
        context.insert(answered)

        context.insert(ProactiveInsight(
            content: "Hamstrings have had two sets this week. Wednesday's hinge day would bring them into range.",
            type: .suggestion
        ))
        context.insert(ProactiveInsight(
            content: "Three sessions in a row on schedule. Keep it going.",
            type: .encouragement
        ))
        try? context.save()
    }

    private static func exercises() -> [String: Exercise] {
        let specs: [(String, [String], [String])] = [
            ("Barbell Squat", ["quadriceps"], ["glutes", "hamstrings"]),
            ("Leg Press", ["quadriceps"], ["glutes"]),
            ("Seated Leg Curl", ["hamstrings"], []),
            ("Standing Calf Raise", ["calves"], []),
            ("Bench Press", ["chest"], ["triceps", "shoulders"]),
            ("Seated Cable Row", ["middle back"], ["lats", "biceps"]),
            ("Overhead Press", ["shoulders"], ["triceps"]),
            ("Dumbbell Curl", ["biceps"], []),
            ("Romanian Deadlift", ["hamstrings"], ["glutes", "lower back"]),
            ("Hip Thrust", ["glutes"], ["hamstrings"]),
            ("Lat Pulldown", ["lats"], ["biceps"]),
            ("Incline Dumbbell Press", ["chest"], ["shoulders", "triceps"]),
            ("Cable Crunch", ["abdominals"], []),
            ("Adductor Machine", ["adductors"], []),
        ]
        var library: [String: Exercise] = [:]
        for (name, primary, secondary) in specs {
            library[name] = Exercise(name: name, primaryMuscles: primary, secondaryMuscles: secondary)
        }
        return library
    }

    private static func makeTemplates(library: [String: Exercise]) -> [WorkoutTemplate] {
        let plans: [(String, [String])] = [
            ("Mon · Legs 1 (squat)", ["Barbell Squat", "Seated Leg Curl", "Standing Calf Raise", "Cable Crunch"]),
            ("Tue · Upper 1 (bench)", ["Bench Press", "Seated Cable Row", "Overhead Press", "Dumbbell Curl"]),
            ("Wed · Legs 2 (hinge)", ["Romanian Deadlift", "Hip Thrust", "Leg Press", "Adductor Machine"]),
            ("Thu · Upper 2 (incline)", ["Incline Dumbbell Press", "Lat Pulldown", "Overhead Press"]),
            ("Fri · Machines (optional)", ["Leg Press", "Lat Pulldown", "Seated Leg Curl"]),
        ]
        return plans.map { name, exerciseNames in
            let template = WorkoutTemplate(name: name)
            for (order, exerciseName) in exerciseNames.enumerated() {
                guard let exercise = library[exerciseName] else { continue }
                template.exercises.append(
                    TemplateExercise(order: order, exercise: exercise, defaultSets: 3, defaultReps: 10)
                )
            }
            return template
        }
    }

    private static func insertWorkout(
        from template: WorkoutTemplate,
        on start: Date,
        setsPerExercise: Int,
        context: ModelContext
    ) {
        let workout = Workout(
            name: template.name,
            startedAt: start,
            templateId: template.id,
            completedAt: start.addingTimeInterval(3_000)
        )
        context.insert(workout)
        for templateExercise in template.exercises.sorted(by: { $0.order < $1.order }) {
            guard let exercise = templateExercise.exercise else { continue }
            let entry = WorkoutExercise(order: templateExercise.order, exercise: exercise)
            context.insert(entry)
            for index in 0..<setsPerExercise {
                let set = WorkoutSet(
                    order: index, weight: 40, weightUnit: .kg, reps: 10,
                    isCompleted: true,
                    completedAt: start.addingTimeInterval(Double(index + templateExercise.order * 4) * 150)
                )
                context.insert(set)
                entry.sets.append(set)
            }
            workout.exercises.append(entry)
        }
    }

    /// A gentle synthetic downward trend over four weeks, last reading two
    /// days ago.
    private static func insertBodyWeight(context: ModelContext, now: Date, calendar: Calendar) {
        for daysAgo in stride(from: 30, through: 2, by: -2) {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            let kilograms = 80 - Double(30 - daysAgo) * 0.03
            context.insert(BodyWeightEntry(weightKg: kilograms, recordedAt: date))
        }
    }
}
