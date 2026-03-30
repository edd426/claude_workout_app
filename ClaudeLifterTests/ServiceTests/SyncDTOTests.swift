import Testing
import Foundation
@testable import ClaudeLifter

@Suite("SyncDTO Encode/Decode Tests")
struct SyncDTOTests {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    @Test("WorkoutSetDTO roundtrips through JSON")
    func workoutSetDTORoundtrip() throws {
        let dto = WorkoutSetDTO(
            id: UUID(),
            order: 1,
            weight: 60.0,
            weightUnit: "kg",
            reps: 8,
            isCompleted: true,
            completedAt: Date(timeIntervalSinceReferenceDate: 0),
            notes: "felt strong"
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(WorkoutSetDTO.self, from: data)
        #expect(decoded.id == dto.id)
        #expect(decoded.order == dto.order)
        #expect(decoded.weight == dto.weight)
        #expect(decoded.weightUnit == dto.weightUnit)
        #expect(decoded.reps == dto.reps)
        #expect(decoded.isCompleted == dto.isCompleted)
        #expect(decoded.notes == dto.notes)
    }

    @Test("WorkoutSetDTO with nil optional fields roundtrips")
    func workoutSetDTONilFields() throws {
        let dto = WorkoutSetDTO(
            id: UUID(),
            order: 0,
            weight: nil,
            weightUnit: "kg",
            reps: nil,
            isCompleted: false,
            completedAt: nil,
            notes: nil
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(WorkoutSetDTO.self, from: data)
        #expect(decoded.weight == nil)
        #expect(decoded.reps == nil)
        #expect(decoded.completedAt == nil)
        #expect(decoded.notes == nil)
    }

    @Test("WorkoutExerciseDTO roundtrips through JSON")
    func workoutExerciseDTORoundtrip() throws {
        let dto = WorkoutExerciseDTO(
            id: UUID(),
            exerciseId: UUID(),
            order: 0,
            notes: "good form",
            restSeconds: 90,
            sets: []
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(WorkoutExerciseDTO.self, from: data)
        #expect(decoded.id == dto.id)
        #expect(decoded.exerciseId == dto.exerciseId)
        #expect(decoded.order == dto.order)
        #expect(decoded.notes == dto.notes)
        #expect(decoded.restSeconds == dto.restSeconds)
    }

    @Test("WorkoutDTO roundtrips through JSON")
    func workoutDTORoundtrip() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let dto = WorkoutDTO(
            id: UUID(),
            templateId: UUID(),
            name: "Push Day",
            startedAt: now,
            completedAt: now.addingTimeInterval(3600),
            notes: nil,
            lastModified: now,
            exercises: []
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(WorkoutDTO.self, from: data)
        #expect(decoded.id == dto.id)
        #expect(decoded.name == dto.name)
        #expect(decoded.templateId == dto.templateId)
        #expect(decoded.notes == nil)
    }

    @Test("TemplateExerciseDTO roundtrips through JSON")
    func templateExerciseDTORoundtrip() throws {
        let dto = TemplateExerciseDTO(
            id: UUID(),
            exerciseId: UUID(),
            order: 2,
            defaultSets: 4,
            defaultReps: 8,
            defaultWeight: 80.0,
            defaultRestSeconds: 120,
            notes: nil
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(TemplateExerciseDTO.self, from: data)
        #expect(decoded.id == dto.id)
        #expect(decoded.defaultSets == dto.defaultSets)
        #expect(decoded.defaultReps == dto.defaultReps)
        #expect(decoded.defaultWeight == dto.defaultWeight)
        #expect(decoded.defaultRestSeconds == dto.defaultRestSeconds)
    }

    @Test("TemplateDTO roundtrips through JSON")
    func templateDTORoundtrip() throws {
        let now = Date(timeIntervalSinceReferenceDate: 2000)
        let dto = TemplateDTO(
            id: UUID(),
            name: "Wednesday Push",
            notes: nil,
            createdAt: now,
            updatedAt: now,
            lastPerformedAt: nil,
            timesPerformed: 5,
            lastModified: now,
            exercises: []
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(TemplateDTO.self, from: data)
        #expect(decoded.id == dto.id)
        #expect(decoded.name == dto.name)
        #expect(decoded.timesPerformed == dto.timesPerformed)
        #expect(decoded.lastPerformedAt == nil)
    }

    @Test("ChatMessageDTO roundtrips through JSON")
    func chatMessageDTORoundtrip() throws {
        let dto = ChatMessageDTO(
            id: UUID(),
            workoutId: nil,
            role: "user",
            content: "How many sets?",
            timestamp: Date(timeIntervalSinceReferenceDate: 3000)
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(ChatMessageDTO.self, from: data)
        #expect(decoded.id == dto.id)
        #expect(decoded.role == dto.role)
        #expect(decoded.content == dto.content)
        #expect(decoded.workoutId == nil)
    }

    @Test("InsightDTO roundtrips through JSON")
    func insightDTORoundtrip() throws {
        let now = Date(timeIntervalSinceReferenceDate: 4000)
        let dto = InsightDTO(
            id: UUID(),
            content: "Train legs!",
            type: "warning",
            generatedAt: now,
            isRead: false,
            lastModified: now
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(InsightDTO.self, from: data)
        #expect(decoded.id == dto.id)
        #expect(decoded.content == dto.content)
        #expect(decoded.type == dto.type)
        #expect(decoded.isRead == dto.isRead)
    }

    @Test("PreferenceDTO roundtrips through JSON")
    func preferenceDTORoundtrip() throws {
        let now = Date(timeIntervalSinceReferenceDate: 5000)
        let dto = PreferenceDTO(
            id: UUID(),
            key: "training_style",
            value: "hypertrophy",
            source: "user_stated",
            lastModified: now
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(PreferenceDTO.self, from: data)
        #expect(decoded.id == dto.id)
        #expect(decoded.key == dto.key)
        #expect(decoded.value == dto.value)
        #expect(decoded.source == dto.source)
    }

    @Test("SyncPullRequest roundtrips through JSON")
    func syncPullRequestRoundtrip() throws {
        let dto = SyncPullRequest(
            lastSyncTimestamp: Date(timeIntervalSinceReferenceDate: 6000),
            collections: ["workouts", "templates"]
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(SyncPullRequest.self, from: data)
        #expect(decoded.collections == dto.collections)
    }

    @Test("SyncPullRequest with nil timestamp roundtrips")
    func syncPullRequestNilTimestamp() throws {
        let dto = SyncPullRequest(lastSyncTimestamp: nil, collections: ["workouts"])
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(SyncPullRequest.self, from: data)
        #expect(decoded.lastSyncTimestamp == nil)
    }

    @Test("SyncPushResponse roundtrips through JSON")
    func syncPushResponseRoundtrip() throws {
        let dto = SyncPushResponse(
            accepted: 5,
            conflicts: 0,
            serverTimestamp: Date(timeIntervalSinceReferenceDate: 7000)
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(SyncPushResponse.self, from: data)
        #expect(decoded.accepted == dto.accepted)
        #expect(decoded.conflicts == dto.conflicts)
    }
}
