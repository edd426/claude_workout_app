import SwiftUI

enum SetRowLayout {
    case compact
    case stacked
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
    let previous: AutoFillResult?
    let layout: SetRowLayout
    let focusedField: FocusState<SetEntryFieldID?>.Binding
    let onComplete: (WorkoutSet) -> Void
    let onEditWeight: (WorkoutSet, Double?) -> Void
    let onEditReps: (WorkoutSet, Int?) -> Void

    @Environment(\.locale) private var locale

    private var weightFieldID: SetEntryFieldID {
        SetEntryFieldID(
            exerciseID: workoutExerciseID,
            setID: set.id,
            kind: .weight
        )
    }

    private var repsFieldID: SetEntryFieldID {
        SetEntryFieldID(
            exerciseID: workoutExerciseID,
            setID: set.id,
            kind: .reps
        )
    }

    private var weightBinding: Binding<Double?> {
        Binding(
            get: { set.weight },
            set: { onEditWeight(set, $0) }
        )
    }

    private var repsBinding: Binding<Int?> {
        Binding(
            get: { set.reps },
            set: { onEditReps(set, $0) }
        )
    }

    private var weightFormat: FloatingPointFormatStyle<Double> {
        .number
            .locale(locale)
            .grouping(.never)
            .precision(.fractionLength(0...3))
    }

    private var repsFormat: IntegerFormatStyle<Int> {
        .number.locale(locale).grouping(.never)
    }

    var body: some View {
        Group {
            switch layout {
            case .compact:
                compactRow
            case .stacked:
                stackedRow
            }
        }
        .padding(.vertical, 4)
        .background(
            set.isCompleted
                ? BrandTheme.terracotta.opacity(0.1)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var compactRow: some View {
        GridRow(alignment: .center) {
            Text("\(set.order + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            previousLabel
                .gridColumnAlignment(.trailing)
            weightEntry
                .gridColumnAlignment(.trailing)
            repsEntry
                .gridColumnAlignment(.trailing)
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
            LabeledContent("Previous") {
                previousLabel
            }
            LabeledContent("Weight") {
                weightEntry
            }
            LabeledContent("Reps") {
                repsEntry
            }
        }
    }

    @ViewBuilder
    private var previousLabel: some View {
        if let previous {
            let weight = previous.weight.map {
                Text($0, format: weightFormat)
            } ?? Text("—")
            let reps = previous.reps.map {
                Text($0, format: repsFormat)
            } ?? Text("—")
            Text("\(weight) × \(reps)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
        }
    }

    private var weightEntry: some View {
        HStack(spacing: 4) {
            TextField(
                "Weight",
                value: weightBinding,
                format: weightFormat,
                prompt: previous?.weight.map {
                    Text($0, format: weightFormat)
                }
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 52, maxWidth: 72, minHeight: 44)
            .focused(focusedField, equals: weightFieldID)
            .accessibilityLabel("Weight for set \(set.order + 1)")
            .accessibilityIdentifier(
                "weight_\(workoutExerciseID.uuidString)_\(set.id.uuidString)"
            )
            Text(displayedWeightUnit.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var displayedWeightUnit: WeightUnit {
        if set.weight == nil, let previous {
            return previous.weightUnit
        }
        return set.weightUnit
    }

    private var repsEntry: some View {
        TextField(
            "Reps",
            value: repsBinding,
            format: repsFormat,
            prompt: previous?.reps.map {
                Text($0, format: repsFormat)
            }
        )
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 44, maxWidth: 56, minHeight: 44)
        .focused(focusedField, equals: repsFieldID)
        .accessibilityLabel("Reps for set \(set.order + 1)")
        .accessibilityIdentifier(
            "reps_\(workoutExerciseID.uuidString)_\(set.id.uuidString)"
        )
    }

    private var completeButton: some View {
        Button {
            onComplete(set)
        } label: {
            Image(
                systemName: set.isCompleted
                    ? "checkmark.circle.fill"
                    : "circle"
            )
            .font(.title2)
            .foregroundStyle(
                set.isCompleted ? BrandTheme.terracotta : .secondary
            )
        }
        .frame(width: 44, height: 44)
        .buttonStyle(.plain)
        .accessibilityLabel(
            set.isCompleted
                ? "Uncomplete set \(set.order + 1)"
                : "Complete set \(set.order + 1)"
        )
        .accessibilityIdentifier(
            "completeSet_\(workoutExerciseID.uuidString)_\(set.id.uuidString)"
        )
    }
}
