import SwiftUI

struct SettingsView: View {
    @State private var vm = SettingsViewModel(settingsManager: SettingsManager())

    var body: some View {
        NavigationStack {
            Form {
                weightUnitSection
                aiModelSection
                apiKeySection
                buildInfoSection
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
            HStack {
                TextField("https://your-server.azurewebsites.net", text: $vm.serverURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                if !vm.serverURL.isEmpty {
                    Button {
                        vm.serverURL = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Server URL")
        } footer: {
            Text(vm.serverURL.isEmpty
                 ? "No server configured — using API key directly (Phase 1 mode)."
                 : "Chat and sync routed through \(vm.serverURL)")
                .font(.caption)
        }

        Section("Server API Key") {
            SecureField("sk-ant-... or Azure function key", text: $vm.apiKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

    private var buildInfoSection: some View {
        Section {
            Button {
                UIPasteboard.general.string = BuildInfo.summary
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(BuildInfo.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tap to copy")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("About")
        }
    }
}
