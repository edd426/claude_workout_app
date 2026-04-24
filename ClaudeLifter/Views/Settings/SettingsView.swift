import SwiftUI

struct SettingsView: View {
    @Environment(\.dependencies) private var deps
    // Build the VM on first appear so it binds to DependencyContainer's
    // SettingsManager (the same one ChatViewModel reads). Previously this
    // view created its own SettingsManager instance, so the two were
    // disconnected — flipping the model in Settings updated one instance
    // while Coach kept reading the other. The UserDefaults write made the
    // values eventually match on relaunch, but the live observation was
    // broken.
    @State private var vm: SettingsViewModel?

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case serverURL
        case apiKey
    }

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    Form {
                        weightUnitSection(vm: vm)
                        aiModelSection(vm: vm)
                        insightsSection(vm: vm)
                        apiKeySection(vm: vm)
                        buildInfoSection
                    }
                    // Dismiss keyboard on scroll (interactive) or on tap
                    // anywhere outside a field. Plenty discoverable — no
                    // separate Done button needed.
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture { focusedField = nil }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Settings")
        }
        .task {
            guard vm == nil, let deps else { return }
            vm = SettingsViewModel(settingsManager: deps.settings)
        }
    }

    private func weightUnitSection(vm: SettingsViewModel) -> some View {
        @Bindable var vm = vm
        return Section("Weight Unit") {
            Picker("Default Unit", selection: $vm.weightUnit) {
                ForEach(WeightUnit.allCases, id: \.self) { unit in
                    Text(unit.rawValue.uppercased()).tag(unit)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func aiModelSection(vm: SettingsViewModel) -> some View {
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

    @ViewBuilder
    private func apiKeySection(vm: SettingsViewModel) -> some View {
        @Bindable var vm = vm
        Section {
            HStack {
                TextField("https://your-server.azurewebsites.net", text: $vm.serverURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .focused($focusedField, equals: .serverURL)
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
                .focused($focusedField, equals: .apiKey)
        }
    }

    private func insightsSection(vm: SettingsViewModel) -> some View {
        @Bindable var vm = vm
        return Section {
            Toggle("Proactive insights on Home", isOn: $vm.proactiveInsightsEnabled)
        } header: {
            Text("Home Screen")
        } footer: {
            Text(vm.proactiveInsightsEnabled
                 ? "Shows Coach-generated suggestion cards on the home screen (\u{201C}You haven’t trained legs in 2 weeks”, etc.). Turn off if they pile up when you’re away from the app."
                 : "Home screen will not show insight cards. No new insights will be generated either.")
                .font(.caption)
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
