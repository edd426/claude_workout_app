import SwiftUI

struct InsightCardView: View {
    let insight: ProactiveInsight
    let onDismiss: () async -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.title3)
                .frame(width: 24)

            Text(insight.content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await onDismiss() }
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        case .suggestion: return .yellow
        case .warning: return .orange
        case .encouragement: return .blue
        }
    }
}
