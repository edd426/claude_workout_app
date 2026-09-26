import SwiftUI

struct WorkoutSummaryView: View {
    let workout: Workout
    let personalRecords: [PersonalRecord]
    let onDismiss: () -> Void
    /// Proposed template changes (#130). Nil when the workout was ad-hoc, or
    /// matched its plan, or detection has not finished yet — the card must
    /// never appear with nothing in it.
    var templateChangeSet: TemplateChangeSet? = nil
    /// Returns an error message to show, or nil on success.
    var onApplyTemplateChanges: (([TemplateChange]) async -> String?)? = nil
    /// The app finished this workout after it sat idle (report 07B1AD96).
    /// This sheet is then the only word the user gets about it, so it says so.
    var finishedAutomatically: Bool = false

    var totalSets: Int {
        workout.exercises.flatMap(\.sets).filter(\.isCompleted).count
    }

    var totalVolume: Double {
        workout.exercises.flatMap(\.sets)
            .filter(\.isCompleted)
            .compactMap { set -> Double? in
                guard let w = set.weightInKilograms, let r = set.reps else { return nil }
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
        // Do not wrap in NavigationStack — this view is presented inside a
        // sheet from ActiveWorkoutView, which is already inside HomeView's
        // NavigationStack. Nesting NavigationStacks inside a sheet caused
        // gesture-dismiss weirdness and occasional crashes on back taps.
        ScrollView {
            VStack(spacing: 24) {
                Text(workout.name)
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(BrandTheme.terracotta)

                Text("Workout Complete!")
                    .font(.title.bold())

                autoFinishNotice

                statsGrid

                if !personalRecords.isEmpty {
                    prSection
                }

                if let templateChangeSet, let onApplyTemplateChanges {
                    TemplateReviewSection(
                        changeSet: templateChangeSet,
                        onApply: onApplyTemplateChanges
                    )
                }

                Button("Done") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom)
                    .accessibilityIdentifier("summaryDone")
            }
            .padding()
        }
    }

    /// What happened and which window was recorded, so a Duration that is
    /// shorter than the time the workout was open is not a surprise.
    @ViewBuilder
    private var autoFinishNotice: some View {
        if finishedAutomatically, let completedAt = workout.completedAt {
            let hours = Int(WorkoutAutoFinishPolicy.idleThreshold / 3600)
            let from = workout.startedAt.formatted(date: .abbreviated, time: .shortened)
            let to = completedAt.formatted(date: .omitted, time: .shortened)
            Label {
                Text(
                    "Finished automatically after \(hours) hours without a logged set. "
                        + "Time is recorded from your first set to your last: \(from) – \(to)."
                )
                .multilineTextAlignment(.leading)
            } icon: {
                Image(systemName: "clock.badge.checkmark")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("autoFinishedNotice")
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
