import SwiftUI

/// Home-screen quick-log card for body weight (issue #80). Two taps in the
/// happy path: "Log" opens the sheet pre-filled with the last weight, "Save"
/// commits it.
struct BodyWeightCard: View {
    let vm: BodyWeightViewModel
    @State private var showEntrySheet = false

    var body: some View {
        HStack(alignment: .center) {
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
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    trendLine
                } else {
                    Text("No entries yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                showEntrySheet = true
            } label: {
                Label("Log", systemImage: "scalemass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
        .task {
            await vm.load()
            await vm.importFromHealthKit()
        }
        .sheet(isPresented: $showEntrySheet) {
            BodyWeightEntrySheet(vm: vm)
                .presentationDetents([.height(220)])
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
                        .font(.caption2)
                        .foregroundStyle(delta >= 0 ? Color.green : Color.orange)
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
                    Text(vm.displayUnit.rawValue)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = vm.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
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
                }
            }
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
