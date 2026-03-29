import SwiftUI

struct WorkoutHistoryRowView: View {
    let workout: Workout

    var exerciseCount: Int { workout.exercises.count }
    var completedSets: Int { workout.exercises.flatMap(\.sets).filter(\.isCompleted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.name)
                .font(.headline)
            HStack {
                Text(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(exerciseCount) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(completedSets) sets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
