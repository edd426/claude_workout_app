import Charts
import SwiftUI

/// "This week" detail (#168): one bar per tracked muscle against the 4-set
/// minimum and the 6–10 target band, then the sets behind each bar.
struct WeeklyVolumeDetailView: View {
    let volume: WeeklyMuscleVolume

    /// Lowest first, the same order as the card. Built once, not in `body`
    /// (UI-E5).
    private let ordered: [WeeklyMuscleVolume.Muscle]

    init(volume: WeeklyMuscleVolume) {
        self.volume = volume
        let under = volume.underMinimum
        let underIds = Set(under.map(\.id))
        let rest = volume.muscles
            .filter { !underIds.contains($0.id) }
            .sorted { $0.sets < $1.sets }
        ordered = under + rest
    }

    var body: some View {
        List {
            Section {
                WeeklyVolumeChart(muscles: ordered, accessibilitySummary: volume.accessibilitySummary)
                    // At accessibility sizes the axis labels ran over the
                    // bars. Every number is repeated at full size in the
                    // sections below, so the chart's own text is capped
                    // (UI-A3).
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                legend
            } header: {
                Text(weekTitle)
            } footer: {
                Text("A set counts 1 for each muscle the exercise works most and ½ for each it works less. Only finished workouts count.")
            }
            ForEach(ordered) { muscle in
                MuscleContributionSection(muscle: muscle)
            }
        }
        .navigationTitle("This week")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var weekTitle: String {
        let start = volume.week.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let end = volume.week.end.addingTimeInterval(-1)
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(start) – \(end)"
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Dashed line: 4 sets, the weekly minimum")
            } icon: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(.secondary)
            }
            Label {
                Text("Shaded band: 6–10 sets, the most efficient range")
            } icon: {
                // The band's own colour, a touch stronger so the swatch reads.
                Image(systemName: "rectangle.fill")
                    .foregroundStyle(BrandTheme.success.opacity(0.45))
            }
            Label {
                Text("Under 4 sets")
            } icon: {
                Image(systemName: "rectangle.fill")
                    .foregroundStyle(BrandTheme.warning)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// Horizontal bars, lowest muscle at the top.
private struct WeeklyVolumeChart: View {
    let muscles: [WeeklyMuscleVolume.Muscle]
    /// The chart in a few sentences for VoiceOver (UI-A4).
    let accessibilitySummary: String

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 28

    private var axisMax: Double {
        max(12, (muscles.map(\.sets).max() ?? 0) + 1)
    }

    var body: some View {
        Chart {
            RectangleMark(
                xStart: .value("Target low", MuscleVolumeTargets.targetBand.lowerBound),
                xEnd: .value("Target high", MuscleVolumeTargets.targetBand.upperBound)
            )
            .foregroundStyle(BrandTheme.success.opacity(0.15))
            RuleMark(x: .value("Minimum", MuscleVolumeTargets.minimumSets))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(Color.secondary)
            ForEach(muscles) { muscle in
                BarMark(
                    x: .value("Sets", muscle.sets),
                    y: .value("Muscle", muscle.muscle.displayName)
                )
                .foregroundStyle(muscle.isUnderMinimum ? BrandTheme.warning : BrandTheme.accent)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(WeeklyMuscleVolume.format(muscle.sets))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(muscle.muscle.displayName)
                .accessibilityValue("\(WeeklyMuscleVolume.format(muscle.sets)) sets")
            }
        }
        .chartXScale(domain: 0...axisMax)
        .chartXAxis {
            AxisMarks(values: [0, 4, 6, 10]) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: rowHeight * CGFloat(muscles.count) + 32)
        .accessibilityLabel("Sets per muscle this week")
        .accessibilityValue(accessibilitySummary)
    }
}

/// The sets behind one bar.
private struct MuscleContributionSection: View {
    let muscle: WeeklyMuscleVolume.Muscle

    var body: some View {
        Section {
            if muscle.contributions.isEmpty {
                Text("No sets yet this week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(muscle.contributions) { contribution in
                    ContributionRow(contribution: contribution)
                }
            }
        } header: {
            HStack {
                Text(muscle.muscle.displayName)
                Spacer()
                Text("\(WeeklyMuscleVolume.format(muscle.sets)) sets")
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct ContributionRow: View {
    let contribution: WeeklyMuscleVolume.Contribution

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(contribution.exerciseName)
                    .font(.body)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("+\(WeeklyMuscleVolume.format(contribution.sets))")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let day = contribution.date.formatted(.dateTime.weekday(.abbreviated).day())
        let sets = contribution.completedSets == 1 ? "1 set" : "\(contribution.completedSets) sets"
        let role = contribution.role == .primary ? "main muscle" : "secondary, counts ½"
        return "\(day) · \(contribution.workoutName) · \(sets), \(role)"
    }
}
