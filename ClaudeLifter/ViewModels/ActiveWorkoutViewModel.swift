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
    private let templateRepository: (any TemplateRepository)?

    var totalSetsCompleted: Int {
        workout?.exercises.flatMap(\.sets).filter(\.isCompleted).count ?? 0
    }

    var hasCompletedSets: Bool {
        workout?.exercises.flatMap(\.sets).contains(where: \.isCompleted) ?? false
    }

    var totalSets: Int {
        workout?.exercises.flatMap(\.sets).count ?? 0
    }

    init(
        template: WorkoutTemplate,
        workoutRepository: any WorkoutRepository,
        autoFillService: any AutoFillServiceProtocol,
        templateRepository: (any TemplateRepository)? = nil,
        prDetectionService: (any PRDetectionServiceProtocol)? = nil
    ) {
        self.template = template
        self.adHocName = nil
        self.workoutRepository = workoutRepository
        self.autoFillService = autoFillService
        self.templateRepository = templateRepository
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
        self.templateRepository = nil
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
        Task { await saveDraft() }
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

    func removeSet(_ set: WorkoutSet, from workoutExercise: WorkoutExercise) {
        workoutExercise.sets.removeAll { $0.id == set.id }
    }

    func saveDraft() async {
        guard let workout else { return }
        workout.lastModified = .now
        try? await saveWorkout(workout)
    }

    func cancelWorkout() async {
        guard let workout else { return }
        do {
            try await workoutRepository.delete(workout)
            self.workout = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishWorkout() async {
        guard let workout else { return }
        workout.completedAt = .now
        workout.lastModified = .now
        do {
            try await saveWorkout(workout)
            if let template, let templateRepository {
                template.timesPerformed += 1
                template.lastPerformedAt = .now
                template.lastModified = .now
                try? await templateRepository.save(template)
            }
            if let prService = prDetectionService {
                detectedPRs = (try? await prService.detectPRs(for: workout)) ?? []
            }
            isFinished = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveWorkout(_ w: Workout) async throws {
        try await workoutRepository.save(w)
    }
}
