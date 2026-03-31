import Foundation
import Observation

@Observable
@MainActor
final class TemplateEditorViewModel {
    var name: String = ""
    var notes: String = ""
    var exercises: [TemplateExercise] = []
    var validationError: String? = nil
    var isSaved = false
    var isNew: Bool

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private let templateRepository: any TemplateRepository
    private let existingTemplate: WorkoutTemplate?

    init(template: WorkoutTemplate?, templateRepository: any TemplateRepository) {
        self.templateRepository = templateRepository
        self.existingTemplate = template
        self.isNew = template == nil
        if let t = template {
            self.name = t.name
            self.notes = t.notes ?? ""
            self.exercises = t.exercises.sorted { $0.order < $1.order }
        }
    }

    func addExercise(_ exercise: Exercise) {
        let order = exercises.count
        let te = TemplateExercise(order: order, exercise: exercise, defaultSets: 3, defaultReps: 8)
        exercises.append(te)
    }

    func removeExercise(at offsets: IndexSet) {
        exercises.remove(atOffsets: offsets)
        reorderExercises()
    }

    func moveExercise(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)
        reorderExercises()
    }

    func save() async {
        validationError = nil
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationError = "Name cannot be empty."
            return
        }
        let template = existingTemplate ?? WorkoutTemplate(name: name)
        template.name = name
        template.notes = notes.isEmpty ? nil : notes
        template.updatedAt = .now
        for (i, ex) in exercises.enumerated() {
            ex.order = i
        }
        if isNew {
            for ex in exercises {
                template.exercises.append(ex)
            }
        }
        // Capture a reference to pass to async boundary (both sides are @MainActor)
        let templateToSave = template
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                Task { @MainActor in
                    do {
                        try await self.templateRepository.save(templateToSave)
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            isSaved = true
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func reorderExercises() {
        for (i, ex) in exercises.enumerated() {
            ex.order = i
        }
    }
}
