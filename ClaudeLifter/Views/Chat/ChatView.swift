import SwiftUI

// MARK: - ChatView

struct ChatView: View {

    @State var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            contextBanner
            errorBanner
            messageList
            Divider()
            ChatInputView(onSend: { text in
                Task { await viewModel.sendMessage(text) }
            })
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copyConversation()
                    } label: {
                        Label("Copy Conversation", systemImage: "doc.on.doc")
                    }
                    .disabled(viewModel.messages.isEmpty)
                    Button(role: .destructive) {
                        viewModel.clearChat()
                    } label: {
                        Label("Clear Chat", systemImage: "trash")
                    }
                    .disabled(viewModel.messages.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            viewModel.pendingConfirmation?.description ?? "",
            isPresented: .init(
                get: { viewModel.pendingConfirmation != nil },
                set: { if !$0 { viewModel.cancelPendingAction() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Save") {
                Task { await viewModel.confirmPendingAction() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelPendingAction()
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var contextBanner: some View {
        if let context = viewModel.activeWorkoutContext {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.secondary)
                Text("Chatting about: \(context)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            Divider()
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let errorMsg = viewModel.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            Divider()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {

                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        ChatMessageBubbleView(message: message)
                            .id(message.id)
                    }
                    if viewModel.isLoading && !viewModel.thinkingText.isEmpty && viewModel.currentStreamingText.isEmpty {
                        thinkingIndicator
                            .id("thinking")
                    }
                    if !viewModel.currentStreamingText.isEmpty {
                        streamingBubble
                            .id("streaming")
                    }
                    if viewModel.isLoading && viewModel.currentStreamingText.isEmpty && viewModel.thinkingText.isEmpty {
                        loadingIndicator
                            .id("loading")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.currentStreamingText) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.thinkingText) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var streamingBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            markdownText(viewModel.currentStreamingText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(BrandTheme.lightGray)
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 280, alignment: .leading)
            Spacer()
        }
    }

    // MARK: - Helpers

    /// Renders a string with inline markdown. Falls back to plain text on failure.
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

    private var thinkingIndicator: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Thinking...")
                    .font(.caption)
                    .foregroundStyle(BrandTheme.secondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(BrandTheme.lightGray)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            Spacer()
        }
    }

    private var loadingIndicator: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(BrandTheme.lightGray)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            Spacer()
        }
    }

    // MARK: - Helpers

    private func copyConversation() {
        let lines = viewModel.messages.map { message -> String in
            let role: String
            switch message.role {
            case .user: role = "You"
            case .assistant: role = "Coach"
            case .system: role = "System"
            }
            let text: String
            switch message.content {
            case .text(let str):
                text = str
            case .toolUse(_, let name, _):
                text = "[Tool: \(name)]"
            case .toolResult(_, let result):
                text = "[Tool result] \(result)"
            }
            return "\(role): \(text)"
        }
        UIPasteboard.general.string = lines.joined(separator: "\n\n")
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if !viewModel.currentStreamingText.isEmpty {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if !viewModel.thinkingText.isEmpty {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = viewModel.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
