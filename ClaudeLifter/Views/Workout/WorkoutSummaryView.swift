import SwiftUI

struct WorkoutSummaryView: View {
    let workout: Workout
    let onDismiss: () -> Void

    var totalSets: Int {
        workout.exercises.flatMap(\.sets).filter(\.isCompleted).count
    }

    var totalVolume: Double {
        workout.exercises.flatMap(\.sets)
            .filter(\.isCompleted)
            .compactMap { set -> Double? in
                guard let w = set.weight, let r = set.reps else { return nil }
                return w * Double(r)
            }
            .reduce(0, +)
    }

    var duration: String {
        guard let completed = workout.completedAt else { return "—" }
        let interval = completed.timeIntervalSince(workout.startedAt)
        let minutes = Int(interval) / 60
        return "\(minutes) min"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("Workout Complete!")
                    .font(.title.bold())

                statsGrid

                Spacer()

                Button("Done") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom)
            }
            .padding()
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 20) {
            StatTileView(label: "Duration", value: duration)
            StatTileView(label: "Sets", value: "\(totalSets)")
            StatTileView(label: "Volume", value: String(format: "%.0f kg", totalVolume))
        }
    }
}

private struct StatTileView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
}
