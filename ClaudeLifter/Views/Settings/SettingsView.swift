import SwiftUI

struct SettingsView: View {
    @State private var vm = SettingsViewModel(settingsManager: SettingsManager())

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case serverURL
        case apiKey
    }

    var body: some View {
        NavigationStack {
            Form {
                weightUnitSection
                aiModelSection
                insightsSection
                apiKeySection
                buildInfoSection
            }
            .navigationTitle("Settings")
            // Dismiss keyboard on scroll (interactive) or on tap anywhere
            // outside a field. Plenty discoverable — no separate Done button
            // needed.
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { focusedField = nil }
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

    private var insightsSection: some View {
        Section {
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
