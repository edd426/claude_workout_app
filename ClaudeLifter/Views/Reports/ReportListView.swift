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
                    vm.showsResolved ? "No reports" : "Nothing outstanding",
                    systemImage: "flag",
                    description: Text(
                        "Reports you file from a workout show up here, and "
                        + "Claude can read them over MCP."
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
                        }
                }
            }
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle("Show resolved", isOn: $vm.showsResolved)
                    .toggleStyle(.button)
                    .accessibilityIdentifier("toggleResolvedReports")
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
