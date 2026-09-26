import Testing
import Foundation
@testable import ClaudeLifter

// MARK: - Pure diff (#153, #147)

private func snapshotExercise(
    _ externalId: String,
    name: String? = nil,
    sets: Int = 3,
    reps: Int = 10,
    weight: Double? = nil,
    rest: Int = 90,
    notes: String? = nil
) -> TemplateSnapshot.Exercise {
    TemplateSnapshot.Exercise(
        externalId: externalId,
        name: name ?? externalId.replacingOccurrences(of: "_", with: " "),
        sets: sets,
        reps: reps,
        weight: weight,
        restSeconds: rest,
        notes: notes
    )
}

private func payloadExercise(
    _ externalId: String,
    order: Int,
    sets: Int = 3,
    reps: Int = 10,
    weight: Double? = nil,
    rest: Int? = 90,
    notes: String? = nil
) -> InboxTemplateExercisePayload {
    InboxTemplateExercisePayload(
        externalId: externalId,
        order: order,
        defaultSets: sets,
        defaultReps: reps,
        defaultWeight: weight,
        defaultRestSeconds: rest,
        notes: notes
    )
}

private let lowerB = TemplateSnapshot(
    name: "Lower B",
    notes: nil,
    exercises: [
        snapshotExercise("Trap_Bar_Deadlift", sets: 3, reps: 5),
        snapshotExercise("Split_Squat_with_Dumbbells", sets: 2, reps: 8),
        snapshotExercise("Seated_Leg_Curl", sets: 3, reps: 12),
        snapshotExercise("Ab_Crunch_Machine", sets: 3, reps: 15, weight: 45, notes: "TechnoGym"),
    ]
)

private func lowerBPayload(
    name: String? = nil,
    notes: String? = nil,
    exercises: [InboxTemplateExercisePayload]?
) -> UpdateTemplatePayload {
    UpdateTemplatePayload(id: UUID().uuidString, name: name, notes: notes, exercises: exercises)
}

@Suite("TemplateUpdateDiff")
struct TemplateUpdateDiffTests {

