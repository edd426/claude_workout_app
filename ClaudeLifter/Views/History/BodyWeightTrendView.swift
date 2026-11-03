import Charts
import SwiftUI

/// The body-weight screen (issues #152, #111): weight over time with its
/// 7-day average, the 28-day rate against an optional goal, and the protein
/// target. Reached from the Home body-weight card and from Progress.
struct BodyWeightTrendView: View {
    @State var vm: BodyWeightTrendViewModel
    @State private var showGoalEditor = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let errorMessage = vm.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                WeightChartCard(vm: vm)
                WeightRateCard(vm: vm) { showGoalEditor = true }
                ProteinTargetCard(vm: vm)
            }
            .padding()
        }
        .navigationTitle("Body Weight")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .sheet(isPresented: $showGoalEditor) {
            WeightGoalEditorView(vm: vm)
                .presentationDetents([.medium, .large])
        }
    }
}

/// Shared card chrome, matching ChartsView.
private struct TrendCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

enum WeightFormat {
    static func signed(_ value: Double, digits: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).sign(strategy: .always()))
    }

    static func plain(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
}

// MARK: - Chart

private struct WeightChartCard: View {
    @Bindable var vm: BodyWeightTrendViewModel

    var body: some View {
        TrendCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Weight").font(.headline)
                Spacer()
                if let average = vm.currentAverage {
                    Text("7-day avg \(WeightFormat.plain(average)) \(vm.displayUnit.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Picker("Range", selection: $vm.selectedRange) {
                ForEach(WeightChartRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            chart
        }
    }

    @ViewBuilder
    private var chart: some View {
        if vm.chartPoints.isEmpty {
            Text(vm.isLoaded ? "No weigh-ins in this range" : "Loading…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            Chart {
                ForEach(vm.chartPoints) { point in
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .symbolSize(16)
                    .foregroundStyle(BrandTheme.terracotta.opacity(0.4))
                }
                ForEach(vm.averageLine) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("7-day average", point.value),
                        series: .value("Series", "7-day average")
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .foregroundStyle(BrandTheme.terracotta)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 240)
            .accessibilityLabel("Body weight chart, \(vm.selectedRange.rawValue)")
        }
    }
}

// MARK: - Rate and goal

private struct WeightRateCard: View {
    let vm: BodyWeightTrendViewModel
    let onEditGoal: () -> Void

    var body: some View {
        TrendCard {
            HStack {
                Text("Rate · last 28 days").font(.headline)
                Spacer()
                Button(vm.goalPercentPerWeek == nil ? "Set goal" : "Edit goal", action: onEditGoal)
                    .font(.subheadline)
                    .accessibilityIdentifier("editWeightGoal")
            }
            rateLine
            if let goal = vm.goalPercentPerWeek {
                Divider()
                goalLine(goal)
            }
        }
    }

    @ViewBuilder
    private var rateLine: some View {
        if let rate = vm.rate, let perWeek = vm.displayRatePerWeek {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(WeightFormat.signed(perWeek)) \(vm.displayUnit.rawValue)/wk")
                    .font(.title3.bold())
                Text("\(WeightFormat.signed(rate.percentPerWeek)) %/wk")
                    .foregroundStyle(.secondary)
            }
            Text("Trend of daily averages across \(rate.daysWithData) days with a weigh-in")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Not enough data: needs weigh-ins on at least 2 days in the last 28.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func goalLine(_ goal: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Goal \(WeightFormat.signed(goal)) %/wk")
            if let perWeek = vm.displayGoalPerWeek {
                Text("≈ \(WeightFormat.signed(perWeek)) \(vm.displayUnit.rawValue)/wk")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        if let status = vm.goalStatus, let deviation = vm.goalDeviation {
            GoalStatusLabel(status: status, deviation: deviation, goal: goal)
        }
    }
}

private struct GoalStatusLabel: View {
    let status: WeightGoalStatus
    let deviation: Double
    let goal: Double

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: status == .onTrack ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(status == .onTrack ? BrandTheme.green : .orange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weightGoalStatus")
    }

    private var title: String {
        switch status {
        case .onTrack: "On track"
        case .tooFast: "Too fast"
        case .tooSlow: "Too slow"
        }
    }

    private var detail: String {
        let off = WeightFormat.plain(abs(deviation), digits: 2)
        switch status {
        case .onTrack: return "Within 0.1 %/wk of the goal (\(off) off)"
        case .tooFast where goal == 0: return "\(off) %/wk of change; the goal is to hold steady"
        case .tooFast: return "\(off) %/wk faster than the goal"
        case .tooSlow: return "\(off) %/wk slower than the goal"
        }
    }
}

// MARK: - Protein (#111)

private struct ProteinTargetCard: View {
    @Bindable var vm: BodyWeightTrendViewModel

    var body: some View {
        TrendCard {
            Text("Protein target").font(.headline)
            if let target = vm.proteinTarget {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(target.grams) g").font(.title3.bold())
                    Text("per day").foregroundStyle(.secondary)
                    if target.isStale {
                        Text("Stale")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
                Text(basisText(target))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Log your weight to get a target.")
                    .foregroundStyle(.secondary)
            }
            Stepper(
                value: $vm.proteinMultiplier,
                in: BodyWeightTrendViewModel.proteinMultiplierRange,
                step: 0.1
            ) {
                Text("\(WeightFormat.plain(vm.proteinMultiplier)) g per kg body weight")
            }
            .accessibilityIdentifier("proteinMultiplierStepper")
            Text("Muscle gains plateau around 1.6 g/kg; higher is a buffer, not a requirement.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func basisText(_ target: ProteinTarget) -> String {
        let weight = "\(WeightFormat.plain(target.basisKilograms)) kg"
        let basis = target.basis == .sevenDayAverage ? "7-day average" : "latest weigh-in"
        let formula = "\(WeightFormat.plain(target.multiplier)) g/kg × \(weight) (\(basis))"
        guard target.isStale else { return formula }
        let when = target.basisDate.formatted(date: .abbreviated, time: .omitted)
        return "\(formula). No weigh-in since \(when); log one to update it."
    }
}
