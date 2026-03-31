import Foundation
import Observation

@Observable
@MainActor
final class ProgressChartsViewModel {

    struct VolumeDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let volume: Double  // total weight * reps for that day
    }

    struct OneRMDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let estimated1RM: Double
    }

    struct MuscleDistribution: Identifiable {
        let id = UUID()
        let muscle: String
        let percentage: Double
    }

    var volumeData: [VolumeDataPoint] = []
    var oneRMData: [OneRMDataPoint] = []
    var muscleDistribution: [MuscleDistribution] = []
    var selectedExerciseId: UUID?
    var exercises: [Exercise] = []

    private let workoutRepository: any WorkoutRepository
    private let exerciseRepository: any ExerciseRepository

    init(workoutRepository: any WorkoutRepository, exerciseRepository: any ExerciseRepository) {
        self.workoutRepository = workoutRepository
        self.exerciseRepository = exerciseRepository
    }

    func loadVolumeOverTime(days: Int = 30) async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let workouts = (try? await workoutRepository.fetchAll()) ?? []
        let recent = workouts.filter { ($0.completedAt ?? $0.startedAt) >= cutoff }

        // Group volume by calendar day
        var volumeByDay: [Date: Double] = [:]
        let calendar = Calendar.current
        for workout in recent {
            let day = calendar.startOfDay(for: workout.completedAt ?? workout.startedAt)
            let dayVolume = workout.exercises
                .flatMap(\.sets)
                .filter(\.isCompleted)
                .compactMap { set -> Double? in
                    guard let w = set.weight, let r = set.reps else { return nil }
                    return w * Double(r)
                }
                .reduce(0, +)
            volumeByDay[day, default: 0] += dayVolume
        }

        volumeData = volumeByDay
            .map { VolumeDataPoint(date: $0.key, volume: $0.value) }
            .sorted { $0.date < $1.date }
    }

    func load1RMProgression(exerciseId: UUID) async {
        let workouts = (try? await workoutRepository.fetchAll()) ?? []
        var points: [OneRMDataPoint] = []
        for workout in workouts {
            guard let completedAt = workout.completedAt else { continue }
            for we in workout.exercises {
                guard we.exercise?.id == exerciseId else { continue }
                let best1RM = we.sets
                    .filter(\.isCompleted)
                    .compactMap { set -> Double? in
                        guard let w = set.weight, let r = set.reps else { return nil }
                        return PersonalRecord.estimated1RM(weight: w, reps: r)
                    }
                    .max()
                if let best1RM {
                    points.append(OneRMDataPoint(date: completedAt, estimated1RM: best1RM))
                }
            }
        }
        oneRMData = points.sorted { $0.date < $1.date }
    }

    func loadMuscleDistribution(days: Int = 30) async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let workouts = (try? await workoutRepository.fetchAll()) ?? []
        let recent = workouts.filter { ($0.completedAt ?? $0.startedAt) >= cutoff }

        var setsByMuscle: [String: Int] = [:]
        for workout in recent {
            for we in workout.exercises {
                let completedSets = we.sets.filter(\.isCompleted).count
                guard completedSets > 0, let exercise = we.exercise else { continue }
                for muscle in exercise.primaryMuscles {
                    setsByMuscle[muscle, default: 0] += completedSets
                }
            }
        }

        let total = setsByMuscle.values.reduce(0, +)
        guard total > 0 else {
            muscleDistribution = []
            return
        }

        muscleDistribution = setsByMuscle
            .map { MuscleDistribution(muscle: $0.key, percentage: Double($0.value) / Double(total) * 100) }
            .sorted { $0.muscle < $1.muscle }
    }

    func loadExercises() async {
        exercises = (try? await exerciseRepository.fetchAll()) ?? []
    }
}
