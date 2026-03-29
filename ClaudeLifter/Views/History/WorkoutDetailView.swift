import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout

    var body: some View {
        List {
            ForEach(workout.exercises.sorted(by: { $0.order < $1.order }), id: \.id) { we in
                Section(we.exercise?.name ?? "Unknown") {
                    ForEach(we.sets.sorted(by: { $0.order < $1.order }), id: \.id) { set in
                        WorkoutSetDetailRow(set: set)
                    }
                }
            }
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WorkoutSetDetailRow: View {
    let set: WorkoutSet

    var body: some View {
        HStack {
            Text("Set \(set.order + 1)")
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            if let weight = set.weight {
                Text(String(format: "%.1f %@", weight, set.weightUnit.rawValue))
                    .frame(width: 80)
            }
            if let reps = set.reps {
                Text("× \(reps) reps")
            }
            Spacer()
            if set.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.body)
    }
}
