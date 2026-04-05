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
                CollapsibleToolResultView(content: content)
            case .toolUse(_, let name, let inputJSON):
                CollapsibleToolUseView(name: name, inputJSON: inputJSON)
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
            case .toolUse(_, let name, let inputJSON):
                CollapsibleToolUseView(name: name, inputJSON: inputJSON)
            case .toolResult(_, let content):
                CollapsibleToolResultView(content: content)
            }
        }
    }

    // MARK: - Helpers

    /// Renders a string with full markdown (headers, bold, italic, code, links).
    /// Falls back to plain text if parsing fails.
    private func markdownText(_ string: String) -> Text {
        if let attributed = try? AttributedString(markdown: string) {
            return Text(attributed)
        }
        return Text(string)
    }
}

// MARK: - CollapsibleToolUseView

private struct CollapsibleToolUseView: View {

    let name: String
    let inputJSON: String
    @State private var isExpanded = false

    private var displayName: String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)
                ScrollView {
                    Text(inputJSON)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 120)
            }
        }
        .background(BrandTheme.lightGray)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 280, alignment: .leading)
    }
}

// MARK: - CollapsibleToolResultView

private struct CollapsibleToolResultView: View {

    let content: String
    @State private var isExpanded = false

    private var summaryLine: String {
        let first = content.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? content
        if first.count > 50 {
            return String(first.prefix(50)) + "…"
        }
        return first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)
                ScrollView {
                    Text(content)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(BrandTheme.lightGray)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 280, alignment: .leading)
    }
}
