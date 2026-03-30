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

    // @needs:ui-viewmodels — serverURL field added for Phase 2 proxy support
    @ViewBuilder
    private var apiKeySection: some View {
        Section {
            TextField("https://func-workout-prod.azurewebsites.net", text: $vm.serverURL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        } header: {
            Text("Server URL")
        } footer: {
            Text("When set, chat is routed through your Azure Function. Leave empty to use the API key below (Phase 1 mode).")
                .font(.caption)
        }

        Section("Server API Key") {
            SecureField("sk-ant-... or Azure function key", text: $vm.apiKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }
}
