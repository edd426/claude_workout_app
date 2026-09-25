import Foundation
import UIKit

/// Everything the app already knows about what is being reported (issue #135).
///
/// Assembled at the tap site, never chosen by the user — the whole design
/// rests on context being captured rather than filled in. `Identifiable` so a
/// non-nil context doubles as the `sheet(item:)` trigger.
struct ReportContext: Identifiable, Equatable, Sendable {
    let id = UUID()
    var exerciseExternalId: String?
    var exerciseName: String?
    var workoutId: UUID?
    var workoutExerciseId: UUID?
    var templateId: UUID?
    var contextSummary: String?

    /// The subtitle shown at the top of the sheet, so it is obvious what the
    /// report will be attached to before anything is typed.
    var subject: String {
        if let exerciseName { return exerciseName }
        if workoutId != nil { return "This workout" }
        return "The app"
    }
}

extension ReportContext {
    /// Report filed from an exercise card mid-workout — the main entry point.
    @MainActor
    static func forExercise(
        _ workoutExercise: WorkoutExercise,
        in workout: Workout?
    ) -> ReportContext {
        ReportContext(
            exerciseExternalId: workoutExercise.exercise?.externalId,
            exerciseName: workoutExercise.exercise?.name,
            workoutId: workout?.id,
            workoutExerciseId: workoutExercise.id,
            templateId: workout?.templateId,
            contextSummary: summarize(workoutExercise, in: workout)
        )
    }

    /// Report filed from the workout toolbar — not about any one exercise.
    @MainActor
    static func forWorkout(_ workout: Workout?) -> ReportContext {
        ReportContext(
            workoutId: workout?.id,
            templateId: workout?.templateId,
            contextSummary: workout.map { summarizeWorkout($0) }
        )
    }

    /// Report filed from the exercise library, away from the gym.
    @MainActor
    static func forLibraryExercise(_ exercise: Exercise) -> ReportContext {
        ReportContext(
            exerciseExternalId: exercise.externalId,
            exerciseName: exercise.name
        )
    }

    /// Report filed from the Home screen — not about any exercise or
    /// workout. The only entry point that previously required opening an
    /// unrelated exercise just to reach the sheet (report A590AD71).
    static func general() -> ReportContext {
        ReportContext()
    }

    /// A bounded, human-readable line describing the sets as they stood when
    /// the report was filed. This is what turns "the timer did something
    /// weird" into something reproducible three days later, without asking
    /// anyone to type a repro mid-set.
    @MainActor
    private static func summarize(
        _ workoutExercise: WorkoutExercise,
        in workout: Workout?
    ) -> String {
        let sets = workoutExercise.sets
            .sorted { $0.order < $1.order }
            .map { set -> String in
                let weight = set.weight.map { formatted($0) + set.weightUnit.rawValue }
                    ?? "bodyweight"
                let reps = set.reps.map(String.init) ?? "–"
                return "\(weight)×\(reps)\(set.isCompleted ? " ✓" : "")"
            }
        var parts: [String] = []
        if let name = workout?.name { parts.append(name) }
        parts.append(workoutExercise.exercise?.name ?? "Unknown exercise")
        parts.append(sets.isEmpty ? "no sets" : sets.joined(separator: ", "))
        return parts.joined(separator: " · ")
    }

    @MainActor
    private static func summarizeWorkout(_ workout: Workout) -> String {
        let completed = workout.exercises
            .flatMap(\.sets)
            .filter(\.isCompleted)
            .count
        let exercises = workout.exercises
            .sorted { $0.order < $1.order }
            .compactMap { $0.exercise?.name }
            .joined(separator: ", ")
        return "\(workout.name) · \(completed) sets completed · \(exercises)"
    }

    private static func formatted(_ weight: Double) -> String {
        weight == weight.rounded()
            ? String(Int(weight))
            : String(format: "%.1f", weight)
    }
}