    @Test("a single reps change is reported as one prescription line, nothing else")
    func repsChange() {
        let payload = lowerBPayload(exercises: [
            payloadExercise("Trap_Bar_Deadlift", order: 0, sets: 3, reps: 10),
            payloadExercise("Split_Squat_with_Dumbbells", order: 1, sets: 2, reps: 8),
            payloadExercise("Seated_Leg_Curl", order: 2, sets: 3, reps: 12),
            payloadExercise("Ab_Crunch_Machine", order: 3, sets: 3, reps: 15, weight: 45, notes: "TechnoGym"),
        ])

        let lines = TemplateUpdateDiff.lines(payload: payload, current: lowerB, nameFor: { $0 })

        #expect(lines == [
            .prescriptionChanged(name: "Trap Bar Deadlift", from: "3 × 5", to: "3 × 10"),
        ])
        #expect(lines[0].text == "Trap Bar Deadlift: 3 × 5 → 3 × 10")
    }

    @Test("an identical payload produces no lines")
    func noChange() {
        let payload = lowerBPayload(exercises: [
            payloadExercise("Trap_Bar_Deadlift", order: 0, sets: 3, reps: 5),
            payloadExercise("Split_Squat_with_Dumbbells", order: 1, sets: 2, reps: 8),
            payloadExercise("Seated_Leg_Curl", order: 2, sets: 3, reps: 12),
            payloadExercise("Ab_Crunch_Machine", order: 3, sets: 3, reps: 15, weight: 45, notes: "TechnoGym"),
        ])

        #expect(TemplateUpdateDiff.lines(payload: payload, current: lowerB, nameFor: { $0 }).isEmpty)
    }

    @Test("a nil rest in the payload means the 90s default, not a change")
    func nilRestIsDefault() {
        let payload = lowerBPayload(exercises: [
            payloadExercise("Trap_Bar_Deadlift", order: 0, sets: 3, reps: 5, rest: nil),
            payloadExercise("Split_Squat_with_Dumbbells", order: 1, sets: 2, reps: 8, rest: nil),
            payloadExercise("Seated_Leg_Curl", order: 2, sets: 3, reps: 12, rest: nil),
            payloadExercise("Ab_Crunch_Machine", order: 3, sets: 3, reps: 15, weight: 45, rest: nil, notes: "TechnoGym"),
        ])

        #expect(TemplateUpdateDiff.lines(payload: payload, current: lowerB, nameFor: { $0 }).isEmpty)
    }

    @Test("note edits are reported per exercise with before and after")
    func noteChange() {
        let payload = lowerBPayload(exercises: [
            payloadExercise("Trap_Bar_Deadlift", order: 0, sets: 3, reps: 5),
            payloadExercise("Split_Squat_with_Dumbbells", order: 1, sets: 2, reps: 8),
            payloadExercise("Seated_Leg_Curl", order: 2, sets: 3, reps: 12),
            payloadExercise("Ab_Crunch_Machine", order: 3, sets: 3, reps: 15, weight: 45, notes: "TechnoGym Total Abdominal"),
        ])

        let lines = TemplateUpdateDiff.lines(payload: payload, current: lowerB, nameFor: { $0 })

        #expect(lines == [
            .noteChanged(name: "Ab Crunch Machine", from: "TechnoGym", to: "TechnoGym Total Abdominal"),
        ])
    }

    @Test("whitespace-only note differences are not changes")
    func noteWhitespaceIgnored() {
        let payload = lowerBPayload(exercises: [
            payloadExercise("Trap_Bar_Deadlift", order: 0, sets: 3, reps: 5, notes: "   "),
            payloadExercise("Split_Squat_with_Dumbbells", order: 1, sets: 2, reps: 8),
            payloadExercise("Seated_Leg_Curl", order: 2, sets: 3, reps: 12),
            payloadExercise("Ab_Crunch_Machine", order: 3, sets: 3, reps: 15, weight: 45, notes: " TechnoGym\n"),
        ])

        #expect(TemplateUpdateDiff.lines(payload: payload, current: lowerB, nameFor: { $0 }).isEmpty)
    }

    @Test("adds, removes and swaps name the exercise, resolving new names through the lookup")
    func addRemove() {
        let payload = lowerBPayload(exercises: [
            payloadExercise("Trap_Bar_Deadlift", order: 0, sets: 3, reps: 5),
            payloadExercise("Split_Squat_with_Dumbbells", order: 1, sets: 2, reps: 8),
            payloadExercise("Seated_Leg_Curl", order: 2, sets: 3, reps: 12),
            payloadExercise("Hanging_Leg_Raise", order: 3, sets: 3, reps: 12),
        ])

        let lines = TemplateUpdateDiff.lines(payload: payload, current: lowerB) { externalId in
            externalId == "Hanging_Leg_Raise" ? "Hanging Leg Raise" : externalId
        }

        #expect(lines == [
            .exerciseAdded(name: "Hanging Leg Raise", prescription: "3 × 12"),
            .exerciseRemoved(name: "Ab Crunch Machine"),
        ])
    }

    @Test("reordering surviving exercises is one line in the new order")
    func reorder() {
        let payload = lowerBPayload(exercises: [
            payloadExercise("Seated_Leg_Curl", order: 0, sets: 3, reps: 12),
            payloadExercise("Trap_Bar_Deadlift", order: 1, sets: 3, reps: 5),
            payloadExercise("Split_Squat_with_Dumbbells", order: 2, sets: 2, reps: 8),
            payloadExercise("Ab_Crunch_Machine", order: 3, sets: 3, reps: 15, weight: 45, notes: "TechnoGym"),
        ])

        let lines = TemplateUpdateDiff.lines(payload: payload, current: lowerB, nameFor: { $0 })

        #expect(lines == [
            .reordered(names: ["Seated Leg Curl", "Trap Bar Deadlift", "Split Squat with Dumbbells", "Ab Crunch Machine"]),
        ])
    }

    @Test("payload order wins over array position")
    func orderFieldRespected() {
        // Same as the snapshot, but the array is shuffled and `order` restores it.
        let payload = lowerBPayload(exercises: [
            payloadExercise("Ab_Crunch_Machine", order: 3, sets: 3, reps: 15, weight: 45, notes: "TechnoGym"),
            payloadExercise("Trap_Bar_Deadlift", order: 0, sets: 3, reps: 5),
            payloadExercise("Seated_Leg_Curl", order: 2, sets: 3, reps: 12),
            payloadExercise("Split_Squat_with_Dumbbells", order: 1, sets: 2, reps: 8),
        ])

        #expect(TemplateUpdateDiff.lines(payload: payload, current: lowerB, nameFor: { $0 }).isEmpty)
    }

    @Test("weight and rest changes are their own lines")
    func weightAndRest() {
        let payload = lowerBPayload(exercises: [
            payloadExercise("Trap_Bar_Deadlift", order: 0, sets: 3, reps: 5, rest: 120),
            payloadExercise("Split_Squat_with_Dumbbells", order: 1, sets: 2, reps: 8),
            payloadExercise("Seated_Leg_Curl", order: 2, sets: 3, reps: 12),
            payloadExercise("Ab_Crunch_Machine", order: 3, sets: 3, reps: 15, weight: 50, notes: "TechnoGym"),
        ])

        let lines = TemplateUpdateDiff.lines(payload: payload, current: lowerB, nameFor: { $0 })

        #expect(lines == [
            .restChanged(name: "Trap Bar Deadlift", from: 90, to: 120),
            .weightChanged(name: "Ab Crunch Machine", from: 45, to: 50),
        ])
        #expect(lines[0].text == "Trap Bar Deadlift: rest 90s → 120s")
        #expect(lines[1].text == "Ab Crunch Machine: weight 45 → 50")
    }

    @Test("details-only payload compares name and note, and leaves exercises alone")
    func detailsOnly() {
        let payload = lowerBPayload(name: "Lower B (Thu)", notes: "Runs Thursday", exercises: nil)

        let lines = TemplateUpdateDiff.lines(payload: payload, current: lowerB, nameFor: { $0 })

        #expect(lines == [
            .renamed(from: "Lower B", to: "Lower B (Thu)"),
            .templateNoteChanged(from: nil, to: "Runs Thursday"),
        ])
    }

    @Test("a duplicated exercise matches slot by slot rather than collapsing")
    func duplicatesMatchInOrder() {
        let current = TemplateSnapshot(name: "Arms", notes: nil, exercises: [
            snapshotExercise("Hammer_Curls", sets: 3, reps: 10),
            snapshotExercise("Hammer_Curls", sets: 2, reps: 15),
        ])
        let payload = lowerBPayload(exercises: [
            payloadExercise("Hammer_Curls", order: 0, sets: 3, reps: 10),
            payloadExercise("Hammer_Curls", order: 1, sets: 2, reps: 20),
        ])

        let lines = TemplateUpdateDiff.lines(payload: payload, current: current, nameFor: { $0 })

        #expect(lines == [
            .prescriptionChanged(name: "Hammer Curls", from: "2 × 15", to: "2 × 20"),
        ])
    }
}

