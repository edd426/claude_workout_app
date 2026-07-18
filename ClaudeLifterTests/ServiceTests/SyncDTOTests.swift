import Testing
import Foundation
@testable import ClaudeLifter

@Suite("SyncDTO Encode/Decode Tests")
struct SyncDTOTests {
    // The wire codecs used by NetworkService — ISO 8601 with fractional seconds,
    // per the v2 snapshot contract.
    private let encoder = NetworkService.makeWireEncoder()
    private let decoder = NetworkService.makeWireDecoder()

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
            exercises: [
                WorkoutExerciseDTO(
                    id: UUID(), exerciseId: UUID(), order: 0,
                    notes: "good form", restSeconds: 90, sets: []
                )
            ]
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(WorkoutDTO.self, from: data)
        #expect(decoded.id == dto.id)
        #expect(decoded.name == dto.name)
        #expect(decoded.templateId == dto.templateId)
        #expect(decoded.notes == nil)
        #expect(decoded.exercises.count == 1)
        #expect(decoded.exercises[0].restSeconds == 90)
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
            exercises: [
                TemplateExerciseDTO(
                    id: UUID(), exerciseId: UUID(), order: 2,
                    defaultSets: 4, defaultReps: 8, defaultWeight: 80.0,
                    defaultRestSeconds: 120, notes: nil
                )
            ]
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(TemplateDTO.self, from: data)
        #expect(decoded.id == dto.id)
        #expect(decoded.name == dto.name)
        #expect(decoded.timesPerformed == dto.timesPerformed)
        #expect(decoded.lastPerformedAt == nil)
        #expect(decoded.exercises.count == 1)
        #expect(decoded.exercises[0].defaultSets == 4)
    }

    @Test("ExerciseDTO roundtrips through JSON including tags")
    func exerciseDTORoundtrip() throws {
        let dto = ExerciseDTO(
            id: UUID(),
            name: "My Cable Fly",
            force: "push",
            level: "beginner",
            mechanic: "isolation",
            equipment: "cable",
            instructions: ["Set pulleys", "Squeeze"],
            primaryMuscles: ["chest"],
            secondaryMuscles: ["shoulders"],
            isCustom: true,
            externalId: nil,
            notes: "seat height 4",
            imageURL: nil,
            photoURL: "exercises/abc.jpg",
            tags: [ExerciseTagDTO(category: "muscle_group", value: "chest")]
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(ExerciseDTO.self, from: data)
        #expect(decoded.id == dto.id)
        #expect(decoded.name == dto.name)
        #expect(decoded.isCustom == true)
        #expect(decoded.instructions == dto.instructions)
        #expect(decoded.notes == dto.notes)
        #expect(decoded.photoURL == dto.photoURL)
        #expect(decoded.tags.count == 1)
        #expect(decoded.tags[0].category == "muscle_group")
        #expect(decoded.tags[0].value == "chest")
    }

    @Test("BodyWeightEntryDTO roundtrips through JSON")
    func bodyWeightEntryDTORoundtrip() throws {
        let dto = BodyWeightEntryDTO(
            id: UUID(),
            weightKg: 81.3,
            recordedAt: Date(timeIntervalSinceReferenceDate: 3000),
            source: "healthkit",
            healthKitSampleUUID: UUID(),
            lastModified: Date(timeIntervalSinceReferenceDate: 3001)
        )
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(BodyWeightEntryDTO.self, from: data)
        #expect(decoded.id == dto.id)
        #expect(decoded.weightKg == dto.weightKg)
        #expect(decoded.source == dto.source)
        #expect(decoded.healthKitSampleUUID == dto.healthKitSampleUUID)
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

    // MARK: - Snapshot wire contract (v2)

    @Test("SnapshotPushRequest always encodes all four collection keys, even when empty")
    func snapshotRequestAlwaysHasFourKeys() throws {
        // The server rejects a body with a missing collection key (400). An empty
        // array means "wipe that type" — so empty must still be on the wire.
        let request = SnapshotPushRequest(
            snapshot: SyncSnapshot(
                workouts: [], templates: [], customExercises: [], bodyWeightEntries: []
            )
        )
        let data = try encoder.encode(request)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["schemaVersion"] as? Int == 2)
        let snapshot = try #require(json["snapshot"] as? [String: Any])
        #expect(snapshot["workouts"] as? [Any] != nil)
        #expect(snapshot["templates"] as? [Any] != nil)
        #expect(snapshot["customExercises"] as? [Any] != nil)
        #expect(snapshot["bodyWeightEntries"] as? [Any] != nil)
    }

    @Test("SnapshotPushResponse decodes the contract-literal JSON")
    func snapshotPushResponseDecodesContractJSON() throws {
        // Verbatim from the wire contract, fractional-second serverTime included.
        let json = """
        {
          "revision": 42,
          "serverTime": "2026-07-18T18:00:00.000Z",
          "counts": {
            "workouts": {"upserted": 3, "deleted": 1},
            "templates": {"upserted": 0, "deleted": 0},
            "customExercises": {"upserted": 2, "deleted": 0},
            "bodyWeightEntries": {"upserted": 5, "deleted": 0}
          }
        }
        """
        let response = try decoder.decode(
            SnapshotPushResponse.self, from: Data(json.utf8)
        )
        #expect(response.revision == 42)
        #expect(response.counts["workouts"]?.upserted == 3)
        #expect(response.counts["workouts"]?.deleted == 1)
        #expect(response.counts["bodyWeightEntries"]?.upserted == 5)
        let expected = ISO8601DateFormatter()
        expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(response.serverTime == expected.date(from: "2026-07-18T18:00:00.000Z"))
    }

    @Test("SnapshotFetchResponse decodes a fresh mirror (revision 0, empty arrays)")
    func snapshotFetchResponseDecodesFreshMirror() throws {
        let json = """
        {
          "revision": 0,
          "serverTime": "2026-07-18T18:00:00.000Z",
          "snapshot": {
            "workouts": [],
            "templates": [],
            "customExercises": [],
            "bodyWeightEntries": []
          }
        }
        """
        let response = try decoder.decode(
            SnapshotFetchResponse.self, from: Data(json.utf8)
        )
        #expect(response.revision == 0)
        #expect(response.snapshot.workouts.isEmpty)
        #expect(response.snapshot.bodyWeightEntries.isEmpty)
    }

    @Test("wire decoder accepts dates without fractional seconds too")
    func wireDecoderAcceptsPlainISO8601() throws {
        let json = """
        {"revision": 1, "serverTime": "2026-07-18T18:00:00Z", "counts": {}}
        """
        let response = try decoder.decode(
            SnapshotPushResponse.self, from: Data(json.utf8)
        )
        #expect(response.revision == 1)
    }

    @Test("wire encoder writes dates with fractional seconds")
    func wireEncoderWritesFractionalSeconds() throws {
        struct Box: Codable { let date: Date }
        let data = try encoder.encode(Box(date: Date(timeIntervalSince1970: 1_752_861_600)))
        let string = try #require(String(data: data, encoding: .utf8))
        // "2025-07-18T18:00:00.000Z" — fractional seconds must be present
        #expect(string.contains(".000Z"))
    }

    @Test("SnapshotFetchResponse roundtrips with populated snapshot")
    func snapshotFetchResponseRoundtrip() throws {
        let workout = WorkoutDTO(
            id: UUID(), templateId: nil, name: "Push Day",
            startedAt: Date(timeIntervalSinceReferenceDate: 100), completedAt: nil,
            notes: nil, lastModified: Date(timeIntervalSinceReferenceDate: 101),
            exercises: []
        )
        let response = SnapshotFetchResponse(
            revision: 3,
            serverTime: Date(timeIntervalSinceReferenceDate: 200),
            snapshot: SyncSnapshot(
                workouts: [workout], templates: [], customExercises: [],
                bodyWeightEntries: []
            )
        )
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(SnapshotFetchResponse.self, from: data)
        #expect(decoded.revision == 3)
        #expect(decoded.snapshot.workouts.count == 1)
        #expect(decoded.snapshot.workouts[0].name == "Push Day")
    }
}
