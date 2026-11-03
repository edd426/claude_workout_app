import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// `createTemplate` / `updateTemplate` may carry an optional per-exercise
/// `alternatives: [{externalId, note?}]`. Absent keeps what the slot had (old
/// MCP servers never send the key); an empty array clears it; an unknown
/// externalId fails the operation exactly like an unknown main exercise.
@Suite("InboxApplier — template-exercise alternatives")
@MainActor
struct InboxAlternativesTests {

    @MainActor
    private struct Env {
        let container: ModelContainer
        let context: ModelContext
        let templates: SwiftDataTemplateRepository
        let exercises: SwiftDataExerciseRepository
        let alternatives: SwiftDataExerciseAlternativeRepository
        let applier: InboxApplier

        init() throws {
            container = try makeTestContainer()
            context = container.mainContext
            templates = SwiftDataTemplateRepository(context: context)
            exercises = SwiftDataExerciseRepository(context: context)
            alternatives = SwiftDataExerciseAlternativeRepository(context: context)
            applier = InboxApplier(
                templateRepository: templates,
                exerciseRepository: exercises,
                reportRepository: SwiftDataExerciseReportRepository(context: context),
                alternativeRepository: alternatives
            )
            for externalId in ["Barbell_Squat", "Leg_Press", "Hack_Squat", "Goblet_Squat", "Romanian_Deadlift"] {
                context.insert(Exercise(
                    name: externalId.replacingOccurrences(of: "_", with: " "),
                    isCustom: false,
                    externalId: externalId
                ))
            }
            try context.save()
        }

        /// The template's slots in order, each with its alternatives' externalIds.
        func slots(_ templateId: UUID) async throws -> [Slot] {
            guard let template = try await templates.fetch(id: templateId) else { return [] }
            var result: [Slot] = []
            for te in template.exercises.sorted(by: { $0.order < $1.order }) {
                let listed = try await alternatives.alternatives(forTemplateExercise: te.id)
                result.append(Slot(externalId: te.exercise?.externalId, alternatives: listed.map(\.externalId)))
            }
            return result
        }
    }

    private struct Slot: Equatable {
        let externalId: String?
        let alternatives: [String]
    }

    private func operation(
        id: String = UUID().uuidString,
        op: String,
        payload: some Encodable,
        approval: Bool
    ) throws -> InboxOperationDTO {
        let value = try JSONDecoder().decode(InboxJSONValue.self, from: JSONEncoder().encode(payload))
        return InboxOperationDTO(
            id: id,
            createdAt: "2026-11-03T08:00:00.000Z",
            op: op,
            payload: value,
            requiresApproval: approval,
            status: approval ? "awaitingApproval" : "pending",
            appliedAt: nil,
            error: nil
        )
    }

    private func slot(
        _ externalId: String,
        order: Int,
        alternatives: [InboxAlternativePayload]? = nil
    ) -> InboxTemplateExercisePayload {
        InboxTemplateExercisePayload(
            externalId: externalId, order: order, defaultSets: 3, defaultReps: 8,
            defaultWeight: nil, defaultRestSeconds: nil, notes: nil, alternatives: alternatives
        )
    }

    /// Creates "Lower A" through the inbox and returns its id.
    private func create(_ env: Env, exercises: [InboxTemplateExercisePayload]) async throws -> UUID {
        let id = UUID()
        let results = await env.applier.process([
            try operation(
                id: id.uuidString,
                op: "createTemplate",
                payload: CreateTemplatePayload(name: "Lower A", notes: nil, exercises: exercises),
                approval: false
            )
        ])
        try #require(results.first?.status == .applied, "\(results.first?.error ?? "")")
        return id
    }

    private func update(_ env: Env, _ id: UUID, exercises: [InboxTemplateExercisePayload]?) async throws -> InboxAckResult {
        await env.applier.approve(try operation(
            op: "updateTemplate",
            payload: UpdateTemplatePayload(id: id.uuidString, name: nil, notes: nil, exercises: exercises),
            approval: true
        ))
    }

    // MARK: - createTemplate

    @Test("createTemplate stores each slot's alternatives in order, with notes")
    func createStoresAlternatives() async throws {
        let env = try Env()
        let id = try await create(env, exercises: [
            slot("Barbell_Squat", order: 0, alternatives: [
                InboxAlternativePayload(externalId: "Hack_Squat", note: "if the rack is taken"),
                InboxAlternativePayload(externalId: "Leg_Press"),
            ]),
            slot("Romanian_Deadlift", order: 1),
        ])

        let slots = try await env.slots(id)
        #expect(slots.map(\.alternatives) == [["Hack_Squat", "Leg_Press"], []])
        let first = try #require(try await env.templates.fetch(id: id)?.exercises.first { $0.order == 0 })
        let stored = try await env.alternatives.alternatives(forTemplateExercise: first.id)
        #expect(stored.first?.note == "if the rack is taken")
        #expect(stored.map(\.order) == [0, 1])
    }

