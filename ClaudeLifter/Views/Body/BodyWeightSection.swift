import Charts
import SwiftUI

/// Card 1 (#152): the 90-day chart with its 7-day average and goal band, the
/// rate against the goal, the last weigh-in's age and the Log button.
struct BodyWeightSection: View {
    let models: BodyModels
    @State private var showLog = false

    private var trend: BodyWeightTrendViewModel { models.weightTrend }

    var body: some View {
        BodyCard(title: "Weight", systemImage: "scalemass") {
            Button {
                showLog = true
            } label: {
                Label("Log", systemImage: "plus")
                    .frame(minHeight: 44)
            }
            // The screen's one prominent action (UI-P1): weight is daily.
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Log weight")
            .accessibilityIdentifier("bodyLogWeight")
        } content: {
            content
        }
        .sheet(isPresented: $showLog, onDismiss: {
            Task { await trend.load() }
        }) {
            BodyWeightEntrySheet(vm: models.weightLog)
                .quickEntryDetents(height: 240)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = trend.errorMessage {
            BodyErrorBanner(message: error) { Task { await trend.load() } }
        } else if !trend.isLoaded {
            BodyLoadingRow(label: "Loading weight…")
        } else if trend.currentAverage == nil {
            Text("No weigh-ins yet. Log one here, or let Apple Health send them from a scale.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            WeightHeadline(trend: trend)
            WeightNinetyDayChart(trend: trend)
            WeightRateLine(trend: trend)
            Divider()
            NavigationLink {
                BodyWeightTrendView(vm: models.trendScreenViewModel())
            } label: {
                BodyDisclosureLabel(title: "Trend, goal and protein")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bodyWeightTrendLink")
        }
    }
}

/// "87.9 kg · 7-day average" and the last weigh-in's age (UI-E4).
private struct WeightHeadline: View {
    let trend: BodyWeightTrendViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let average = trend.currentAverage {
                // One line when it fits; the caption drops below at large sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        value(average)
                        caption
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        value(average)
                        caption
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let age = trend.lastWeighInAge {
                Label("Last weigh-in \(age)", systemImage: trend.isWeighInStale ? "clock.badge.exclamationmark" : "clock")
                    .font(.subheadline)
                    .foregroundStyle(trend.isWeighInStale ? BrandTheme.warning : BrandTheme.secondaryText)
                    .accessibilityIdentifier("bodyWeightAge")
            }
        }
    }

    private func value(_ average: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(average, format: .number.precision(.fractionLength(1)))
                .font(.title2.bold())
                .monospacedDigit()
            Text(trend.displayUnit.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var caption: some View {
        Text("7-day average")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// Weigh-ins as dots, the 7-day average as a line, the goal pace as a band.
private struct WeightNinetyDayChart: View {
    let trend: BodyWeightTrendViewModel
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(trend.goalBand) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Goal pace low", point.lower),
                        yEnd: .value("Goal pace high", point.upper)
                    )
                    .foregroundStyle(BrandTheme.info.opacity(0.25))
                }
                ForEach(trend.chartPoints) { point in
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .symbolSize(14)
                    .foregroundStyle(BrandTheme.accent.opacity(0.45))
                }
                ForEach(trend.averageLine) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("7-day average", point.value),
                        series: .value("Series", "7-day average")
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .foregroundStyle(BrandTheme.accent)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weight, last 3 months")
            .accessibilityValue(trend.chartAccessibilitySummary)
            .accessibilityIdentifier("bodyWeightChart")
            Text(legend)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var legend: String {
        trend.goalBand.isEmpty
            ? "Dots are weigh-ins; the line is the 7-day average."
            : "Dots are weigh-ins; the line is the 7-day average; the band is your goal pace."
    }
}

/// "+0.18 kg/wk vs goal -0.25", with the on-track status as an icon and words.
private struct WeightRateLine: View {
    let trend: BodyWeightTrendViewModel

    var body: some View {
        if let summary = trend.rateSummary {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let status = trend.goalStatus {
                    Label(statusText(status), systemImage: status == .onTrack ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(status == .onTrack ? BrandTheme.success : BrandTheme.warning)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("bodyWeightRate")
        } else {
            Text("Not enough weigh-ins for a rate yet: it needs 2 days in the last 28.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func statusText(_ status: WeightGoalStatus) -> String {
        switch status {
        case .onTrack: return "On track (28-day trend)"
        case .tooFast: return "Faster than the goal (28-day trend)"
        case .tooSlow: return "Slower than the goal (28-day trend)"
        }
    }
}

/// Card 2 (#111): the daily protein target from the latest weight. There is
/// no intake log yet; per-day logging is #110.
struct BodyProteinSection: View {
    let models: BodyModels
    @Environment(\.calendar) private var calendar

    private var trend: BodyWeightTrendViewModel { models.weightTrend }

    var body: some View {
        BodyCard(title: "Protein", systemImage: "fork.knife") {
            NavigationLink {
                BodyWeightTrendView(vm: models.trendScreenViewModel())
            } label: {
                Text("Adjust")
                    .foregroundStyle(BrandTheme.accentText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Adjust the protein multiplier")
            .accessibilityIdentifier("bodyProteinAdjust")
        } content: {
            if let target = trend.proteinTarget {
                Text(target.summaryText)
                    .font(.body)
                    .monospacedDigit()
                    .accessibilityIdentifier("bodyProteinTarget")
                if let stale = target.staleText(now: .now, calendar: calendar) {
                    Label(stale, systemImage: "clock.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(BrandTheme.warning)
                }
            } else if !trend.isLoaded {
                BodyLoadingRow(label: "Loading…")
            } else {
                Text("Log your weight to get a daily protein target.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
