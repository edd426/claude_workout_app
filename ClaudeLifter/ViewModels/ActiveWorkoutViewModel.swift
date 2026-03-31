import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ActiveWorkoutViewModel {
    var workout: Workout? = nil
    var isFinished = false
    var errorMessage: String? = nil
    var lastCompletedSet: WorkoutSet? = nil
    var detectedPRs: [PersonalRecord] = []

    private let template: WorkoutTemplate?
    private let adHocName: String?
    private let workoutRepository: any WorkoutRepository
    private let autoFillService: any AutoFillServiceProtocol
    private let prDetectionService: (any PRDetectionServiceProtocol)?

    var totalSetsCompleted: Int {
        workout?.exercises.flatMap(\.sets).filter(\.isCompleted).count ?? 0
    }

    var totalSets: Int {
        workout?.exercises.flatMap(\.sets).count ?? 0
    }

    init(
        template: WorkoutTemplate,
        workoutRepository: any WorkoutRepository,
        autoFillService: any AutoFillServiceProtocol,
        prDetectionService: (any PRDetectionServiceProtocol)? = nil
    ) {
        self.template = template
        self.adHocName = nil
        self.workoutRepository = workoutRepository
        self.autoFillService = autoFillService
        self.prDetectionService = prDetectionService
    }

    init(
        adHocName: String,
        workoutRepository: any WorkoutRepository,
        autoFillService: any AutoFillServiceProtocol,
        prDetectionService: (any PRDetectionServiceProtocol)? = nil
    ) {
        self.template = nil
        self.adHocName = adHocName
        self.workoutRepository = workoutRepository
        self.autoFillService = autoFillService
        self.prDetectionService = prDetectionService
    }

    func startWorkout() async {
        if let template {
            await startFromTemplate(template)
        } else if let adHocName {
            await startAdHoc(name: adHocName)
        }
    }

    private func startAdHoc(name: String) async {
        let newWorkout = Workout(name: name, startedAt: .now, templateId: nil)
        do {
            try await saveWorkout(newWorkout)
            workout = newWorkout
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startFromTemplate(_ template: WorkoutTemplate) async {
        let newWorkout = Workout(
            name: template.name,
            startedAt: .now,
            templateId: template.id
        )
        for templateExercise in template.exercises.sorted(by: { $0.order < $1.order }) {
            guard let exercise = templateExercise.exercise else { continue }
            let we = WorkoutExercise(
                order: templateExercise.order,
                exercise: exercise,
                restSeconds: templateExercise.defaultRestSeconds
            )
            let autoFill = try? await autoFillService.lastPerformed(exerciseId: exercise.id)
            for i in 0..<templateExercise.defaultSets {
                let set = WorkoutSet(
                    order: i,
                    weight: autoFill?.weight ?? templateExercise.defaultWeight,
                    weightUnit: autoFill?.weightUnit ?? .kg,
                    reps: autoFill?.reps ?? templateExercise.defaultReps
                )
                we.sets.append(set)
            }
            newWorkout.exercises.append(we)
        }
        do {
            try await saveWorkout(newWorkout)
            workout = newWorkout
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeSet(_ set: WorkoutSet) {
        set.isCompleted = true
        set.completedAt = .now
        lastCompletedSet = set
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func addExercise(_ exercise: Exercise) {
        guard let workout else { return }
        let order = workout.exercises.count
        let we = WorkoutExercise(order: order, exercise: exercise)
        workout.exercises.append(we)
        for i in 0..<3 {
            we.sets.append(WorkoutSet(order: i))
        }
    }

    func removeExercise(_ workoutExercise: WorkoutExercise) {
        workout?.exercises.removeAll { $0.id == workoutExercise.id }
    }

    func finishWorkout() async {
        guard let workout else { return }
        workout.completedAt = .now
        workout.lastModified = .now
        do {
            try await saveWorkout(workout)
            if let prService = prDetectionService {
                detectedPRs = (try? await prService.detectPRs(for: workout)) ?? []
            }
            isFinished = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // Bridge @MainActor-isolated model to Sendable async repository
    private func saveWorkout(_ w: Workout) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                do {
                    try await self.workoutRepository.save(w)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
