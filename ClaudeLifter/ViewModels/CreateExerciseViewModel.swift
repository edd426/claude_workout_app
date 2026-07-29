import Foundation
import Observation

@Observable
@MainActor
final class CreateExerciseViewModel {
    var name: String = ""
    var equipment: String = ""
    var primaryMuscles: [String] = []
    var level: String = ""
    var mechanic: String = ""
    var force: String = ""
    var notes: String = ""
    var errorMessage: String?
    var isSaved = false

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func save(using repository: any ExerciseRepository) async throws {
        guard canSave else {
            throw CreateExerciseError.nameRequired
        }
        let exercise = Exercise(
            name: name.trimmingCharacters(in: .whitespaces),
            force: force.isEmpty ? nil : force,
            level: level.isEmpty ? nil : level,
            mechanic: mechanic.isEmpty ? nil : mechanic,
            equipment: equipment.isEmpty ? nil : equipment,
            primaryMuscles: primaryMuscles,
            isCustom: true,
            notes: notes.isEmpty ? nil : notes
        )
        for muscle in primaryMuscles {
            exercise.tags.append(ExerciseTag(category: "muscle_group", value: muscle))
        }
        if !equipment.isEmpty {
            exercise.tags.append(ExerciseTag(category: "equipment", value: equipment))
        }
        if !level.isEmpty {
            exercise.tags.append(ExerciseTag(category: "level", value: level))
        }
        if !mechanic.isEmpty {
            exercise.tags.append(ExerciseTag(category: "mechanic", value: mechanic))
        }
        if !force.isEmpty {
            exercise.tags.append(ExerciseTag(category: "force", value: force))
        }
        try await repository.save(exercise)
    }

    func submit(using repository: any ExerciseRepository) async {
        errorMessage = nil
        isSaved = false
        do {
            try await save(using: repository)
            isSaved = true
        } catch {
            errorMessage = "Could not create the exercise. Check your details and try again."
        }
    }
}

enum CreateExerciseError: Error {
    case nameRequired
}
