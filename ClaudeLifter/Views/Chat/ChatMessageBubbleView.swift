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

    /// Renders a string with markdown (bold, italic, code, links, inline
    /// formatting). Uses .inlineOnlyPreservingWhitespace so line breaks
    /// Claude emits actually render. Block-level syntax like headers
    /// (`###`) is not supported by this parser — so we preprocess leading
    /// `#`-runs into `**bold**` spans before parsing, and also tell Claude
    /// in the system prompt to prefer `**bold**`. This keeps responses
    /// that DO contain headers readable instead of leaving literal "### "
    /// characters in the bubble.
    private func markdownText(_ string: String) -> Text {
        let headersAsBold = ChatMarkdown.convertHeadersToBold(string)
        let processed = headersAsBold
            .replacingOccurrences(of: "\n\n", with: "\u{0000}")
            .replacingOccurrences(of: "\n", with: "  \n")
            .replacingOccurrences(of: "\u{0000}", with: "\n\n")
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: processed, options: options) {
            return Text(attributed)
        }
        return Text(string)
    }
}

/// Shared helpers for rendering Coach text in the chat bubble and the
/// streaming view. Kept file-private-ish via a plain enum so unit tests
/// can exercise the same logic both views depend on.
enum ChatMarkdown {
    /// Convert leading `###`/`##`/`#` header markers at the start of a line
    /// into `**bold**` spans, so the inline-only markdown renderer doesn't
    /// leave literal "### " characters in the chat bubble.
    static func convertHeadersToBold(_ input: String) -> String {
        var output: [String] = []
        for line in input.components(separatedBy: "\n") {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.hasPrefix("###### ")
                || trimmed.hasPrefix("##### ")
                || trimmed.hasPrefix("#### ")
                || trimmed.hasPrefix("### ")
                || trimmed.hasPrefix("## ")
                || trimmed.hasPrefix("# ") {
                // Strip the leading `#` run plus the following space, wrap
                // remainder in **bold**. Preserve leading whitespace.
                let leadingCount = line.count - trimmed.count
                let leading = String(line.prefix(leadingCount))
                var body = String(trimmed)
                while body.first == "#" { body.removeFirst() }
                while body.first == " " { body.removeFirst() }
                // Strip any trailing `#` characters ("## Header ##" style).
                while body.last == "#" || body.last == " " { body.removeLast() }
                if !body.isEmpty {
                    output.append("\(leading)**\(body)**")
                } else {
                    output.append(line)
                }
            } else {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
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
