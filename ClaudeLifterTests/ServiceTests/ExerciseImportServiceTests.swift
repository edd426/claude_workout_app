import Testing
import SwiftData
import Foundation
@testable import ClaudeLifter

@Suite("ExerciseImportService Tests")
struct ExerciseImportServiceTests {
    let sampleJSON = """
    [
        {
            "name": "Bench Press",
            "force": "push",
            "level": "intermediate",
            "mechanic": "compound",
            "equipment": "barbell",
            "primaryMuscles": ["chest"],
            "secondaryMuscles": ["triceps", "shoulders"],
            "instructions": ["Lie on bench", "Lower to chest", "Press up"],
            "category": "strength",
            "images": ["Bench_Press/0.jpg", "Bench_Press/1.jpg"],
            "id": "Bench_Press"
        },
        {
            "name": "Squat",
            "force": "push",
            "level": "beginner",
            "mechanic": "compound",
            "equipment": "barbell",
            "primaryMuscles": ["quadriceps"],
            "secondaryMuscles": ["glutes", "hamstrings"],
            "instructions": ["Stand with bar on back", "Squat down", "Drive up"],
            "category": "strength",
            "images": [],
            "id": "Barbell_Squat"
        }
    ]
    """

    let nullFieldsJSON = """
    [
        {
            "name": "Plank",
            "force": null,
            "level": "beginner",
            "mechanic": null,
            "equipment": "body only",
            "primaryMuscles": ["abdominals"],
            "secondaryMuscles": [],
            "instructions": ["Hold plank position"],
            "category": "strength",
            "images": [],
            "id": "Plank"
        }
    ]
    """

    @Test("imports exercises from JSON data")
    @MainActor
    func importBasic() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ExerciseImportService()
        let data = sampleJSON.data(using: .utf8)!

        let count = try await service.importExercises(from: data, into: context)
        #expect(count == 2)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(exercises.count == 2)
    }

    @Test("imported exercises have correct fields")
    @MainActor
    func importedFields() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ExerciseImportService()
        let data = sampleJSON.data(using: .utf8)!

        try await service.importExercises(from: data, into: context)

        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "Bench Press" })
        let bench = try context.fetch(descriptor).first
        #expect(bench != nil)
        #expect(bench?.force == "push")
        #expect(bench?.level == "intermediate")
        #expect(bench?.mechanic == "compound")
        #expect(bench?.equipment == "barbell")
        #expect(bench?.primaryMuscles == ["chest"])
        #expect(bench?.secondaryMuscles == ["triceps", "shoulders"])
        #expect(bench?.instructions.count == 3)
        #expect(bench?.isCustom == false)
        #expect(bench?.externalId == "Bench_Press")
    }

    @Test("imported exercises get muscle group tags")
    @MainActor
    func muscleGroupTags() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ExerciseImportService()
        let data = sampleJSON.data(using: .utf8)!

        try await service.importExercises(from: data, into: context)

        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "Bench Press" })
        let bench = try context.fetch(descriptor).first!
        let muscleTags = bench.tags.filter { $0.category == "muscle_group" }
        #expect(muscleTags.contains { $0.value == "chest" })
    }

    @Test("imported exercises get equipment tags")
    @MainActor
    func equipmentTags() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ExerciseImportService()
        let data = sampleJSON.data(using: .utf8)!

        try await service.importExercises(from: data, into: context)

        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "Bench Press" })
        let bench = try context.fetch(descriptor).first!
        let equipmentTags = bench.tags.filter { $0.category == "equipment" }
        #expect(equipmentTags.contains { $0.value == "barbell" })
    }

    @Test("import is idempotent — skips existing exercises")
    @MainActor
    func idempotent() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ExerciseImportService()
        let data = sampleJSON.data(using: .utf8)!

        let first = try await service.importExercises(from: data, into: context)
        let second = try await service.importExercises(from: data, into: context)

        #expect(first == 2)
        #expect(second == 0)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(exercises.count == 2)
    }

    @Test("handles null force and mechanic fields")
    @MainActor
    func nullFields() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ExerciseImportService()
        let data = nullFieldsJSON.data(using: .utf8)!

        let count = try await service.importExercises(from: data, into: context)
        #expect(count == 1)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let plank = exercises.first
        #expect(plank?.force == nil)
        #expect(plank?.mechanic == nil)
    }

    @Test("returns count of newly imported exercises")
    @MainActor
    func importCount() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ExerciseImportService()

        // Pre-insert one
        let existing = Exercise(name: "Bench Press", externalId: "Bench_Press")
        context.insert(existing)
        try context.save()

        let data = sampleJSON.data(using: .utf8)!
        let count = try await service.importExercises(from: data, into: context)
        #expect(count == 1)
    }

    @Test("imports exercises.json bundle resource")
    @MainActor
    func importsBundleResource() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ExerciseImportService()

        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            // If running in test bundle, skip this check
            return
        }

        let count = try await service.importExercises(from: data, into: context)
        #expect(count > 800)
    }
}
