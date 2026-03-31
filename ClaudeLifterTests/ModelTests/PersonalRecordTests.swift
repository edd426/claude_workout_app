import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("PersonalRecord Model Tests")
@MainActor
struct PersonalRecordTests {

    @Test("PersonalRecord initializes with defaults")
    func initWithDefaults() throws {
        let exerciseId = UUID()
        let workoutId = UUID()
        let record = PersonalRecord(
            exerciseId: exerciseId,
            type: .heaviestWeight,
            value: 100.0,
            workoutId: workoutId
        )

        #expect(record.exerciseId == exerciseId)
        #expect(record.prType == .heaviestWeight)
        #expect(record.value == 100.0)
        #expect(record.workoutId == workoutId)
        #expect(record.syncStatus == .pending)
        #expect(record.weight == nil)
        #expect(record.reps == nil)
    }

    @Test("PRType enum has all expected cases")
    func prTypeEnumCases() {
        let cases: [PRType] = [.heaviestWeight, .mostRepsAtWeight, .highest1RM]
        #expect(cases.count == 3)
        #expect(PRType(rawValue: "heaviestWeight") == .heaviestWeight)
        #expect(PRType(rawValue: "mostRepsAtWeight") == .mostRepsAtWeight)
        #expect(PRType(rawValue: "highest1RM") == .highest1RM)
        #expect(PRType(rawValue: "invalid") == nil)
    }

    @Test("Brzycki formula computes correct 1RM")
    func brzykiFormula() throws {
        // 100kg x 5 reps = 100 * (36 / (37-5)) = 100 * (36/32) = 112.5
        let result = PersonalRecord.estimated1RM(weight: 100.0, reps: 5)
        let unwrapped = try #require(result)
        #expect(abs(unwrapped - 112.5) < 0.01)
    }

    @Test("Brzycki formula returns nil for reps greater than 36")
    func brzykiFormulaEdgeCase() {
        let result = PersonalRecord.estimated1RM(weight: 100.0, reps: 37)
        #expect(result == nil)
    }

    @Test("PersonalRecord persists in test container")
    func persistsInContainer() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exerciseId = UUID()
        let workoutId = UUID()

        let record = PersonalRecord(
            exerciseId: exerciseId,
            type: .highest1RM,
            value: 112.5,
            weight: 100.0,
            reps: 5,
            workoutId: workoutId
        )
        context.insert(record)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersonalRecord>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.prType == .highest1RM)
        #expect(fetched.first?.value == 112.5)
    }

    @Test("Fetch by exerciseId returns correct records")
    func fetchByExerciseId() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exerciseId1 = UUID()
        let exerciseId2 = UUID()
        let workoutId = UUID()

        let record1 = PersonalRecord(exerciseId: exerciseId1, type: .heaviestWeight, value: 100.0, workoutId: workoutId)
        let record2 = PersonalRecord(exerciseId: exerciseId1, type: .highest1RM, value: 112.5, workoutId: workoutId)
        let record3 = PersonalRecord(exerciseId: exerciseId2, type: .heaviestWeight, value: 80.0, workoutId: workoutId)
        context.insert(record1)
        context.insert(record2)
        context.insert(record3)
        try context.save()

        let repo = SwiftDataPersonalRecordRepository(context: context)
        let results = try await repo.fetch(exerciseId: exerciseId1)
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.exerciseId == exerciseId1 })
    }
}
