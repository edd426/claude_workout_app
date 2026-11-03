import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// The approval diff (#153) must show alternative changes. Without it, an
/// `updateTemplate` that only changes alternatives previews as "No
/// differences" — and the user approves a change they were never shown.
@Suite("Inbox preview — template-exercise alternatives")
struct InboxAlternativesPreviewTests {

    private func slot(_ externalId: String, name: String, alternatives: [String] = []) -> TemplateSnapshot.Exercise {
        var exercise = TemplateSnapshot.Exercise(
            externalId: externalId, name: name, sets: 3, reps: 8, weight: nil, restSeconds: 90, notes: nil
        )
        exercise.alternatives = alternatives
        return exercise
    }

    private func payloadSlot(_ externalId: String, order: Int, alternatives: [String]?) -> InboxTemplateExercisePayload {
        InboxTemplateExercisePayload(
            externalId: externalId, order: order, defaultSets: 3, defaultReps: 8,
            defaultWeight: nil, defaultRestSeconds: nil, notes: nil,
            alternatives: alternatives?.map { InboxAlternativePayload(externalId: $0) }
        )
    }

    private func names(_ externalId: String) -> String {
        TemplateUpdateDiff.humanized(externalId)
    }

    @Test("A changed alternatives list is a line of its own, named for people")
    func changedListIsALine() {
        let current = TemplateSnapshot(name: "Lower A", notes: nil, exercises: [
            slot("Barbell_Squat", name: "Barbell Squat", alternatives: ["Leg_Press"])
        ])
        let payload = UpdateTemplatePayload(id: UUID().uuidString, name: nil, notes: nil, exercises: [
            payloadSlot("Barbell_Squat", order: 0, alternatives: ["Hack_Squat", "Goblet_Squat"])
        ])

        let lines = TemplateUpdateDiff.lines(payload: payload, current: current, nameFor: names)

        #expect(lines == [.alternativesChanged(name: "Barbell Squat", from: ["Leg Press"], to: ["Hack Squat", "Goblet Squat"])])
        #expect(lines.first?.text == "Barbell Squat: alternatives Leg Press → Hack Squat, Goblet Squat")
    }

    @Test("Absent alternatives are not a change — the apply keeps them")
    func absentIsNoChange() {
        let current = TemplateSnapshot(name: "Lower A", notes: nil, exercises: [
            slot("Barbell_Squat", name: "Barbell Squat", alternatives: ["Leg_Press"])
        ])
        let payload = UpdateTemplatePayload(id: UUID().uuidString, name: nil, notes: nil, exercises: [
            payloadSlot("Barbell_Squat", order: 0, alternatives: nil)
        ])

        #expect(TemplateUpdateDiff.lines(payload: payload, current: current, nameFor: names).isEmpty)
    }

    @Test("The same list again is not a change")
    func sameListIsNoChange() {
        let current = TemplateSnapshot(name: "Lower A", notes: nil, exercises: [
            slot("Barbell_Squat", name: "Barbell Squat", alternatives: ["Leg_Press"])
        ])
        let payload = UpdateTemplatePayload(id: UUID().uuidString, name: nil, notes: nil, exercises: [
            payloadSlot("Barbell_Squat", order: 0, alternatives: ["Leg_Press"])
        ])

        #expect(TemplateUpdateDiff.lines(payload: payload, current: current, nameFor: names).isEmpty)
    }

    @Test("An empty list clears, and says so")
    func emptyListClears() {
        let current = TemplateSnapshot(name: "Lower A", notes: nil, exercises: [
            slot("Barbell_Squat", name: "Barbell Squat", alternatives: ["Leg_Press"])
        ])
        let payload = UpdateTemplatePayload(id: UUID().uuidString, name: nil, notes: nil, exercises: [
            payloadSlot("Barbell_Squat", order: 0, alternatives: [])
        ])

        let lines = TemplateUpdateDiff.lines(payload: payload, current: current, nameFor: names)

        #expect(lines == [.alternativesChanged(name: "Barbell Squat", from: ["Leg Press"], to: [])])
        #expect(lines.first?.text == "Barbell Squat: alternatives Leg Press → none")
    }

    @Test("An added exercise that lists alternatives shows them too")
    func addedSlotShowsAlternatives() {
        let current = TemplateSnapshot(name: "Lower A", notes: nil, exercises: [])
        let payload = UpdateTemplatePayload(id: UUID().uuidString, name: nil, notes: nil, exercises: [
            payloadSlot("Barbell_Squat", order: 0, alternatives: ["Leg_Press"])
        ])

        let lines = TemplateUpdateDiff.lines(payload: payload, current: current, nameFor: names)

        #expect(lines.contains(.alternativesChanged(name: "Barbell Squat", from: [], to: ["Leg Press"])))
    }

    @Test("The builder reads local alternatives, so an alternatives-only update is not a no-op")
    @MainActor
    func builderSeesAlternatives() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let squat = Exercise(name: "Barbell Squat", isCustom: false, externalId: "Barbell_Squat")
        let legPress = Exercise(name: "Leg Press", isCustom: false, externalId: "Leg_Press")
        let hack = Exercise(name: "Hack Squat", isCustom: false, externalId: "Hack_Squat")
        [squat, legPress, hack].forEach { context.insert($0) }
        let templates = SwiftDataTemplateRepository(context: context)
        let alternatives = SwiftDataExerciseAlternativeRepository(context: context)
        let template = WorkoutTemplate(name: "Lower A")
        let te = TemplateExercise(order: 0, exercise: squat, defaultSets: 3, defaultReps: 8)
        template.exercises.append(te)
        try await templates.save(template)
        try await alternatives.replaceAlternatives(forTemplateExercise: te.id, with: [AlternativeSpec(externalId: "Leg_Press")])
        let builder = InboxChangePreviewBuilder(
            templateRepository: templates,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            alternativeRepository: alternatives
        )
        let payload = UpdateTemplatePayload(id: template.id.uuidString, name: nil, notes: nil, exercises: [
            payloadSlot("Barbell_Squat", order: 0, alternatives: ["Hack_Squat"])
        ])
        let value = try JSONDecoder().decode(InboxJSONValue.self, from: JSONEncoder().encode(payload))
        let operation = InboxOperationDTO(
            id: UUID().uuidString, createdAt: "2026-11-03T08:00:00.000Z", op: "updateTemplate",
            payload: value, requiresApproval: true, status: "awaitingApproval", appliedAt: nil, error: nil
        )

        let preview = await builder.preview(for: operation)

        #expect(preview.lines == [.alternativesChanged(name: "Barbell Squat", from: ["Leg Press"], to: ["Hack Squat"])])
        #expect(preview.summary == "Barbell Squat: alternatives Leg Press → Hack Squat")
    }
}
