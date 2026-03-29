import Foundation
import SwiftData

protocol ExerciseImportServiceProtocol: Sendable {
    @discardableResult
    func importExercises(from data: Data, into context: ModelContext) async throws -> Int
}

final class ExerciseImportService: ExerciseImportServiceProtocol, @unchecked Sendable {
    private struct ExerciseJSON: Decodable {
        let id: String
        let name: String
        let force: String?
        let level: String?
        let mechanic: String?
        let equipment: String?
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
        let instructions: [String]
        let category: String?
        let images: [String]
    }

    @discardableResult
    func importExercises(from data: Data, into context: ModelContext) async throws -> Int {
        let decoded = try JSONDecoder().decode([ExerciseJSON].self, from: data)
        var imported = 0

        for json in decoded {
            // Check for existing by externalId (idempotency)
            let externalId = json.id
            let descriptor = FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.externalId == externalId }
            )
            if (try context.fetch(descriptor).first) != nil {
                continue
            }

            let exercise = Exercise(
                name: json.name,
                force: json.force,
                level: json.level,
                mechanic: json.mechanic,
                equipment: json.equipment,
                instructions: json.instructions,
                primaryMuscles: json.primaryMuscles,
                secondaryMuscles: json.secondaryMuscles,
                isCustom: false,
                externalId: json.id
            )
            context.insert(exercise)

            // Create tags from mapped fields
            var tags: [ExerciseTag] = []

            for muscle in json.primaryMuscles {
                let tag = ExerciseTag(category: "muscle_group", value: muscle)
                context.insert(tag)
                tags.append(tag)
            }

            if let equipment = json.equipment {
                let tag = ExerciseTag(category: "equipment", value: equipment)
                context.insert(tag)
                tags.append(tag)
            }

            if let force = json.force {
                let tag = ExerciseTag(category: "force", value: force)
                context.insert(tag)
                tags.append(tag)
            }

            if let mechanic = json.mechanic {
                let tag = ExerciseTag(category: "mechanic", value: mechanic)
                context.insert(tag)
                tags.append(tag)
            }

            if let level = json.level {
                let tag = ExerciseTag(category: "level", value: level)
                context.insert(tag)
                tags.append(tag)
            }

            if let category = json.category {
                let tag = ExerciseTag(category: "category", value: category)
                context.insert(tag)
                tags.append(tag)
            }

            exercise.tags = tags
            imported += 1
        }

        if imported > 0 {
            try context.save()
        }

        return imported
    }
}