/// Drives the report sheet. Deliberately thin: pick a category, type a
/// sentence, save. Everything else is filled in from `context` and the build.
@MainActor
@Observable
final class ReportSheetViewModel {
    let context: ReportContext
    var category: ReportCategory = .bug
    var detail: String = ""
    var suggestedReplacement: String = ""
    private(set) var isSaving = false
    var errorMessage: String?

    /// The attached photo, already re-encoded as a ≤1024px JPEG (#141). Kept
    /// on the phone when the report is filed; uploaded on a later sync.
    private(set) var photoData: Data?
    /// `photoData` decoded once for the sheet's thumbnail, rather than on
    /// every render — the body re-evaluates on each keystroke in the detail.
    private(set) var photoPreview: UIImage?
    /// Why the chosen photo could not be attached. Never blocks filing.
    var photoError: String?
    /// The report was filed but its photo could not be kept. Set by `submit`
    /// so the sheet can say so before closing, instead of implying the photo
    /// went with it.
    private(set) var photoWasLost = false

    private let repository: any ExerciseReportRepository
    private let photoStore: any ReportPhotoStoring

    init(
        context: ReportContext,
        repository: any ExerciseReportRepository,
        photoStore: any ReportPhotoStoring = LocalReportPhotoStore()
    ) {
        self.context = context
        self.repository = repository
        self.photoStore = photoStore
        // A report filed against a specific exercise is far more often about
        // that exercise than about the app; one without an exercise almost
        // always is a bug. Start on the likelier chip.
        self.category = context.exerciseName == nil ? .bug : .swapRequest
    }

    /// Only the two categories that name a substitute show the field — asking
    /// for a replacement on a bug report is noise.
    var showsReplacementField: Bool {
        category == .swapRequest || category == .wrongExercise
    }

    var canSubmit: Bool {
        !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    /// Takes a photo from the camera or the library. Returns false, with a
    /// message, when the data is not an image.
    @discardableResult
    func attachPhoto(_ data: Data) -> Bool {
        guard let jpeg = JPEGEncoding.jpeg(from: data) else {
            photoError = "Couldn't use that photo. Try another one."
            return false
        }
        photoData = jpeg
        photoPreview = UIImage(data: jpeg)
        photoError = nil
        return true
    }

    func removePhoto() {
        photoData = nil
        photoPreview = nil
        photoError = nil
    }

    /// Returns true when the report was saved and the sheet should close.
    func submit() async -> Bool {
        guard canSubmit else { return false }
        isSaving = true
        defer { isSaving = false }

        let replacement = suggestedReplacement
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let report = ExerciseReport(
            category: category,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            exerciseExternalId: context.exerciseExternalId,
            exerciseName: context.exerciseName,
            suggestedReplacement:
                showsReplacementField && !replacement.isEmpty ? replacement : nil,
            workoutId: context.workoutId,
            workoutExerciseId: context.workoutExerciseId,
            templateId: context.templateId,
            contextSummary: context.contextSummary,
            appVersion: "\(BuildInfo.appVersion) (\(BuildInfo.buildNumber))",
            iosVersion: UIDevice.current.systemVersion
        )

        // The photo is written first, under the report's id, so it is on disk
        // before the report exists to be synced. If it cannot be written the
        // report is filed without it: the report is the point (#141).
        var storedPhoto = false
        if let photoData {
            do {
                try photoStore.save(photoData, reportId: report.id)
                storedPhoto = true
            } catch {
                photoError = "The photo couldn't be kept: \(error.localizedDescription)"
                photoWasLost = true
            }
        }

        do {
            try await repository.save(report)
            return true
        } catch {
            if storedPhoto {
                // Retrying files a new report with a new id; don't leave this
                // photo orphaned under the old one.
                photoStore.delete(reportId: report.id)
            }
            errorMessage = "Couldn't save the report: \(error.localizedDescription)"
            return false
        }
    }
}
