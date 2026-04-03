import SwiftUI

// MARK: - ChatMessageBubbleView

struct ChatMessageBubbleView: View {

    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .system:
            // Legacy system messages shown as tool cards
            ToolActionCardView(content: message.textContent)
        }
    }

    // MARK: - User Bubble (right-aligned, terracotta)

    private var userBubble: some View {
        Group {
            switch message.content {
            case .text(let str):
                HStack {
                    Spacer()
                    Text(str)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(BrandTheme.terracotta)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: 280, alignment: .trailing)
                }
            case .toolResult(_, let content):
                // Tool results (user role) shown as compact info cards
                ToolActionCardView(content: content)
            case .toolUse(_, let name, _):
                ToolActionCardView(content: "[Tool: \(name)]")
            }
        }
    }

    // MARK: - Assistant Bubble (left-aligned, lightGray)

    private var assistantBubble: some View {
        Group {
            switch message.content {
            case .text(let str):
                HStack(alignment: .bottom, spacing: 8) {
                    markdownText(str)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(BrandTheme.lightGray)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: 280, alignment: .leading)
                    Spacer()
                }
            case .toolUse(_, let name, _):
                // Show tool-use assistant messages as compact cards
                ToolActionCardView(content: "[Tool: \(name)]")
            case .toolResult(_, let content):
                ToolActionCardView(content: content)
            }
        }
    }

    // MARK: - Helpers

    /// Renders a string with inline markdown (bold, italic, code, links).
    /// Falls back to plain text if parsing fails.
    /// Uses inlineOnlyPreservingWhitespace to avoid block-level elements (headers, etc.)
    /// appearing in chat bubbles.
    private func markdownText(_ string: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: string,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }
        return Text(string)
    }
}
