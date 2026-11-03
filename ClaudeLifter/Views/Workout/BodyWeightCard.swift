import SwiftUI

/// Home-screen quick-log card for body weight (issue #80). Two taps in the
/// happy path: "Log" opens the sheet pre-filled with the last weight, "Save"
/// commits it. Tapping the rest of the card opens the weight screen (#152),
/// and the protein target (#111) sits under the trend.
struct BodyWeightCard: View {
    let vm: BodyWeightViewModel
    @Environment(\.dependencies) private var deps
    @State private var showEntrySheet = false

    var body: some View {
        HStack(alignment: .center) {
            trendLink
            Button {
                showEntrySheet = true
            } label: {
                Label("Log", systemImage: "scalemass")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(BrandTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 8)
        .task {
            await vm.load()
            await vm.importFromHealthKit()
        }
        .sheet(isPresented: $showEntrySheet) {
            BodyWeightEntrySheet(vm: vm)
                .quickEntryDetents(height: 240)
        }
    }

    /// Everything left of the Log button opens the weight screen (#152).
    @ViewBuilder
    private var trendLink: some View {
        if let deps {
            NavigationLink {
                BodyWeightTrendView(vm: BodyWeightTrendViewModel(
                    repository: deps.bodyWeightRepository,
                    settings: deps.settings
                ))
            } label: {
                HStack {
                    summary
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bodyWeightTrendLink")
        } else {
            summary
            Spacer()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Body Weight")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let weight = vm.latestDisplayWeight, let entry = vm.latest {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(weight, format: .number.precision(.fractionLength(1)))
                        .font(.title3.bold())
                    Text(vm.displayUnit.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.recordedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                trendLine
                proteinLine
            } else {
                Text("No entries yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var proteinLine: some View {
        if let target = vm.proteinTarget {
            Text("Protein \(target.grams) g/day\(target.isStale ? " · stale" : "")")
                .font(.caption)
                .foregroundStyle(target.isStale ? BrandTheme.warning : BrandTheme.secondaryText)
                .accessibilityIdentifier("proteinTargetLine")
        }
    }

    @ViewBuilder
    private var trendLine: some View {
        let deltas: [(String, Double?)] = [("7d", vm.delta(days: 7)), ("30d", vm.delta(days: 30))]
        let available = deltas.compactMap { label, value in value.map { (label, $0) } }
        if !available.isEmpty {
            HStack(spacing: 8) {
                ForEach(available, id: \.0) { label, delta in
                    Text("\(label) \(delta >= 0 ? "+" : "")\(delta, format: .number.precision(.fractionLength(1)))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(BrandTheme.secondaryText)
                }
            }
        }
    }
}

struct BodyWeightEntrySheet: View {
    let vm: BodyWeightViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("Weight", text: $weightText)
                        .keyboardType(.decimalPad)
                        .focused($fieldFocused)
                        .font(.title3)
                        .monospacedDigit()
                        .accessibilityIdentifier("bodyWeightField")
                    Text(vm.displayUnit.rawValue)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = vm.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(BrandTheme.destructive)
                }
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if let value = parsedWeight {
                                await vm.logWeight(value, unit: vm.displayUnit)
                                if vm.errorMessage == nil { dismiss() }
                            }
                        }
                    }
                    .disabled(parsedWeight == nil)
                    .accessibilityIdentifier("saveBodyWeight")
                }
            }
            .keyboardDoneButton(identifier: "bodyWeightKeyboardDone") { fieldFocused = false }
            .task {
                if let last = vm.latestDisplayWeight {
                    weightText = last.formatted(.number.precision(.fractionLength(1)))
                }
                fieldFocused = true
            }
        }
    }

    /// Accepts both "84.3" and "84,3" — the decimal pad follows the locale.
    private var parsedWeight: Double? {
        let normalized = weightText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0, value < 500 else { return nil }
        return value
    }
}
