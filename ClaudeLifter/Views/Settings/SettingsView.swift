import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

    // Backup UI state.
    @State private var shareItem: ShareItem?
    @State private var isImporting = false
    @State private var alertMessage: String?
    // Cloud restore UI state (issue #78). Destructive, so gated behind an
    // explicit confirmation dialog.
    @State private var isConfirmingRestore = false
    @State private var isRestoring = false
    /// Path of a store that failed to open and was quarantined (issue #72),
    /// read once from UserDefaults so the user can find their recovered data.
    @State private var quarantinePath: String?

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
                            backupSection(deps: deps)
                        }
                        if let quarantinePath {
                            quarantineSection(path: quarantinePath)
                        }
                        buildInfoSection
                    }
                    // Dismiss keyboard on scroll (interactive) or on tap
                    // anywhere outside a field. Plenty discoverable — no
                    // separate Done button needed.
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture { focusedField = nil }
                    .sheet(item: $shareItem) { item in
                        ShareSheet(items: [item.url])
                    }
                    .fileImporter(
                        isPresented: $isImporting,
                        allowedContentTypes: [.json],
                        allowsMultipleSelection: false
                    ) { result in
                        handleImport(result: result)
                    }
                    .alert("Data", isPresented: alertPresented) {
                        Button("OK", role: .cancel) { alertMessage = nil }
                    } message: {
                        Text(alertMessage ?? "")
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Settings")
        }
        .task {
            quarantinePath = UserDefaults.standard.string(forKey: "lastStoreQuarantinePath")
            guard vm == nil, let deps else { return }
            vm = SettingsViewModel(settingsManager: deps.settings)
        }
    }

    // MARK: - Backup

    private func backupSection(deps: DependencyContainer) -> some View {
        Section {
            Button {
                Task { await exportBackup(deps: deps) }
            } label: {
                Label("Export Backup", systemImage: "square.and.arrow.up")
            }
            Button {
                isImporting = true
            } label: {
                Label("Import Backup", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Export writes a JSON file of all workouts, templates, custom exercises, and preferences that you can save off-device. Import merges a backup file, skipping anything already on this device.")
                .font(.caption)
        }
    }

    private func quarantineSection(path: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("A previous database failed to open and was recovered. Your old data was moved here (not deleted):")
                    .font(.caption)
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Dismiss") {
                    UserDefaults.standard.removeObject(forKey: "lastStoreQuarantinePath")
                    quarantinePath = nil
                }
                .font(.caption)
            }
        } header: {
            Text("Store Recovery")
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { presented in if !presented { alertMessage = nil } }
        )
    }

    private func exportBackup(deps: DependencyContainer) async {
        do {
            let url = try await deps.backupService.exportBackup()
            shareItem = ShareItem(url: url)
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        guard let deps else { return }
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    let summary = try await deps.backupService.importBackup(from: url)
                    alertMessage = Self.summaryMessage(summary)
                } catch {
                    alertMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        case .failure(let error):
            alertMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private static func summaryMessage(_ summary: BackupImportSummary) -> String {
        func line(_ label: String, _ result: BackupImportSummary.CollectionResult) -> String {
            "\(label): \(result.imported) imported, \(result.skipped) skipped"
        }
        return [
            line("Workouts", summary.workouts),
            line("Templates", summary.templates),
            line("Custom exercises", summary.customExercises),
            line("Preferences", summary.preferences)
        ].joined(separator: "\n")
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
            SyncStateRow(state: syncManager.state, revision: syncManager.lastRevision)
            Button(role: .destructive) {
                isConfirmingRestore = true
            } label: {
                Label("Restore from Cloud", systemImage: "icloud.and.arrow.down")
            }
            .disabled(isRestoring || syncManager.state == .disabled)
            .confirmationDialog(
                "Replace local data with the cloud snapshot?",
                isPresented: $isConfirmingRestore,
                titleVisibility: .visible
            ) {
                Button("Replace Local Data", role: .destructive) {
                    Task { await restoreFromCloud(syncManager: syncManager) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes all workouts, templates, custom exercises, and body-weight entries on this phone and replaces them with the last cloud snapshot. Chat history and training preferences are not affected. This cannot be undone.")
            }
        } header: {
            Text("Sync Status")
        } footer: {
            Text("Sync mirrors this phone's data to the cloud — the phone is the source of truth. Restore is for disaster recovery on a fresh install.")
                .font(.caption)
        }
    }

    private func restoreFromCloud(syncManager: SyncManager) async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            let summary = try await syncManager.restoreFromSnapshot()
            var lines = [
                "Restored from cloud snapshot #\(summary.revision):",
                "Workouts: \(summary.workouts)",
                "Templates: \(summary.templates)",
                "Custom exercises: \(summary.customExercises)",
                "Body-weight entries: \(summary.bodyWeightEntries)"
            ]
            if summary.placeholderExercises > 0 {
                lines.append("Placeholders created for \(summary.placeholderExercises) unknown exercise(s)")
            }
            alertMessage = lines.joined(separator: "\n")
        } catch {
            alertMessage = "Restore failed: \(error.localizedDescription)"
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

// MARK: - Backup share sheet helpers

/// Identifiable wrapper so a freshly-exported file URL can drive `.sheet(item:)`.
private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Bridges `UIActivityViewController` so the exported backup file can be shared
/// (AirDrop, Files, Mail, etc.) from SwiftUI.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Sync state UI (also used by HomeView)

/// Full row for Settings showing the current SyncManager state. Reactive — reads
/// `state`'s underlying inputs through @Observable, so SwiftUI re-renders when
/// the user pastes the server URL, when sync starts, when it errors, etc.
struct SyncStateRow: View {
    let state: SyncState
    /// Server-assigned snapshot revision of the last successful sync, shown
    /// alongside the last-synced time. Nil until the first sync.
    var revision: Int? = nil

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
            return "Uploading snapshot…"
        case .error(let msg):
            return msg
        case .synced(let date):
            let when = Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
            if let revision {
                return "Last synced \(when) · snapshot #\(revision)"
            }
            return "Last synced \(when)"
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
