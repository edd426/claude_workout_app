import SwiftUI

struct ExerciseCardView: View {
    let workoutExercise: WorkoutExercise
    let onCompleteSet: (WorkoutSet) -> Void
    let onAddSet: () -> Void
    var onRemoveSet: ((WorkoutSet) -> Void)? = nil

    private var sortedSets: [WorkoutSet] {
        workoutExercise.sets.sorted(by: { $0.order < $1.order })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            exerciseHeader
            Divider()
            ForEach(sortedSets, id: \.id) { set in
                HStack {
                    SetRowView(set: set, onComplete: onCompleteSet)
                    if sortedSets.count > 1, let onRemoveSet {
                        Button {
                            onRemoveSet(set)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button("+ Add Set", action: onAddSet)
                .font(.caption)
                .foregroundStyle(.blue)
                .padding(.top, 4)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    private var exerciseHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workoutExercise.exercise?.name ?? "Unknown Exercise")
                .font(.headline)
            if let muscles = workoutExercise.exercise?.primaryMuscles, !muscles.isEmpty {
                Text(muscles.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