    @Test("Replaying the same createTemplate does not duplicate alternatives")
    func createReplayIsIdempotent() async throws {
        let env = try Env()
        let opId = UUID().uuidString
        let op = try operation(
            id: opId, op: "createTemplate",
            payload: CreateTemplatePayload(name: "Lower A", notes: nil, exercises: [
                slot("Barbell_Squat", order: 0, alternatives: [InboxAlternativePayload(externalId: "Leg_Press")])
            ]),
            approval: false
        )

        _ = await env.applier.process([op])
        _ = await env.applier.process([op])

        #expect(try await env.alternatives.fetchAll().count == 1)
    }

    @Test("An unknown alternative externalId fails createTemplate and writes nothing")
    func createUnknownAlternativeFails() async throws {
        let env = try Env()
        let id = UUID()
        let results = await env.applier.process([
            try operation(
                id: id.uuidString, op: "createTemplate",
                payload: CreateTemplatePayload(name: "Lower A", notes: nil, exercises: [
                    slot("Barbell_Squat", order: 0, alternatives: [InboxAlternativePayload(externalId: "Not_A_Real_Exercise")])
                ]),
                approval: false
            )
        ])

        #expect(results.first?.status == .failed)
        #expect(results.first?.error?.contains("Not_A_Real_Exercise") == true)
        #expect(try await env.templates.fetch(id: id) == nil)
        #expect(try await env.alternatives.fetchAll().isEmpty)
    }

    @Test("An empty alternative externalId is a malformed payload")
    func emptyAlternativeIdIsMalformed() async throws {
        let env = try Env()
        let results = await env.applier.process([
            try operation(
                op: "createTemplate",
                payload: CreateTemplatePayload(name: "Lower A", notes: nil, exercises: [
                    slot("Barbell_Squat", order: 0, alternatives: [InboxAlternativePayload(externalId: "  ")])
                ]),
                approval: false
            )
        ])

        #expect(results.first?.status == .failed)
        #expect(results.first?.error?.contains("Malformed") == true)
    }

    // MARK: - updateTemplate

    @Test("updateTemplate with alternatives replaces the slot's list")
    func updateReplaces() async throws {
        let env = try Env()
        let id = try await create(env, exercises: [
            slot("Barbell_Squat", order: 0, alternatives: [InboxAlternativePayload(externalId: "Leg_Press")])
        ])

        let result = try await update(env, id, exercises: [
            slot("Barbell_Squat", order: 0, alternatives: [
                InboxAlternativePayload(externalId: "Goblet_Squat"), InboxAlternativePayload(externalId: "Hack_Squat"),
            ])
        ])

        #expect(result.status == .applied)
        #expect(try await env.slots(id).map(\.alternatives) == [["Goblet_Squat", "Hack_Squat"]])
        #expect(try await env.alternatives.fetchAll().count == 2, "the old slot's rows are cleaned up, not left behind")
    }

    /// The applier rebuilds every TemplateExercise on update (fresh ids), so
    /// "untouched" has to mean carried over to the replacement slot — matched
    /// by externalId, slot by slot, the same rule the approval diff uses.
    @Test("updateTemplate without the alternatives key keeps each slot's alternatives")
    func updateAbsentKeeps() async throws {
        let env = try Env()
        let id = try await create(env, exercises: [
            slot("Barbell_Squat", order: 0, alternatives: [InboxAlternativePayload(externalId: "Leg_Press", note: "rack taken")]),
            slot("Romanian_Deadlift", order: 1),
        ])

        // An old MCP server: reorders and changes reps, never mentions alternatives.
        let result = try await update(env, id, exercises: [
            slot("Romanian_Deadlift", order: 0),
            InboxTemplateExercisePayload(
                externalId: "Barbell_Squat", order: 1, defaultSets: 4, defaultReps: 6,
                defaultWeight: nil, defaultRestSeconds: nil, notes: nil
            ),
        ])

        #expect(result.status == .applied)
        let slots = try await env.slots(id)
        #expect(slots.map(\.externalId) == ["Romanian_Deadlift", "Barbell_Squat"])
        #expect(slots.map(\.alternatives) == [[], ["Leg_Press"]])
        let squat = try #require(try await env.templates.fetch(id: id)?.exercises.first { $0.order == 1 })
        #expect(try await env.alternatives.alternatives(forTemplateExercise: squat.id).first?.note == "rack taken")
        #expect(try await env.alternatives.fetchAll().count == 1)
    }