// MARK: - Preview builder (repositories → preview)

@Suite("InboxChangePreviewBuilder")
@MainActor
struct InboxChangePreviewBuilderTests {

    private func makeLowerB() -> (WorkoutTemplate, MockTemplateRepository, MockExerciseRepository) {
        let template = TestFixtures.makeTemplate(name: "Lower B")
        let deadlift = TestFixtures.makeExercise(name: "Trap Bar Deadlift", externalId: "Trap_Bar_Deadlift")
        let curl = TestFixtures.makeExercise(name: "Seated Leg Curl", externalId: "Seated_Leg_Curl")
        template.exercises = [
            TemplateExercise(order: 0, exercise: deadlift, defaultSets: 3, defaultReps: 5),
            TemplateExercise(order: 1, exercise: curl, defaultSets: 3, defaultReps: 12),
        ]
        let templates = MockTemplateRepository()
        templates.templates = [template]
        let exercises = MockExerciseRepository()
        exercises.exercises = [deadlift, curl, TestFixtures.makeExercise(name: "Hanging Leg Raise", externalId: "Hanging_Leg_Raise")]
        return (template, templates, exercises)
    }

    private func updateOperation(templateId: UUID, exercises: [InboxJSONValue]) -> InboxOperationDTO {
        InboxOperationDTO(
            id: "op-1",
            createdAt: "2026-09-26T06:50:37.446Z",
            op: "updateTemplate",
            payload: .object([
                "id": .string(templateId.uuidString),
                "exercises": .array(exercises),
            ]),
            requiresApproval: true,
            status: "awaitingApproval",
            appliedAt: nil,
            error: nil
        )
    }

