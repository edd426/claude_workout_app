import SwiftUI

/// Sets the optional weight-change goal (#152) as a direction plus a %/week
/// magnitude, so a loss goal never needs a typed minus sign.
struct WeightGoalEditorView: View {
    let vm: BodyWeightTrendViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var direction: WeightGoalDirection
    @State private var magnitude: Double

    init(vm: BodyWeightTrendViewModel) {
        self.vm = vm
        let goal = vm.goalPercentPerWeek
        _direction = State(initialValue: WeightGoalDirection(goal: goal))
        let current = abs(goal ?? 0)
        _magnitude = State(initialValue: current > 0 ? current : 0.25)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Goal", selection: $direction) {
                        ForEach(WeightGoalDirection.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Within ±0.1 %/week of the goal counts as on track. The rate is the trend of the last 28 days.")
                }
                if direction == .lose || direction == .gain {
                    magnitudeSection
                }
            }
            .navigationTitle("Weight Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
    }

    private var magnitudeSection: some View {
        Section {
            Stepper(value: $magnitude, in: 0.05...BodyWeightTrendViewModel.maxGoalMagnitude, step: 0.05) {
                Text("\(WeightFormat.plain(magnitude, digits: 2)) % per week")
            }
            .accessibilityIdentifier("weightGoalMagnitude")
        } footer: {
            if let average = vm.currentAverage {
                let perWeek = average * magnitude / 100
                Text("About \(WeightFormat.plain(perWeek, digits: 2)) \(vm.displayUnit.rawValue) a week at your current 7-day average.")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                vm.goalPercentPerWeek = direction.goal(magnitude: magnitude)
                dismiss()
            }
        }
    }
}

extension WeightGoalDirection {
    var label: String {
        switch self {
        case .none: "None"
        case .lose: "Lose"
        case .maintain: "Maintain"
        case .gain: "Gain"
        }
    }
}
