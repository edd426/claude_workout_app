import SwiftUI

/// One row of an exercise card: [weight field] × [reps field] [checkmark].
///
/// Display is derived directly from the `WorkoutSet` model (SwiftData
/// `@Model` classes are Observation-tracked on iOS 17+), so external changes
/// — auto-fill, sync pull, Coach tool calls — refresh the row automatically.
/// There is deliberately NO local `@State` copy of weight/reps: the old copy
/// was seeded once in `init` and written back on complete, clobbering any
/// newer model values (#76). Edits commit through the `onEditWeight` /
/// `onEditReps` callbacks, which route to the ViewModel's mutation API.
struct SetRowView: View {
    let set: WorkoutSet
    let onComplete: (WorkoutSet) -> Void
    let onEditWeight: (WorkoutSet, Double) -> Void
    let onEditReps: (WorkoutSet, Int) -> Void

    @FocusState private var focusedField: FocusField?

    private enum FocusField {
        case weight, reps
    }

    /// Model-derived binding: reads the live model value, writes through the
    /// ViewModel API. `TextField(value:format:)` only calls the setter when
    /// the user commits (focus loss / Done), so typing isn't interrupted.
    private var weightBinding: Binding<Double> {
        Binding(
            get: { set.weight ?? 0 },
            set: { onEditWeight(set, $0) }
        )
    }

    private var repsBinding: Binding<Int> {
        Binding(
            get: { set.reps ?? 0 },
            set: { onEditReps(set, $0) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            setNumberLabel
            weightField
            Text("×").foregroundStyle(.secondary)
            repsField
            completeButton
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(set.isCompleted ? BrandTheme.terracotta.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    private var setNumberLabel: some View {
        Text("Set \(set.order + 1)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .leading)
    }

    private var weightField: some View {
        HStack(spacing: 4) {
            TextField("0", value: weightBinding, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 60)
                .focused($focusedField, equals: .weight)
                .accessibilityIdentifier("weight_\(set.order)")
            Text(set.weightUnit.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var repsField: some View {
        TextField("0", value: repsBinding, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .frame(width: 44)
            .focused($focusedField, equals: .reps)
            .accessibilityIdentifier("reps_\(set.order)")
    }

    private var completeButton: some View {
        Button {
            // Resigning focus commits any in-progress field edit through the
            // model-derived bindings (→ ViewModel API) before completion.
            focusedField = nil
            onComplete(set)
        } label: {
            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(set.isCompleted ? BrandTheme.terracotta : .secondary)
        }
        .frame(width: 44, height: 44)
        .buttonStyle(.plain)
        .accessibilityIdentifier("completeSet_\(set.order)")
    }
}
