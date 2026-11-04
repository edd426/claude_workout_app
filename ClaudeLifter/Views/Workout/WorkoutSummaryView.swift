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

    @Environment(\.dependencies) private var deps
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Records since `PREra.start` with the lifetime best beside each (#173).
    /// Read after the sheet appears; until then, or if it can't be read, the
    /// plain `personalRecords` show instead.
    @State private var report: PRReport?

    private var unit: WeightUnit { deps?.settings.weightUnit ?? .kg }

    /// Cards on this sheet. In dark mode a sheet's own background is
    /// #1C1C1E, the same as `BrandTheme.cardBackground`, so those cards
    /// vanished; the system's secondary background is one step lighter on
    /// an elevated sheet (#2C2C2E) and a light gray in light mode.
    static let sheetCard = Color(uiColor: .secondarySystemBackground)

    private var stats: WorkoutHistorySummary { WorkoutHistorySummary(workout) }

    /// Completed sets only.
    var totalSets: Int { stats.completedSets }

    /// Kilograms, each set converted from its own unit.
    var totalVolume: Double { stats.volumeKg }

    private var hasRecords: Bool {
        !(report?.records.isEmpty ?? personalRecords.isEmpty)
    }

    var body: some View {
        // Do not wrap in NavigationStack — this view is presented inside a
        // sheet from ActiveWorkoutView, which is already inside HomeView's
        // NavigationStack. Nesting NavigationStacks inside a sheet caused
        // gesture-dismiss weirdness and occasional crashes on back taps.
        ScrollView {
            VStack(spacing: 24) {
                header
                autoFinishNotice
                statsGrid
                recordsSection
                if let templateChangeSet, let onApplyTemplateChanges {
                    TemplateReviewSection(
                        changeSet: templateChangeSet,
                        onApply: onApplyTemplateChanges
                    )
                }
                doneButton
            }
            .padding()
        }
        // Rerun when post-commit detection lands, so the report is read
        // after the records it describes are saved (#125).
        .task(id: personalRecords.count) { await loadReport() }
        .sensoryFeedback(.success, trigger: hasRecords) { _, now in now }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text(workout.name)
                .font(.title3.bold())
                .foregroundStyle(.secondary)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(BrandTheme.completed)
                .accessibilityHidden(true)
            Text("Workout Complete!")
                .font(.title.bold())
        }
    }

    private var doneButton: some View {
        Button {
            onDismiss()
        } label: {
            Text("Done").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.bottom)
        .accessibilityIdentifier("summaryDone")
    }

    /// A failed read keeps the plain records on screen: the workout is saved
    /// either way, and the records were already detected (UI-E2).
    private func loadReport() async {
        guard let service = deps?.prDetectionService else { return }
        if let loaded = try? await service.prReport(for: workout) {
            report = loaded
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
                Self.sheetCard,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("autoFinishedNotice")
        }
    }

    /// Three tiles in a row; stacked at accessibility sizes, where the row
    /// hyphenated the labels and truncated the volume (UI-A3).
    private var statsGrid: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            StatTileView(label: "Duration", value: stats.durationText)
            StatTileView(label: "Sets", value: "\(stats.completedSets)")
            StatTileView(label: "Volume", value: stats.volumeText(in: unit))
        }
    }

    @ViewBuilder
    private var recordsSection: some View {
        if let report {
            if !report.records.isEmpty {
                PRReportCard(records: report.records, unit: unit)
            }
            if !report.lifetimeReferences.isEmpty {
                LifetimeBestsCard(references: report.lifetimeReferences, unit: unit)
            }
        } else if !personalRecords.isEmpty {
            PRReportCard(records: fallbackRecords, unit: unit)
        }
    }

    /// The saved records as report records without a lifetime comparison,
    /// for a detector that can't build a report.
    private var fallbackRecords: [PRReport.Record] {
        personalRecords.map { record in
            let exercise = workout.exercises.first { $0.exercise?.id == record.exerciseId }?.exercise
            return PRReport.Record(
                exerciseId: record.exerciseId,
                exerciseName: exercise?.name ?? "Exercise",
                type: record.prType,
                value: record.value,
                set: PRSetRef(
                    weightKg: record.weight ?? record.value,
                    reps: record.reps ?? 1,
                    date: record.achievedAt
                ),
                lifetimeBest: nil
            )
        }
    }
}

private struct StatTileView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(WorkoutSummaryView.sheetCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Records since 2026, grouped by exercise, each with its lifetime best
/// beside it (#173).
private struct PRReportCard: View {
    let records: [PRReport.Record]
    let unit: WeightUnit

    private var exercises: [(id: UUID, name: String, records: [PRReport.Record])] {
        var order: [UUID] = []
        var grouped: [UUID: [PRReport.Record]] = [:]
        for record in records {
            if grouped[record.exerciseId] == nil { order.append(record.exerciseId) }
            grouped[record.exerciseId, default: []].append(record)
        }
        return order.map { id in
            (id, grouped[id]?.first?.exerciseName ?? "", grouped[id] ?? [])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Personal records \(PREra.label)", systemImage: "trophy.fill")
                .font(.headline)
                .foregroundStyle(BrandTheme.accentText)
            ForEach(exercises, id: \.id) { exercise in
                VStack(alignment: .leading, spacing: 8) {
                    Text(exercise.name)
                        .font(.headline)
                    ForEach(exercise.records) { record in
                        PRRecordRow(record: record, unit: unit)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkoutSummaryView.sheetCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("summaryPersonalRecords")
    }
}

private struct PRRecordRow: View {
    let record: PRReport.Record
    let unit: WeightUnit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(BrandTheme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(PRDisplay.title(for: record.type))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(PRDisplay.value(of: record, in: unit))
                    .font(.body.bold())
                    .monospacedDigit()
                Text(PRDisplay.comparison(for: record, in: unit, now: .now))
                    .font(.subheadline)
                    .foregroundStyle(record.isNewLifetimeBest ? BrandTheme.accentText : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Exercises done today without a record since 2026, with their best ever
/// set, for comparison only.
private struct LifetimeBestsCard: View {
    let references: [PRReport.LifetimeReference]
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lifetime bests")
                .font(.headline)
            ForEach(references) { reference in
                VStack(alignment: .leading, spacing: 2) {
                    Text(reference.exerciseName)
                        .font(.body)
                    Text(PRDisplay.lifetimeBest(reference.heaviest, in: unit, now: .now))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkoutSummaryView.sheetCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("summaryLifetimeBests")
    }
}
