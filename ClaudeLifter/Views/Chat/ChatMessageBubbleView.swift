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
            ToolActionCardView(content: message.content)
        }
    }

    // MARK: - User Bubble (right-aligned, terracotta)

    private var userBubble: some View {
        HStack {
            Spacer()
            Text(message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(BrandTheme.terracotta)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 280, alignment: .trailing)
        }
    }

    // MARK: - Assistant Bubble (left-aligned, lightGray)

    private var assistantBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(BrandTheme.lightGray)
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 280, alignment: .leading)
            Spacer()
        }
    }
}
