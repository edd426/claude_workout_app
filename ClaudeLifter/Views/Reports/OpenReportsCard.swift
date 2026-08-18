import SwiftUI

/// Home card showing how many reports are still outstanding. Exists so filed
/// reports don't quietly rot — a backlog nobody sees is a backlog nobody
/// clears. Renders nothing when there is nothing outstanding.
struct OpenReportsCard: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        if count > 0 {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(BrandTheme.terracotta)
                    Text(count == 1 ? "1 open report" : "\(count) open reports")
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
