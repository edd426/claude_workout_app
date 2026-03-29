import SwiftUI

struct SetRowView: View {
    let set: WorkoutSet
    let onComplete: (WorkoutSet) -> Void

    @State private var weight: Double
    @State private var reps: Int

    init(set: WorkoutSet, onComplete: @escaping (WorkoutSet) -> Void) {
        self.set = set
        self.onComplete = onComplete
        _weight = State(initialValue: set.weight ?? 0)
        _reps = State(initialValue: set.reps ?? 0)
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
        .background(set.isCompleted ? Color.green.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }

    private var setNumberLabel: some View {
        Text("Set \(set.order + 1)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .leading)
    }

    private var weightField: some View {
        HStack(spacing: 4) {
            TextField("0", value: $weight, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 60)
                .onChange(of: weight) { _, v in set.weight = v }
            Text(set.weightUnit.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var repsField: some View {
        TextField("0", value: $reps, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .frame(width: 44)
            .onChange(of: reps) { _, v in set.reps = v }
    }

    private var completeButton: some View {
        Button {
            set.weight = weight
            set.reps = reps
            onComplete(set)
        } label: {
            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(set.isCompleted ? .green : .secondary)
        }
        .frame(width: 44, height: 44)
        .buttonStyle(.plain)
    }
}
