import SwiftUI

struct WorkoutSummaryView: View {
    let workout: Workout
    let personalRecords: [PersonalRecord]
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
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(BrandTheme.terracotta)

                    Text("Workout Complete!")
                        .font(.title.bold())

                    statsGrid

                    if !personalRecords.isEmpty {
                        prSection
                    }

                    Button("Done") { onDismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.bottom)
                        .accessibilityIdentifier("summaryDone")
                }
                .padding()
            }
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

    private var prSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Personal Records", systemImage: "trophy.fill")
                .font(.headline)
                .foregroundStyle(BrandTheme.terracotta)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(personalRecords, id: \.id) { pr in
                PRCardView(record: pr)
            }
        }
        .padding()
        .background(BrandTheme.terracotta.opacity(0.1))
        .cornerRadius(12)
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

private struct PRCardView: View {
    let record: PersonalRecord

    private var typeLabel: String {
        switch record.prType {
        case .heaviestWeight: return "Heaviest Weight"
        case .mostRepsAtWeight: return "Most Reps at Weight"
        case .highest1RM: return "Estimated 1RM"
        }
    }

    private var valueLabel: String {
        switch record.prType {
        case .heaviestWeight: return String(format: "%.1f kg", record.value)
        case .mostRepsAtWeight:
            if let w = record.weight {
                return String(format: "%d reps @ %.1f kg", record.reps ?? Int(record.value), w)
            }
            return "\(record.reps ?? Int(record.value)) reps"
        case .highest1RM: return String(format: "%.1f kg", record.value)
        }
    }

    var body: some View {
        HStack {
            Image(systemName: "star.fill")
                .foregroundStyle(BrandTheme.terracotta)
            VStack(alignment: .leading, spacing: 2) {
                Text(typeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(valueLabel)
                    .font(.subheadline.bold())
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
