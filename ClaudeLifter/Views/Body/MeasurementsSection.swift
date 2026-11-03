import Charts
import SwiftUI

/// Card 3 (#165): the latest waist, waist-to-height against NICE NG246's
/// 0.5 line, a monthly sparkline, Log waist, and the one-time height.
struct MeasurementsSection: View {
    let vm: MeasurementsViewModel
    @State private var showWaistSheet = false
    @State private var showHeightSheet = false

    var body: some View {
        BodyCard(title: "Measurements", systemImage: "ruler") {
            Button {
                showWaistSheet = true
            } label: {
                Label("Log waist", systemImage: "plus")
                    .frame(minHeight: 44)
            }
            .secondaryActionStyle()
            .accessibilityIdentifier("bodyLogWaist")
        } content: {
            content
        }
        .sheet(isPresented: $showWaistSheet) {
            WaistEntrySheet(vm: vm)
                .quickEntryDetents(height: 280)
        }
        .sheet(isPresented: $showHeightSheet) {
            HeightEntrySheet(vm: vm)
                .quickEntryDetents(height: 300)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = vm.loadError {
            BodyErrorBanner(message: error) { Task { await vm.load() } }
        } else if !vm.isLoaded {
            BodyLoadingRow(label: "Loading measurements…")
        } else {
            WaistSummary(vm: vm)
            WaistToHeightRow(vm: vm) { showHeightSheet = true }
            WaistSparkline(vm: vm)
            Divider()
            Button {
                showHeightSheet = true
            } label: {
                BodyDisclosureLabel(title: "Height", value: vm.heightText ?? "Add")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bodyHeightRow")
        }
    }
}

private struct WaistSummary: View {
    let vm: MeasurementsViewModel

    var body: some View {
        if let waist = vm.latestWaistText {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(waist)
                        .font(.title3.bold())
                        .monospacedDigit()
                    Text("waist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let age = vm.latestWaistAge {
                    Text("Measured \(age)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("bodyWaistLatest")
        } else {
            Text("No waist measurement yet. Once a month is plenty.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// "WHtR 0.51 · aim below 0.5", or the step that is missing.
private struct WaistToHeightRow: View {
    let vm: MeasurementsViewModel
    let onAddHeight: () -> Void

    var body: some View {
        switch vm.waistToHeight {
        case .needsHeight:
            VStack(alignment: .leading, spacing: 8) {
                Text("Waist-to-height needs your height.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Add your height", action: onAddHeight)
                    .secondaryActionStyle()
                    .accessibilityIdentifier("bodyAddHeight")
            }
        case .needsWaist:
            Text("Log your waist to see your waist-to-height ratio.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .ratio(_, let band):
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.waistToHeight.text)
                    .font(.headline)
                    .monospacedDigit()
                if let bandText = vm.waistToHeight.bandText {
                    Label(bandText, systemImage: band == .healthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(band == .healthy ? BrandTheme.success : BrandTheme.warning)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("bodyWaistToHeight")
        }
    }
}

/// Monthly waist means, with the 0.5 × height line as the reference.
private struct WaistSparkline: View {
    let vm: MeasurementsViewModel
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 80

    var body: some View {
        let points = vm.waistSparkline
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 4) {
                Chart {
                    if let reference = vm.heightCm.map({ $0 * BodyMetrics.increasedRiskThreshold }) {
                        RuleMark(y: .value("0.5 of height", reference))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(BrandTheme.secondaryText)
                    }
                    ForEach(points) { point in
                        LineMark(x: .value("Month", point.date), y: .value("Waist", point.valueCm))
                            .foregroundStyle(BrandTheme.accent)
                        PointMark(x: .value("Month", point.date), y: .value("Waist", point.valueCm))
                            .symbolSize(20)
                            .foregroundStyle(BrandTheme.accent)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .frame(height: height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Waist trend")
                .accessibilityValue(vm.sparklineSummary)
                if let reference = vm.heightCm.map({ $0 * BodyMetrics.increasedRiskThreshold }) {
                    Text("Monthly averages. The dashed line is half your height, \(BodyFormat.number(reference, maxFractionDigits: 1)) cm.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Monthly averages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Sheets

/// Log waist: a fitted sheet in cm, prefilled from the last entry (UI-P4).
struct WaistEntrySheet: View {
    let vm: MeasurementsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSaving = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Waist", text: $text)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .font(.title3)
                            .monospacedDigit()
                            .accessibilityIdentifier("waistField")
                        Text("cm")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Measure at the navel, relaxed, after breathing out. Mornings are the most consistent.")
                }
                if let error = vm.entryError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(BrandTheme.destructive)
                }
            }
            .navigationTitle("Log Waist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(MeasurementsViewModel.parseWaist(text) == nil || isSaving)
                        .accessibilityIdentifier("saveWaist")
                }
            }
            .keyboardDoneButton(identifier: "waistKeyboardDone") { focused = false }
            .task {
                vm.clearEntryError()
                text = vm.waistPrefill
                focused = true
            }
        }
    }

    private func save() {
        guard let cm = MeasurementsViewModel.parseWaist(text) else { return }
        isSaving = true
        Task {
            // A failure leaves the sheet open with `entryError` shown (UI-E2).
            if await vm.logWaist(cm: cm) { dismiss() }
            isSaving = false
        }
    }
}

/// Height, set once: ft + in or cm, stored in cm (#165).
struct HeightEntrySheet: View {
    let vm: MeasurementsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var style: HeightStyle
    @State private var first: String
    @State private var second: String
    @FocusState private var focus: Field?

    private enum Field { case first, second }

    /// Prefilled here, not in `.task`, so the style's `onChange` never sees
    /// the prefill as a unit switch.
    init(vm: MeasurementsViewModel) {
        self.vm = vm
        let style = vm.heightStyle
        let fields = vm.heightCm.map { HeightEntry.fields(cm: $0, style: style) } ?? (first: "", second: "")
        _style = State(initialValue: style)
        _first = State(initialValue: fields.first)
        _second = State(initialValue: fields.second)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Units", selection: $style) {
                        ForEach(HeightStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("heightStylePicker")
                    fields
                } footer: {
                    Text("Used for your waist-to-height ratio. Saved in centimetres; shown the way you enter it.")
                }
            }
            .navigationTitle("Height")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(enteredCm == nil)
                        .accessibilityIdentifier("saveHeight")
                }
            }
            .keyboardDoneButton(identifier: "heightKeyboardDone") { focus = nil }
            .onChange(of: style) { oldStyle, newStyle in convert(from: oldStyle, to: newStyle) }
            .task { focus = .first }
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch style {
        case .feetInches:
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                unitField("Feet", text: $first, unit: "ft", field: .first, keyboard: .numberPad)
                unitField("Inches", text: $second, unit: "in", field: .second, keyboard: .decimalPad)
            }
        case .centimetres:
            unitField("Height", text: $first, unit: "cm", field: .first, keyboard: .decimalPad)
        }
    }

    private func unitField(
        _ title: String, text: Binding<String>, unit: String, field: Field, keyboard: UIKeyboardType
    ) -> some View {
        HStack(spacing: 4) {
            TextField(title, text: text)
                .keyboardType(keyboard)
                .focused($focus, equals: field)
                .font(.title3)
                .monospacedDigit()
                .accessibilityLabel(title)
                .accessibilityIdentifier("height\(title)Field")
            Text(unit)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var enteredCm: Double? {
        switch style {
        case .feetInches: return HeightEntry.cm(feetText: first, inchesText: second)
        case .centimetres: return HeightEntry.cm(centimetresText: first)
        }
    }

    /// Switching units keeps what was typed, converted.
    private func convert(from oldStyle: HeightStyle, to newStyle: HeightStyle) {
        let cm: Double? = switch oldStyle {
        case .feetInches: HeightEntry.cm(feetText: first, inchesText: second)
        case .centimetres: HeightEntry.cm(centimetresText: first)
        }
        if let cm {
            (first, second) = HeightEntry.fields(cm: cm, style: newStyle)
        } else {
            first = ""
            second = ""
        }
    }

    private func save() {
        let saved = switch style {
        case .feetInches: vm.setHeight(feetText: first, inchesText: second)
        case .centimetres: vm.setHeight(centimetresText: first)
        }
        if saved { dismiss() }
    }
}
