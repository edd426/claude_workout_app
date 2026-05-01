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
                        if let deps {
                            syncStatusSection(syncManager: deps.syncManager)
                        }
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

    private func syncStatusSection(syncManager: SyncManager) -> some View {
        Section {
            SyncStateRow(state: syncManager.state)
        } header: {
            Text("Sync Status")
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

// MARK: - Sync state UI (also used by HomeView)

/// Full row for Settings showing the current SyncManager state. Reactive — reads
/// `state`'s underlying inputs through @Observable, so SwiftUI re-renders when
/// the user pastes the server URL, when sync starts, when it errors, etc.
struct SyncStateRow: View {
    let state: SyncState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch state {
        case .disabled: return "exclamationmark.triangle.fill"
        case .offline:  return "wifi.slash"
        case .syncing:  return "arrow.triangle.2.circlepath"
        case .error:    return "xmark.octagon.fill"
        case .synced:   return "checkmark.circle.fill"
        case .pending:  return "clock"
        }
    }

    private var iconColor: Color {
        switch state {
        case .disabled: return .orange
        case .offline:  return .secondary
        case .syncing:  return BrandTheme.info
        case .error:    return .red
        case .synced:   return BrandTheme.success
        case .pending:  return .secondary
        }
    }

    private var title: String {
        switch state {
        case .disabled: return "Sync disabled"
        case .offline:  return "Offline"
        case .syncing:  return "Syncing…"
        case .error:    return "Sync failed"
        case .synced:   return "Synced"
        case .pending:  return "Sync pending"
        }
    }

    private var detail: String {
        switch state {
        case .disabled:
            return "Set the Server URL above to enable cloud sync."
        case .offline:
            return "Will resume when network returns."
        case .syncing:
            return "Pulling and pushing changes…"
        case .error(let msg):
            return msg
        case .synced(let date):
            return "Last synced \(Self.relativeFormatter.localizedString(for: date, relativeTo: .now))"
        case .pending:
            return "Configured but no sync has run yet."
        }
    }

    /// Static formatter — RelativeDateTimeFormatter is expensive to construct.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

/// Compact banner for the Home tab. Renders only for actionable states the user
/// would otherwise miss — currently `.disabled`. Other states (offline, syncing,
/// synced) are visible in Settings; cluttering Home with them is noise.
struct SyncStateBanner: View {
    let state: SyncState

    var body: some View {
        if case .disabled = state {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cloud sync is off")
                        .font(.subheadline.weight(.medium))
                    Text("Workouts are saved on this device only. Open Settings to set the server URL.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(BrandTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.top, 8)
        } else {
            EmptyView()
        }
    }
}
