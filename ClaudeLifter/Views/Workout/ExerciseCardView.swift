import SwiftUI

struct ExerciseCardView: View {
    let workoutExercise: WorkoutExercise
    let focusedField: FocusState<SetEntryFieldID?>.Binding
    let previousValue: (WorkoutSet) -> AutoFillResult?
    let onCompleteSet: (WorkoutSet) -> Void
    let onEditWeight: (WorkoutSet, Double?) -> Void
    let onEditReps: (WorkoutSet, Int?) -> Void
    let onAddSet: () -> Void
    var onRemoveSet: ((WorkoutSet) -> Void)? = nil
    /// Files a report against this exercise (issue #135). The gym is where
    /// the problem is noticed, so this is the entry point that matters.
    var onReport: (() -> Void)? = nil
    /// Opens the per-exercise note editor (issue #136). The machine settings
    /// are needed standing at the machine, so the note is shown inline and the
    /// editor is one tap from it.
    var onEditNotes: (() -> Void)? = nil
    /// Opens the editor for this workout's copy of the template's note — the
    /// Coach's cue (reports 31A4983B, E26BBFAA), which used to be read-only.
    var onEditTemplateNote: (() -> Void)? = nil
    /// The template plan for this exercise (#144). Nil for ad-hoc workouts and
    /// exercises added mid-session — both genuinely have no target, and an
    /// invented one would be worse than none.
    var plannedTarget: PlannedTarget? = nil
    /// Whether last session's reps for a given set missed that target.
    var previousDrifted: (WorkoutSet) -> Bool = { _ in false }
    /// Loads the "last done" panel (#167). Nil hides the disclosure entirely.
    var loadRecency: (@MainActor () async -> ExerciseRecency?)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The template note starts collapsed to one line (report 31A4983B: "They
    /// take up a lot of space … should be clicked into, but not prominent").
    @State private var isTemplateNoteExpanded = false
    /// The "last done" panel starts collapsed and costs no height until
    /// opened (#167); its content is loaded on first expand.
    @State private var isLastDoneExpanded = false
    @State private var recency: ExerciseRecency?
    @State private var recencyLoadFailed = false

    private var sortedSets: [WorkoutSet] {
        workoutExercise.sets.sorted(by: { $0.order < $1.order })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            exerciseHeader
            if isLastDoneExpanded {
                LastDonePanel(recency: recency, loadFailed: recencyLoadFailed)
            }
            targetRow
            notesRow
            Divider()
            setEntryRows
            addSetButton
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: isLastDoneExpanded) { await loadRecencyIfNeeded() }
    }

    private func loadRecencyIfNeeded() async {
        guard isLastDoneExpanded, recency == nil, let loadRecency else { return }
        recencyLoadFailed = false
        recency = await loadRecency()
        recencyLoadFailed = recency == nil
    }

    /// The plan, so drift is visible while training rather than only in
    /// hindsight (#144). Without it the screen showed what you did last time
    /// and nothing about what was intended, so 8 → 12 → 12 → 12 each looked
    /// locally reasonable.
    @ViewBuilder
    private var targetRow: some View {
        if let plannedTarget {
            Text("Target \(plannedTarget.summary)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Target \(plannedTarget.sets) sets of \(plannedTarget.reps) reps")
                .accessibilityIdentifier("exerciseTarget")
        }
    }

    /// The durable note lives on the library `Exercise` — it describes the
    /// machine, so it follows the exercise into every workout (#136). The
    /// session note is this workout's copy of the template's cue, usually
    /// written by the Coach; it is shown beneath, collapsed to one line.
    private var exerciseNotes: String? {
        Self.cleaned(workoutExercise.exercise?.notes)
    }

    private var sessionNotes: String? {
        let session = Self.cleaned(workoutExercise.notes)
        return session == exerciseNotes ? nil : session
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !value.isEmpty else { return nil }
        return value
    }

