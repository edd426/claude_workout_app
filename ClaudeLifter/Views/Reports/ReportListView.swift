import SwiftUI

/// The report backlog. Reachable from the Home card so filed reports are
/// visible without a round trip through the cloud.
struct ReportListView: View {
    @State var vm: ReportListViewModel

    var body: some View {
        @Bindable var vm = vm
        return List {
            if vm.visibleReports.isEmpty {
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
            } else {
                ForEach(vm.visibleReports, id: \.id) { report in
                    ReportRow(report: report)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await vm.delete(report) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            if report.status != .resolved {
                                Button {
                                    Task { await vm.setStatus(.resolved, for: report) }
                                } label: {
                                    Label("Resolve", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                            if report.status == .open {
                                Button {
                                    Task { await vm.setStatus(.acknowledged, for: report) }
                                } label: {
                                    Label("Acknowledge", systemImage: "checkmark.bubble")
                                }
                                .tint(BrandTheme.terracotta)
                            }
                            // The escape hatch #136 needed: a fix that turns
                            // out to be inert has to be reopenable, or the
                            // backlog quietly loses a real complaint.
                            if report.status != .open {
                                Button {
                                    Task { await vm.setStatus(.open, for: report) }
                                } label: {
                                    Label("Reopen", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.orange)
                            }
                        }
                }
            }
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // A picker rather than the old "Show resolved" toggle. That
                // toggle keyed on a state nothing in the app or the write path
                // ever produced, so it could not visibly do anything (#146).
                Menu {
                    Picker("Filter", selection: $vm.statusFilter) {
                        ForEach(ReportStatusFilter.allCases) { filter in
                            Label(filter.displayName, systemImage: filter.systemImage)
                                .tag(filter)
                        }
                    }
                } label: {
                    Label(vm.statusFilter.displayName, systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("reportStatusFilter")
            }
        }
        .task { await vm.load() }
    }
}

private struct ReportRow: View {
    let report: ExerciseReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label(report.category.displayName, systemImage: report.category.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BrandTheme.terracotta)
                Spacer()
                if report.status != .open {
                    Text(report.status.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(report.detail)
                .font(.body)
            if let name = report.exerciseName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let replacement = report.suggestedReplacement {
                Text("→ \(replacement)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let resolution = report.resolution {
                Text(resolution)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Text(report.createdAt, format: .dateTime.month().day().hour().minute())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
