import SwiftUI

/// Home card showing how many reports are still outstanding. Exists so filed
/// reports don't quietly rot — a backlog nobody sees is a backlog nobody
/// clears. Renders nothing when there is nothing outstanding.
struct OpenReportsCard: View {
    let count: Int
    /// Reports that have an answer written but are waiting on an install.
    /// Shown apart from `count` because folding them together made the card
    /// say "6 open reports" while three of the six displayed a resolution
    /// (#146) — the number disagreed with what was on screen right below it.
    var acknowledgedCount: Int = 0
    let onOpen: () -> Void

    private var total: Int { count + acknowledgedCount }

    private var title: String {
        switch (count, acknowledgedCount) {
        case (0, let waiting):
            return waiting == 1 ? "1 report awaiting install" : "\(waiting) reports awaiting install"
        case (let open, 0):
            return open == 1 ? "1 open report" : "\(open) open reports"
        case (let open, let waiting):
            return "\(open) open · \(waiting) awaiting install"
        }
    }

    var body: some View {
        if total > 0 {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(BrandTheme.terracotta)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 8)
            .accessibilityIdentifier("openReportsCard")
        }
    }
}