    /// The user's own note is shown in full, unconditionally when present — a
    /// note behind a tap is a note you do not read mid-set, which is the whole
    /// of #136. The template note is the opposite case (report 31A4983B): long
    /// Coach prose that crowded the card, so it gets one line until tapped.
    @ViewBuilder
    private var notesRow: some View {
        if exerciseNotes != nil || sessionNotes != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let exerciseNotes {
                    noteLine(
                        exerciseNotes,
                        systemImage: "note.text",
                        identifier: "exerciseNotes",
                        label: "Note"
                    )
                }
                if let sessionNotes {
                    templateNoteLine(sessionNotes)
                }
            }
        }
    }

    @ViewBuilder
    private func templateNoteLine(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy) { isTemplateNoteExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "text.bubble")
                    Text(text)
                        .lineLimit(isTemplateNoteExpanded ? nil : 1)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isTemplateNoteExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Template note: \(text)")
            .accessibilityHint(isTemplateNoteExpanded ? "Collapses the note" : "Shows the whole note")
            .accessibilityIdentifier("sessionNotes")

            if isTemplateNoteExpanded, let onEditTemplateNote {
                Button("Edit template note", action: onEditTemplateNote)
                    .font(.caption)
                    .accessibilityIdentifier("editTemplateNote")
            }
        }
    }

    @ViewBuilder
    private func noteLine(
        _ text: String,
        systemImage: String,
        identifier: String,
        label: String
    ) -> some View {
        let content = Label {
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(text)")
        .accessibilityIdentifier(identifier)

        if let onEditNotes, identifier == "exerciseNotes" {
            Button(action: onEditNotes) { content }
                .buttonStyle(.plain)
                .accessibilityHint("Edit this note")
        } else {
            content
        }
    }

    @ViewBuilder
    private var setEntryRows: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                ForEach(sortedSets, id: \.id) { set in
                    setRow(set, layout: .stacked)
                        .id(set.id)
                }
            }
        } else {
            Grid(horizontalSpacing: 8, verticalSpacing: 2) {
                columnHeaders
                ForEach(sortedSets, id: \.id) { set in
                    setRow(set, layout: .compact)
                        .id(set.id)
                }
            }
        }
    }

    private func setRow(
        _ set: WorkoutSet,
        layout: SetRowLayout
    ) -> some View {
        SetRowView(
            workoutExerciseID: workoutExercise.id,
            set: set,
            previous: previousValue(set),
            previousDrifted: previousDrifted(set),
            layout: layout,
            focusedField: focusedField,
            onComplete: onCompleteSet,
            onEditWeight: onEditWeight,
            onEditReps: onEditReps
        )
    }

    private var columnHeaders: some View {
        GridRow {
            headerText("SET", alignment: .leading)
            headerText("PREVIOUS", alignment: .trailing)
            headerText("WEIGHT", alignment: .trailing)
            headerText("REPS", alignment: .trailing)
            Color.clear
                .frame(width: 44, height: 1)
                .accessibilityHidden(true)
        }
    }

    private func headerText(
        _ title: String,
        alignment: HorizontalAlignment
    ) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(alignment)
    }

    private var addSetButton: some View {
        Button(action: onAddSet) {
            Label("Add Set", systemImage: "plus.circle")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .padding(.top, 4)
    }

    private var exerciseHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workoutExercise.exercise?.name ?? "Unknown Exercise")
                    .font(.headline)
                musclesLine
            }
            Spacer()
            actionsMenu
        }
    }

    /// The primary muscles, as before. With a recency loader the same line is
    /// the "last done" disclosure (#167), so the collapsed card keeps its
    /// height: a clock and chevron are the only additions.
    @ViewBuilder
    private var musclesLine: some View {
        let muscles = workoutExercise.exercise?.primaryMuscles ?? []
        let text = muscles.joined(separator: ", ")
        if loadRecency != nil {
            Button {
                withAnimation(.snappy) { isLastDoneExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(muscles.isEmpty ? "Last done" : text)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "clock.arrow.circlepath")
                    Image(systemName: isLastDoneExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                // Taller hit area than the caption line, without changing layout.
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .padding(.vertical, -6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(muscles.isEmpty ? "Last done" : "\(text), last done")
            .accessibilityHint(
                isLastDoneExpanded
                    ? "Hides when you last did this exercise"
                    : "Shows when you last did this exercise and trained these muscles"
            )
            .accessibilityIdentifier("lastDoneToggle")
        } else if !muscles.isEmpty {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionsMenu: some View {
        if onRemoveSet != nil || onReport != nil || onEditNotes != nil
            || onEditTemplateNote != nil {
            Menu {
                if let onEditNotes {
                    Button {
                        onEditNotes()
                    } label: {
                        Label(
                            exerciseNotes == nil ? "Add a note…" : "Edit note…",
                            systemImage: "note.text"
                        )
                    }
                    .accessibilityIdentifier("editExerciseNotes")
                }
                if sessionNotes != nil, let onEditTemplateNote {
                    Button {
                        onEditTemplateNote()
                    } label: {
                        Label("Edit template note…", systemImage: "text.bubble")
                    }
                    .accessibilityIdentifier("editTemplateNoteMenu")
                }
                if let onReport {
                    Button {
                        onReport()
                    } label: {
                        Label("Report a problem…", systemImage: "flag")
                    }
                    .accessibilityIdentifier("reportExercise")
                }
                if sortedSets.count > 1, let onRemoveSet {
                    Section("Remove Set…") {
                        ForEach(sortedSets, id: \.id) { set in
                            Button("Set \(set.order + 1)", role: .destructive) {
                                onRemoveSet(set)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Exercise actions")
        }
    }
}
