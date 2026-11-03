import SwiftUI

struct WorkoutHistoryRowView: View {
    let workout: Workout

    /// Done exercises and completed sets only, not the plan (#176).
    private var summary: WorkoutHistorySummary { WorkoutHistorySummary(workout) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.name)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("\(workout.startedAt.formatted(date: .abbreviated, time: .omitted)) · \(summary.rowDetail)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 4)
        // One addressable element per logged workout. Combining also gives
        // VoiceOver the whole row as a single announcement instead of five
        // disconnected fragments.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("historyRow_\(workout.id)")
    }
}
