import SwiftUI

// MARK: - ToolActionCardView

/// Compact card shown for tool-action system messages.
struct ToolActionCardView: View {

    let content: String

    /// Strips the "[Tool: toolName]" prefix for display, if present.
    private var displayContent: String {
        if content.hasPrefix("[Tool: ") {
            if let range = content.range(of: "] ") {
                return String(content[range.upperBound...])
            }
        }
        return content
    }

    private var toolName: String? {
        guard content.hasPrefix("[Tool: "),
              let closeRange = content.range(of: "]") else { return nil }
        let start = content.index(content.startIndex, offsetBy: 7)
        return String(content[start..<closeRange.lowerBound])
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                if let name = toolName {
                    Text(name.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                Text(displayContent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
