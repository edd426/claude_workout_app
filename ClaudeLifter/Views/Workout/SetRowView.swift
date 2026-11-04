import SwiftUI

enum SetRowLayout {
    case compact
    case stacked
}

/// Column widths shared by the set rows and their header, so the compact
/// layout lines up without a `Grid`. A `Grid` painted the completed tint per
/// cell (#175 item 1); an `HStack` row can carry one background.
struct SetRowColumns: DynamicProperty {
    @ScaledMetric(relativeTo: .subheadline) var set: CGFloat = 24
    @ScaledMetric(relativeTo: .title3) var weight: CGFloat = 88
    @ScaledMetric(relativeTo: .title3) var reps: CGFloat = 52
    /// UI-T2: the set checkmark is gym-critical, at least 56 × 56 pt.
    let check: CGFloat = 56
    let spacing: CGFloat = 8
}

/// One model-derived set-entry row.
///
/// Display is derived directly from the `WorkoutSet` model (SwiftData
/// `@Model` classes are Observation-tracked on iOS 17+), so external changes
/// — auto-fill, sync pull, Coach tool calls — refresh the row automatically.
/// There is deliberately NO local `@State` copy of weight/reps: the old copy
/// was seeded once in `init` and written back on complete, clobbering newer
/// model values (#76). Edits commit through the ViewModel mutation callbacks.
struct SetRowView: View {
    let workoutExerciseID: UUID
    let set: WorkoutSet
    /// PREVIOUS, already formatted by the ViewModel: "80 × 8", or with last
    /// session's drift spelled out, "12 × 12 → 8" (#144). Marked here and
    /// never on what is typed now: this is next to the field he is about to
    /// fill in, while the choice is still his to make.
    let previousText: String?
    var drifted: Bool = false
    let layout: SetRowLayout
    let columns: SetRowColumns
    let focusedField: FocusState<SetEntryFieldID?>.Binding
    let onComplete: (WorkoutSet) -> Void
    let onEditWeight: (WorkoutSet, Double?) -> Void
    let onEditReps: (WorkoutSet, Int?) -> Void

    @Environment(\.locale) private var locale

    private var weightFieldID: SetEntryFieldID {
        SetEntryFieldID(exerciseID: workoutExerciseID, setID: set.id, kind: .weight)
    }

    private var repsFieldID: SetEntryFieldID {
        SetEntryFieldID(exerciseID: workoutExerciseID, setID: set.id, kind: .reps)
    }

    private var weightBinding: Binding<Double?> {
        Binding(get: { set.weight }, set: { onEditWeight(set, $0) })
    }

    private var repsBinding: Binding<Int?> {
        Binding(get: { set.reps }, set: { onEditReps(set, $0) })
    }

    private var weightFormat: FloatingPointFormatStyle<Double> {
        .number.locale(locale).grouping(.never).precision(.fractionLength(0...3))
    }

    private var repsFormat: IntegerFormatStyle<Int> {
        .number.locale(locale).grouping(.never)
    }