    private func exerciseJSON(_ externalId: String, order: Int, sets: Int, reps: Int) -> InboxJSONValue {
        .object([
            "externalId": .string(externalId),
            "order": .number(Double(order)),
            "defaultSets": .number(Double(sets)),
            "defaultReps": .number(Double(reps)),
        ])
    }

    @Test("an update against the local template yields a titled, summarised diff")
    func updatePreview() async {
        let (template, templates, exercises) = makeLowerB()
        let builder = InboxChangePreviewBuilder(templateRepository: templates, exerciseRepository: exercises)
        let operation = updateOperation(templateId: template.id, exercises: [
            exerciseJSON("Trap_Bar_Deadlift", order: 0, sets: 3, reps: 10),
            exerciseJSON("Seated_Leg_Curl", order: 1, sets: 3, reps: 12),
        ])

        let preview = await builder.preview(for: operation)

        #expect(preview.title == "Update “Lower B”")
        #expect(preview.lines == [.prescriptionChanged(name: "Trap Bar Deadlift", from: "3 × 5", to: "3 × 10")])
        #expect(preview.summary == "Trap Bar Deadlift: 3 × 5 → 3 × 10")
        #expect(preview.isDestructive == false)
    }

    @Test("added exercises are named from the library, or humanised when unknown")
    func addedNames() async {
        let (template, templates, exercises) = makeLowerB()
        let builder = InboxChangePreviewBuilder(templateRepository: templates, exerciseRepository: exercises)
        let operation = updateOperation(templateId: template.id, exercises: [
            exerciseJSON("Trap_Bar_Deadlift", order: 0, sets: 3, reps: 5),
            exerciseJSON("Seated_Leg_Curl", order: 1, sets: 3, reps: 12),
            exerciseJSON("Hanging_Leg_Raise", order: 2, sets: 3, reps: 12),
            exerciseJSON("Some_New_Thing", order: 3, sets: 2, reps: 8),
        ])

        let preview = await builder.preview(for: operation)

        #expect(preview.lines == [
            .exerciseAdded(name: "Hanging Leg Raise", prescription: "3 × 12"),
            .exerciseAdded(name: "Some New Thing", prescription: "2 × 8"),
        ])
    }

    @Test("a no-op update says so instead of showing an empty list")
    func noOpUpdate() async {
        let (template, templates, exercises) = makeLowerB()
        let builder = InboxChangePreviewBuilder(templateRepository: templates, exerciseRepository: exercises)
        let operation = updateOperation(templateId: template.id, exercises: [
            exerciseJSON("Trap_Bar_Deadlift", order: 0, sets: 3, reps: 5),
            exerciseJSON("Seated_Leg_Curl", order: 1, sets: 3, reps: 12),
        ])

        let preview = await builder.preview(for: operation)

        #expect(preview.lines.isEmpty)
        #expect(preview.summary == "No differences from the current template.")
    }

    @Test("a template missing locally is called out rather than diffed against nothing")
    func missingTemplate() async {
        let (_, templates, exercises) = makeLowerB()
        let builder = InboxChangePreviewBuilder(templateRepository: templates, exerciseRepository: exercises)
        let operation = updateOperation(templateId: UUID(), exercises: [])

        let preview = await builder.preview(for: operation)

        #expect(preview.title == "Update template")
        #expect(preview.summary.contains("not on this phone"))
    }

    @Test("a delete is destructive and counts what goes")
    func deletePreview() async {
        let (template, templates, exercises) = makeLowerB()
        let builder = InboxChangePreviewBuilder(templateRepository: templates, exerciseRepository: exercises)
        let operation = InboxOperationDTO(
            id: "op-2",
            createdAt: "2026-09-26T06:50:37.446Z",
            op: "deleteTemplate",
            payload: .object(["id": .string(template.id.uuidString), "name": .string("Lower B")]),
            requiresApproval: true,
            status: "awaitingApproval",
            appliedAt: nil,
            error: nil
        )

        let preview = await builder.preview(for: operation)

        #expect(preview.title == "Delete “Lower B”")
        #expect(preview.isDestructive)
        #expect(preview.summary == "Removes the template and its 2 exercises from this phone and the cloud.")
    }
}
