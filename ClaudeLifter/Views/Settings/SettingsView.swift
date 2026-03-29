import SwiftUI

struct SettingsView: View {
    @State private var vm = SettingsViewModel(settingsManager: SettingsManager())

    var body: some View {
        NavigationStack {
            Form {
                weightUnitSection
                aiModelSection
                apiKeySection
            }
            .navigationTitle("Settings")
        }
    }

    private var weightUnitSection: some View {
        Section("Weight Unit") {
            Picker("Default Unit", selection: $vm.weightUnit) {
                ForEach(WeightUnit.allCases, id: \.self) { unit in
                    Text(unit.rawValue.uppercased()).tag(unit)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var aiModelSection: some View {
        Section("AI Model") {
            ForEach(vm.availableModels, id: \.self) { model in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName)
                        Text(model.costIndicator)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if vm.aiModel == model {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { vm.aiModel = model }
            }
        }
    }

    private var apiKeySection: some View {
        Section("Anthropic API Key") {
            SecureField("sk-ant-...", text: $vm.apiKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }
}
