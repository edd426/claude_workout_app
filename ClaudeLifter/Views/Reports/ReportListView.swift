import SwiftUI

/// The report backlog, presented as a sheet from Today.
///
/// Every status change is on the row's `ellipsis.circle` menu as well as the
/// swipe (#154, UI-P7). Delete is red, last, and confirmed; the swipe never
/// deletes on a full swipe (UI-P6).
struct ReportListView: View {
    @State var vm: ReportListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: ExerciseReport?
    @State private var deleteConfirmed = 0

    var body: some View {
        @Bindable var vm = vm
        return List {
            if vm.visibleReports.isEmpty {
                emptyState
            } else {
                ForEach(vm.visibleReports, id: \.id) { report in
                    ReportRow(report: report) { action in
                        handle(action, on: report)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        swipeButtons(for: report)
                    }
                }
            }
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(filter: $vm.statusFilter) }
        .sensoryFeedback(.warning, trigger: deleteConfirmed)
        .confirmationDialog(
            "Delete this report?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { report in
            Button("Delete Report", role: .destructive) {
                deleteConfirmed += 1
                Task { await vm.perform(.delete, on: report) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It is removed from this phone and, at the next sync, from the cloud. Claude can no longer read it.")
        }
        .task { await vm.load() }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            vm.statusFilter == .all
                ? "No reports"
                : "Nothing \(vm.statusFilter.displayName.lowercased())",
            systemImage: vm.statusFilter.systemImage,
            description: Text(
                vm.reports.isEmpty
                    ? "Reports you file from a workout show up here, and "
                        + "Claude can read them over MCP."
                    : "\(vm.reports.count) report\(vm.reports.count == 1 ? "" : "s") "
                        + "under a different filter."
            )
        )
    }

    /// Status moves are one swipe away for speed, the first outermost;
    /// Delete sits innermost and is confirmed like the menu's.
    ///
    /// Delete carries no `.destructive` role here on purpose: in a swipe that
    /// role animates the row away at once, before the confirmation is
    /// answered. It is painted system red explicitly instead, because the
    /// app-wide tint would otherwise paint it terracotta (UI-P6).
    @ViewBuilder
    private func swipeButtons(for report: ExerciseReport) -> some View {
        ForEach(ReportListViewModel.actions(for: report.status)) { action in
            Button {
                handle(action, on: report)
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
            .tint(action.swipeTint)
        }
    }

    private func handle(_ action: ReportRowAction, on report: ExerciseReport) {
        if action.isDestructive {
            pendingDelete = report
        } else {
            Task { await vm.perform(action, on: report) }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(filter: Binding<ReportStatusFilter>) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
                .accessibilityIdentifier("closeReports")
        }
        ToolbarItem(placement: .primaryAction) {
            // A picker rather than the old "Show resolved" toggle. That
            // toggle keyed on a state nothing in the app or the write path
            // ever produced, so it could not visibly do anything (#146).
            Menu {
                Picker("Filter", selection: filter) {
                    ForEach(ReportStatusFilter.allCases) { option in
                        Label(option.displayName, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
            } label: {
                Label(filter.wrappedValue.displayName, systemImage: "line.3.horizontal.decrease.circle")
            }
            .accessibilityIdentifier("reportStatusFilter")
        }
    }
}

private extension ReportRowAction {
    var swipeTint: Color {
        switch self {
        case .acknowledge: BrandTheme.info
        case .resolve: BrandTheme.success
        case .reopen: BrandTheme.warning
        case .delete: BrandTheme.destructive
        }
    }
}

private struct ReportRow: View {
    let report: ExerciseReport
    let onAction: (ReportRowAction) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            content
            actionsMenu
        }
        .padding(.vertical, 4)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(report.detail)
                .font(.body)
            details
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Badge on its own line, category under it, so neither truncates:
    /// side by side, "Fixed – awaiting install" was cut off at default size
    /// next to the row menu. The badge keeps its natural width, except at
    /// accessibility sizes where it may wrap (UI-A3).
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ReportStatusBadge(status: report.status)
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                // Set only once the photo is in blob storage, i.e. readable
                // over MCP with get_report_photo (#141).
                if report.photoURL != nil {
                    Image(systemName: "photo")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Photo attached")
                }
            }
            Label(report.category.displayName, systemImage: report.category.systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(BrandTheme.accentText)
        }
    }

    @ViewBuilder
    private var details: some View {
        if let name = report.exerciseName {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if let replacement = report.suggestedReplacement {
            Text("→ \(replacement)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if let resolution = report.resolution {
            Text(resolution)
                .font(.subheadline)
                .foregroundStyle(BrandTheme.success)
        }
        Text(report.createdAt, format: .dateTime.month().day().hour().minute())
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// The visible path to every swipe action (UI-P7). Status moves first,
    /// Delete last in its own section (UI-P6, UI-P8).
    private var actionsMenu: some View {
        let actions = ReportListViewModel.actions(for: report.status)
        return Menu {
            Section {
                ForEach(actions.filter { !$0.isDestructive }) { action in
                    Button(action.title, systemImage: action.systemImage) { onAction(action) }
                }
            }
            Section {
                ForEach(actions.filter(\.isDestructive)) { action in
                    Button(action.title, systemImage: action.systemImage, role: .destructive) {
                        onAction(action)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(BrandTheme.accent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Report actions")
        .accessibilityIdentifier("reportActions")
    }
}

/// Status as a capsule: colour plus words, never colour alone (UI-C4).
struct ReportStatusBadge: View {
    let status: ReportStatus

    var body: some View {
        Label(status.badgeTitle, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .accessibilityLabel("Status: \(status.badgeTitle)")
    }

    private var color: Color {
        switch status {
        case .open: BrandTheme.warning
        case .acknowledged: BrandTheme.info
        case .resolved: BrandTheme.success
        }
    }

    private var systemImage: String {
        switch status {
        case .open: "flag.fill"
        case .acknowledged: "shippingbox.fill"
        case .resolved: "checkmark.circle.fill"
        }
    }
}