    var body: some View {
        Group {
            switch layout {
            case .compact: compactRow
            case .stacked: stackedRow
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        // One background for the whole row, not per-cell patches (#175).
        .background(
            set.isCompleted ? BrandTheme.completed.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var compactRow: some View {
        HStack(spacing: columns.spacing) {
            Text("\(set.order + 1)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: columns.set, alignment: .leading)
                .accessibilityHidden(true)
            previousLabel
                .frame(maxWidth: .infinity, alignment: .trailing)
            weightEntry
                .frame(width: columns.weight, alignment: .trailing)
            repsEntry
                .frame(width: columns.reps)
            completeButton
        }
    }

    private var stackedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Set \(set.order + 1)")
                    .font(.headline)
                Spacer()
                completeButton
            }
            LabeledContent("Previous") { previousLabel }
            // No width cap at accessibility sizes: the weight is the most
            // important number on the screen and must never read "…" (§3.14).
            LabeledContent("Weight") { weightEntry }
            LabeledContent("Reps") { repsEntry }
        }
    }

    @ViewBuilder
    private var previousLabel: some View {
        if let previousText {
            Text(previousText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(drifted ? BrandTheme.warning : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(
                    drifted
                        ? "Previous \(previousText), off target"
                        : "Previous \(previousText)"
                )
        } else {
            Text("—")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("No previous session")
        }
    }

    private var weightEntry: some View {
        HStack(spacing: 4) {
            // No ghost text inside the field (#174): an empty weight means
            // bodyweight, so that is exactly what the field says.
            TextField("Weight", value: weightBinding, format: weightFormat, prompt: Text("BW"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .font(.title3.monospacedDigit())
                .frame(minWidth: 52, maxWidth: layout == .stacked ? .infinity : nil, minHeight: 44)
                .focused(focusedField, equals: weightFieldID)
                // "Bodyweight" goes in the label, not the value: overriding the
                // value hid the typed number from VoiceOver and UI tests.
                .accessibilityLabel(
                    set.weight == nil
                        ? "Weight for set \(set.order + 1), bodyweight"
                        : "Weight for set \(set.order + 1)"
                )
                .accessibilityIdentifier("weight_\(workoutExerciseID.uuidString)_\(set.id.uuidString)")
                .modifier(FocusWithCaretAtEnd(isFocused: focusedField.wrappedValue == weightFieldID) {
                    focusedField.wrappedValue = weightFieldID
                })
            Text(set.weightUnit.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var repsEntry: some View {
        TextField("Reps", value: repsBinding, format: repsFormat, prompt: Text("–"))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .font(.title3.monospacedDigit())
            .frame(minWidth: 44, maxWidth: layout == .stacked ? .infinity : nil, minHeight: 44)
            .focused(focusedField, equals: repsFieldID)
            .accessibilityLabel("Reps for set \(set.order + 1)")
            .accessibilityIdentifier("reps_\(workoutExerciseID.uuidString)_\(set.id.uuidString)")
            .modifier(FocusWithCaretAtEnd(isFocused: focusedField.wrappedValue == repsFieldID) {
                focusedField.wrappedValue = repsFieldID
            })
    }

    private var completeButton: some View {
        Button {
            onComplete(set)
        } label: {
            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title)
                .foregroundStyle(set.isCompleted ? BrandTheme.completed : .secondary)
                .frame(minWidth: columns.check, minHeight: columns.check)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // UI-H2: medium on complete, light on un-complete, from the view
        // (UI-H1), not a feedback generator in the ViewModel.
        .sensoryFeedback(trigger: set.isCompleted) { _, completed in
            completed ? .impact(weight: .medium) : .impact(weight: .light)
        }
        .accessibilityLabel(set.isCompleted ? "Uncomplete set \(set.order + 1)" : "Complete set \(set.order + 1)")
        .accessibilityValue(set.isCompleted ? "completed" : "not completed")
        .accessibilityIdentifier("completeSet_\(workoutExerciseID.uuidString)_\(set.id.uuidString)")
    }
}

/// The SET / PREVIOUS / WEIGHT / REPS header over the compact rows, on the
/// same columns.
struct SetRowHeader: View {
    let columns: SetRowColumns

    var body: some View {
        HStack(spacing: columns.spacing) {
            header("SET").frame(width: columns.set, alignment: .leading)
            header("PREVIOUS").frame(maxWidth: .infinity, alignment: .trailing)
            header("WEIGHT").frame(width: columns.weight, alignment: .center)
            header("REPS").frame(width: columns.reps)
            Color.clear.frame(width: columns.check, height: 1)
        }
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// The first tap on a set field leaves the caret at the END, so one backspace
/// corrects the last digit without a second tap to reposition it (report
/// 8FF8C6D5, Seated Calf Raise, 2026-09-14).
///
/// The tap is intercepted rather than corrected afterwards because correcting
/// afterwards is what the screen already did: it selected all one main-actor
/// hop after `textDidBeginEditing`. The report shows that never took effect on
/// device — with the text selected, typing would have replaced the value and
/// no second tap would be needed — so the tap's own caret placement lands
/// after that hop, wherever the finger was (usually the start of a centred
/// number). Any hop-based fix races the same placement. Focusing
/// programmatically involves no touch to place a caret, so UIKit leaves it at
/// the end.
///
/// Only the unfocused field is intercepted. Once focused, touches reach the
/// field again, so the caret can still be dragged and the text long-pressed.
/// The overlay is `.accessibilityHidden`: VoiceOver activates the labelled
/// field underneath (the UI-T4 exception for focus helpers).
private struct FocusWithCaretAtEnd: ViewModifier {
    let isFocused: Bool
    let focus: () -> Void

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(isFocused)
            .overlay {
                if !isFocused {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: focus)
                        .accessibilityHidden(true)
                }
            }
    }
}