    @Test("updateTemplate with an empty alternatives array clears the slot")
    func updateEmptyClears() async throws {
        let env = try Env()
        let id = try await create(env, exercises: [
            slot("Barbell_Squat", order: 0, alternatives: [InboxAlternativePayload(externalId: "Leg_Press")])
        ])

        let result = try await update(env, id, exercises: [slot("Barbell_Squat", order: 0, alternatives: [])])

        #expect(result.status == .applied)
        #expect(try await env.slots(id).map(\.alternatives) == [[]])
        #expect(try await env.alternatives.fetchAll().isEmpty)
    }

    @Test("A slot that is removed by the update takes its alternatives with it")
    func removedSlotDropsAlternatives() async throws {
        let env = try Env()
        let id = try await create(env, exercises: [
            slot("Barbell_Squat", order: 0, alternatives: [InboxAlternativePayload(externalId: "Leg_Press")]),
            slot("Romanian_Deadlift", order: 1),
        ])

        _ = try await update(env, id, exercises: [slot("Romanian_Deadlift", order: 0)])

        #expect(try await env.alternatives.fetchAll().isEmpty)
    }

    @Test("Duplicate slots of one exercise keep their own alternatives, slot by slot")
    func duplicateSlotsMatchInOrder() async throws {
        let env = try Env()
        let id = try await create(env, exercises: [
            slot("Barbell_Squat", order: 0, alternatives: [InboxAlternativePayload(externalId: "Leg_Press")]),
            slot("Barbell_Squat", order: 1, alternatives: [InboxAlternativePayload(externalId: "Goblet_Squat")]),
        ])

        _ = try await update(env, id, exercises: [slot("Barbell_Squat", order: 0), slot("Barbell_Squat", order: 1)])

        #expect(try await env.slots(id).map(\.alternatives) == [["Leg_Press"], ["Goblet_Squat"]])
    }

    @Test("An update that does not touch exercises leaves alternatives alone")
    func renameOnlyKeeps() async throws {
        let env = try Env()
        let id = try await create(env, exercises: [
            slot("Barbell_Squat", order: 0, alternatives: [InboxAlternativePayload(externalId: "Leg_Press")])
        ])

        let result = await env.applier.approve(try operation(
            op: "updateTemplate",
            payload: UpdateTemplatePayload(id: id.uuidString, name: "Lower A (v2)", notes: nil, exercises: nil),
            approval: true
        ))

        #expect(result.status == .applied)
        #expect(try await env.slots(id).map(\.alternatives) == [["Leg_Press"]])
    }

    @Test("An unknown alternative externalId fails updateTemplate and changes nothing")
    func updateUnknownAlternativeFails() async throws {
        let env = try Env()
        let id = try await create(env, exercises: [
            slot("Barbell_Squat", order: 0, alternatives: [InboxAlternativePayload(externalId: "Leg_Press")])
        ])
        let before = try #require(try await env.templates.fetch(id: id)?.exercises.first?.id)

        let result = try await update(env, id, exercises: [
            slot("Barbell_Squat", order: 0, alternatives: [InboxAlternativePayload(externalId: "Nope_Machine")])
        ])

        #expect(result.status == .failed)
        #expect(result.error?.contains("Nope_Machine") == true)
        #expect(try await env.templates.fetch(id: id)?.exercises.first?.id == before)
        #expect(try await env.slots(id).map(\.alternatives) == [["Leg_Press"]])
    }

    // MARK: - Wire shape

    @Test("The alternatives key decodes tri-state: absent, empty, and listed")
    func payloadDecodesTriState() throws {
        let base = #"{"externalId":"Barbell_Squat","order":0,"defaultSets":3,"defaultReps":8"#
        let absent = try JSONDecoder().decode(InboxTemplateExercisePayload.self, from: Data((base + "}").utf8))
        let empty = try JSONDecoder().decode(InboxTemplateExercisePayload.self, from: Data((base + #","alternatives":[]}"#).utf8))
        let listed = try JSONDecoder().decode(
            InboxTemplateExercisePayload.self,
            from: Data((base + #","alternatives":[{"externalId":"Leg_Press","note":"rack taken"}]}"#).utf8)
        )

        #expect(absent.alternatives == nil)
        #expect(empty.alternatives == [])
        #expect(listed.alternatives == [InboxAlternativePayload(externalId: "Leg_Press", note: "rack taken")])
    }
}
