import SwiftUI

/// Every inbox change awaiting approval, with its real diff, decided in one
/// sitting (#153, closes #147).
///
/// Verdicts are staged per row and sent together when the sheet closes, so
/// Home stays usable while changes are pending and N decisions cost one sync
/// instead of N. Undecided rows simply stay pending.
struct PendingChangesView: View {
    @Bindable var vm: InboxApprovalViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if vm.approvals.isEmpty {
                ContentUnavailableView(
                    "Nothing waiting",
                    systemImage: "checkmark.shield",
                    description: Text("Changes proposed by the Coach or over MCP show up here.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(vm.approvals, id: \.id) { operation in
                        PendingChangeRow(
                            operation: operation,
                            preview: vm.preview(for: operation),
                            verdict: vm.verdict(for: operation),
                            onVerdict: { verdict in
                                if vm.verdict(for: operation) == verdict {
                                    vm.unstage(operation)
                                } else {
                                    vm.stage(operation, verdict)
                                }
                            }
                        )
                    }
                } footer: {
                    Text(footerText)
                }
            }
        }
        .navigationTitle("Pending changes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Approve All") { vm.stageAll(.approve) }
                    Button("Decline All", role: .destructive) { vm.stageAll(.decline) }
                } label: {
                    Label("All", systemImage: "checklist")
                }
                .disabled(vm.approvals.isEmpty)
                .accessibilityIdentifier("pendingChangesAllMenu")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(doneTitle) { dismiss() }
                    .fontWeight(.semibold)
                    .disabled(vm.isCommitting)
                    .accessibilityIdentifier("pendingChangesDone")
            }
        }
        .interactiveDismissDisabled(vm.isCommitting)
        .overlay {
            if vm.isCommitting {
                ProgressView("Applying…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert(
            "Could not apply",
            isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var doneTitle: String {
        vm.stagedCount == 0 ? "Done" : "Apply \(vm.stagedCount)"
    }

    private var footerText: String {
        if vm.stagedCount == 0 {
            return "Tap Approve or Decline on each change. Nothing is sent until you tap Done."
        }
        let left = vm.approvals.count - vm.stagedCount
        return left == 0
            ? "All \(vm.stagedCount) decided. They are applied together when you tap Apply."
            : "\(vm.stagedCount) decided, \(left) still pending. Undecided changes stay in the queue."
    }
}

private struct PendingChangeRow: View {
    let operation: InboxOperationDTO
    let preview: InboxChangePreview?
    let verdict: InboxDecision.Verdict?
    let onVerdict: (InboxDecision.Verdict) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview?.title ?? "Proposed change")
                .font(.headline)
            if let preview {
                diffBody(preview)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            verdictButtons
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("pendingChange_\(operation.id)")
    }

    @ViewBuilder
    private func diffBody(_ preview: InboxChangePreview) -> some View {
        if preview.lines.isEmpty {
            Text(preview.summary)
                .font(.subheadline)
                .foregroundStyle(preview.isDestructive ? .red : .secondary)
        } else if preview.lines.count <= 3 {
            diffLines(preview.lines)
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                diffLines(preview.lines)
            } label: {
                Text("\(preview.lines.count) changes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func diffLines(_ lines: [InboxChangeLine]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines) { line in
                Text(line.text)
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(line.isStructural ? .medium : .regular)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var verdictButtons: some View {
        HStack(spacing: 10) {
            verdictButton(
                .approve,
                title: preview?.isDestructive == true ? "Delete" : "Approve",
                systemImage: "checkmark",
                tint: preview?.isDestructive == true ? .red : BrandTheme.terracotta
            )
            verdictButton(
                .decline,
                title: "Decline",
                systemImage: "xmark",
                tint: .secondary
            )
            Spacer()
            if verdict != nil {
                Text(verdict == .approve ? "Will apply" : "Will decline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func verdictButton(
        _ value: InboxDecision.Verdict,
        title: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        let selected = verdict == value
        return Button {
            onVerdict(value)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(selected ? tint : .secondary)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? tint : .clear, lineWidth: 1.5)
        )
        .accessibilityIdentifier(
            "\(value == .approve ? "approve" : "decline")_\(operation.id)"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The Home entry point: one card for however many changes are waiting,
/// showing the first diff line so a single reps change reads as one.
struct PendingChangesCard: View {
    let count: Int
    let headlines: [String]
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                count == 1 ? "1 change awaiting approval" : "\(count) changes awaiting approval",
                systemImage: "checkmark.shield"
            )
            .font(.caption)
            .foregroundStyle(BrandTheme.terracotta)
            ForEach(headlines.prefix(3), id: \.self) { headline in
                Text(headline)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            if headlines.count > 3 {
                Text("and \(headlines.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Review Changes", action: onReview)
                .buttonStyle(.borderedProminent)
                .tint(BrandTheme.terracotta)
                .accessibilityIdentifier("reviewInboxApproval")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            .quaternary.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityIdentifier("pendingChangesCard")
    }
}
