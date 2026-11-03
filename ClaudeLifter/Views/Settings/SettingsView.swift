import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Settings, presented as a sheet from Today's gear (1.9.0).
///
/// No gesture sits on the `Form`. A Form-wide tap gesture to dismiss the
/// keyboard won every tap, so Restore, Export and Import fired only on a
/// press-and-hold (#171). The keyboard goes with a scroll or the keyboard
/// toolbar's Done instead.
struct SettingsView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
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
    /// What the one file importer is picking. Two `.fileImporter`s in one
    /// view hierarchy fight, so backup and Jefit share this one.
    @State private var importKind: ImportKind = .backup
    @State private var jefitFile: PickedFile?
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

    enum ImportKind {
        case backup
        case jefit

        var contentTypes: [UTType] {
            switch self {
            case .backup: return [.json]
            case .jefit: return [.commaSeparatedText, .plainText, .text]
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    form(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Settings")
            .toolbar { toolbar }
            .navigationDestination(item: $jefitFile) { file in
                JefitImportView(fileURL: file.url)
            }
        }
        .task {
            quarantinePath = UserDefaults.standard.string(forKey: "lastStoreQuarantinePath")
            guard vm == nil, let deps else { return }
            vm = SettingsViewModel(settingsManager: deps.settings)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Settings is a sheet; Done is its visible way out (UI-P4).
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
                .accessibilityIdentifier("settingsDone")
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focusedField = nil }
        }
    }

    private func form(vm: SettingsViewModel) -> some View {
        Form {
            weightUnitSection(vm: vm)
            aiModelSection(vm: vm)
            insightsSection(vm: vm)
            if let deps {
                syncStatusSection(syncManager: deps.syncManager)
                backupSection(deps: deps)
            }
            advancedSection(vm: vm)
            if let quarantinePath {
                quarantineSection(path: quarantinePath)
            }
            buildInfoSection
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .accessibilityIdentifier("backupShareSheet")
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: importKind.contentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .alert("Data", isPresented: alertPresented) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
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
            .accessibilityIdentifier("exportBackup")
            Button {
                importKind = .backup
                isImporting = true
            } label: {
                Label("Import Backup", systemImage: "square.and.arrow.down")
            }
            Button {
                #if DEBUG
                if let path = Self.uiTestJefitFixturePath {
                    jefitFile = PickedFile(url: URL(fileURLWithPath: path))
                    return
                }
                #endif
                importKind = .jefit
                isImporting = true
            } label: {
                Label("Import Jefit History…", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("importJefitHistory")
        } header: {
            Text("Backup")
        } footer: {
            Text("Export writes a JSON file of all workouts, templates, custom exercises, and preferences that you can save off-device. Import merges a backup file, skipping anything already on this device. Jefit import reads the CSV from Jefit's Export Data and shows what it will add before it writes anything.")
        }
    }

    #if DEBUG
    /// UI tests can't drive the system file picker. Under `-UITesting` only,
    /// the `-UITestJefitFixturePath <path>` launch argument stands in for a
    /// picked file. Debug builds only; a release build has no such path.
    private static var uiTestJefitFixturePath: String? {
        guard ProcessInfo.processInfo.arguments.contains("-UITesting") else { return nil }
        return UserDefaults.standard.string(forKey: "UITestJefitFixturePath")
    }
    #endif

    private func quarantineSection(path: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("A previous database failed to open and was recovered. Your old data was moved here (not deleted):")
                    .font(.subheadline)
                Text(path)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Button("Dismiss") {
                UserDefaults.standard.removeObject(forKey: "lastStoreQuarantinePath")
                quarantinePath = nil
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
        switch importKind {
        case .jefit:
            // The import screen handles reading and every error itself.
            if case .success(let urls) = result, let url = urls.first {
                jefitFile = PickedFile(url: url)
            } else if case .failure(let error) = result,
                      (error as? CocoaError)?.code != .userCancelled {
                alertMessage = "Couldn't open the file: \(error.localizedDescription)"
            }
        case .backup:
            importBackup(result: result)
        }
    }

    private func importBackup(result: Result<[URL], Error>) {
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
                AIModelRow(model: model, isSelected: vm.aiModel == model) {
                    vm.aiModel = model
                }
            }
        }
    }

    /// Developer configuration, below the user's own preferences (§3.12).
    @ViewBuilder
    private func advancedSection(vm: SettingsViewModel) -> some View {
        @Bindable var vm = vm
        Section {
            HStack(spacing: 8) {
                TextField(
                    "Server URL",
                    text: $vm.serverURL,
                    prompt: Text("https://your-server.azurewebsites.net")
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .focused($focusedField, equals: .serverURL)
                if !vm.serverURL.isEmpty {
                    Button {
                        vm.serverURL = ""
                    } label: {
                        Label("Clear server URL", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            SecureField("Server API Key", text: $vm.apiKey, prompt: Text("Server API key"))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .apiKey)
        } header: {
            Text("Advanced")
        } footer: {
            Text(vm.serverURL.isEmpty
                 ? "No server configured — using API key directly (Phase 1 mode)."
                 : "Chat and sync routed through \(vm.serverURL)")
        }
    }

    private func insightsSection(vm: SettingsViewModel) -> some View {
        @Bindable var vm = vm
        return Section {
            Toggle("Proactive insights on Today", isOn: $vm.proactiveInsightsEnabled)
        } header: {
            Text("Today Screen")
        } footer: {
            Text(vm.proactiveInsightsEnabled
                 ? "Shows Coach-generated suggestion cards on Today (\u{201C}You haven’t trained legs in 2 weeks”, etc.). Turn off if they pile up when you’re away from the app."
                 : "Today will not show insight cards. No new insights will be generated either.")
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

    /// The version footer: the visible proof a new build landed.
    private var buildInfoSection: some View {
        Section {
            Button {
                UIPasteboard.general.string = BuildInfo.summary
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(BuildInfo.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Tap to copy")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("buildInfo")
        } header: {
            Text("About")
        }
    }
}

/// A model choice. A Button, not a tap gesture, so it has the button trait
/// and VoiceOver activation (UI-T4); the checkmark is the accent colour,
/// and "selected" is announced (UI-C4).
private struct AIModelRow: View {
    let model: AIModel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .foregroundStyle(.primary)
                    Text(model.costIndicator)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BrandTheme.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("aiModel_\(model.rawValue)")
    }
}

// MARK: - Backup share sheet helpers

/// Identifiable wrapper so a freshly-exported file URL can drive `.sheet(item:)`.
private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// A picked file, so it can drive `.navigationDestination(item:)`.
struct PickedFile: Identifiable, Hashable {
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
                .frame(minWidth: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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
        case .disabled: return BrandTheme.warning
        case .offline:  return .secondary
        case .syncing:  return BrandTheme.info
        case .error:    return BrandTheme.destructive
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
            return "Set the Server URL under Advanced to enable cloud sync."
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
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BrandTheme.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cloud sync is off")
                        .font(.subheadline.weight(.medium))
                    Text("Workouts are saved on this device only. Open Settings to set the server URL.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(BrandTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
            .padding(.horizontal)
            .padding(.top, 8)
        } else {
            EmptyView()
        }
    }
}
