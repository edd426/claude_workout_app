import SwiftUI

/// The automatic refreshes behind Today's pull-to-refresh (UI-P7): a workout
/// ending, the app returning to the foreground, a finished sync, and the
/// sync manager's approvals changing.
struct TodayRefreshTriggers: ViewModifier {
    @Environment(\.dependencies) private var deps
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    let onWorkoutEnded: () -> Void
    let onBecameActive: () -> Void
    let onSynced: () -> Void
    let onApprovalsChanged: ([InboxOperationDTO]) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: appState.isWorkoutActive) { wasActive, isActive in
                if wasActive && !isActive { onWorkoutEnded() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { onBecameActive() }
            }
            .onChange(of: deps?.syncManager.lastSyncDate) { _, _ in
                onSynced()
            }
            .onChange(of: deps?.syncManager.pendingApprovals ?? []) { _, approvals in
                onApprovalsChanged(approvals)
            }
    }
}

/// An approve or decline that failed on the server. This is a decision
/// point, so it is an alert rather than a banner (UI-E1).
struct ApprovalErrorAlert: ViewModifier {
    let approvalVM: InboxApprovalViewModel?

    func body(content: Content) -> some View {
        content.alert(
            "Approval Error",
            isPresented: Binding(
                get: { approvalVM?.errorMessage != nil },
                set: { if !$0 { approvalVM?.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                approvalVM?.errorMessage = nil
            }
        } message: {
            Text(approvalVM?.errorMessage ?? "")
        }
    }
}

/// Every sheet Today presents. Each one has a visible Close, Done or Cancel
/// of its own (UI-P4).
struct TodaySheets<Summary: View>: ViewModifier {
    @Environment(\.dependencies) private var deps

    @Binding var completedSummary: WorkoutCompletionSummary?
    @Binding var showSettings: Bool
    @Binding var showPendingChanges: Bool
    @Binding var showReports: Bool
    @Binding var showTemplateEditor: Bool
    @Binding var generalReportContext: ReportContext?
    let approvalVM: InboxApprovalViewModel?
    let reportListVM: ReportListViewModel?
    /// Something Today shows may have changed while the sheet was up.
    let onReload: () -> Void
    @ViewBuilder let summarySheet: (WorkoutCompletionSummary) -> Summary

    func body(content: Content) -> some View {
        content
            // The completion summary is presented here, not inside
            // ActiveWorkoutView, because ending the workout tears that view
            // down. Presenting it over Today means the workout is already
            // safely closed by the time this appears, so any way of
            // dismissing it is harmless (#123).
            .sheet(item: $completedSummary) { summarySheet($0) }
            // Settings left the tab bar in 1.9.0; SettingsView has its own
            // NavigationStack and Done.
            .sheet(isPresented: $showSettings, onDismiss: onReload) {
                SettingsView()
            }
            .sheet(item: $generalReportContext) { context in
                reportSheet(context)
            }
            .sheet(isPresented: $showPendingChanges) {
                pendingChangesSheet
            }
            .sheet(isPresented: $showReports, onDismiss: onReload) {
                reportsSheet
            }
            .sheet(isPresented: $showTemplateEditor, onDismiss: onReload) {
                templateEditorSheet
            }
    }

    @ViewBuilder
    private func reportSheet(_ context: ReportContext) -> some View {
        if let deps {
            ReportSheetView(
                vm: ReportSheetViewModel(
                    context: context,
                    repository: deps.exerciseReportRepository,
                    photoStore: deps.reportPhotoStore
                ),
                onSaved: onReload
            )
        }
    }

    @ViewBuilder
    private var pendingChangesSheet: some View {
        if let approvalVM {
            NavigationStack {
                PendingChangesView(vm: approvalVM)
            }
            // One batch, one sync, after the user is done deciding (#153).
            .onDisappear { Task { await approvalVM.commit() } }
        }
    }

    @ViewBuilder
    private var reportsSheet: some View {
        if let reportListVM {
            // Reports are also closed out by the AI over MCP, so the list
            // reloads on dismiss (`onReload`).
            NavigationStack {
                ReportListView(vm: reportListVM)
            }
        }
    }

    @ViewBuilder
    private var templateEditorSheet: some View {
        if let deps {
            TemplateEditorView(
                vm: TemplateEditorViewModel(
                    template: nil,
                    templateRepository: deps.templateRepository
                )
            )
        }
    }
}
