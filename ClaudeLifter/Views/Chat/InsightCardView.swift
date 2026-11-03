import SwiftUI

struct InsightCardView: View {
    let insight: ProactiveInsight
    let onDismiss: () async -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.title3)
                .frame(minWidth: 24)
                .padding(.top, 12)
                .accessibilityHidden(true)

            Text(insight.content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)

            Button {
                Task { await onDismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The SF Symbol's own label is "Close", which doesn't say what
            // it closes (UI-A1).
            .accessibilityLabel("Dismiss insight")
            .accessibilityIdentifier("dismissInsight")
        }
        // 16 pt inside on the leading edge; the dismiss target supplies its
        // own space on the trailing edge (UI-S2, UI-T1).
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(
            BrandTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var iconName: String {
        switch insight.type {
        case .suggestion: return "lightbulb.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .encouragement: return "star.fill"
        }
    }

    private var iconColor: Color {
        switch insight.type {
        case .suggestion: return BrandTheme.accent
        case .warning: return BrandTheme.warning
        case .encouragement: return BrandTheme.info
        }
    }
}
