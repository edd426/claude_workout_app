import SwiftUI

// MARK: - ChatView

struct ChatView: View {

    @State var viewModel: ChatViewModel
    @State private var showConversationList = false

    var body: some View {
        VStack(spacing: 0) {
            contextBanner
            errorBanner
            messageList
            Divider()
            ChatInputView(
                onSend: { text in
                    Task { await viewModel.sendMessage(text) }
                },
                isLoading: viewModel.isLoading
            )
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        viewModel.startNewConversation()
                    } label: {
                        Label("New Chat", systemImage: "plus.message")
                    }
                    Button {
                        showConversationList = true
                    } label: {
                        Label("Past Chats", systemImage: "clock.arrow.circlepath")
                    }
                    Divider()
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
        .task {
            // Load preferences first so the very first sendMessage() includes
            // them in the system prompt. Previously this was never called and
            // cachedPreferences stayed empty for the entire session.
            await viewModel.loadPreferences()
            await viewModel.loadHistory()
        }
        .sheet(isPresented: $showConversationList) {
            ConversationListView(viewModel: viewModel, isPresented: $showConversationList)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var contextBanner: some View {
        if viewModel.activeWorkoutContext != nil || !modelDisplay.isEmpty {
            HStack(spacing: 8) {
                if let context = viewModel.activeWorkoutContext {
                    Label(context, systemImage: "figure.strengthtraining.traditional")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !modelDisplay.isEmpty {
                    Text(modelDisplay)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospaced()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            Divider()
        }
    }

    /// Short human-readable name for the currently selected Anthropic model,
    /// surfaced in the Coach header so the user can see at a glance which
    /// model their messages are hitting (Haiku vs Sonnet vs Opus).
    private var modelDisplay: String {
        let raw = viewModel.selectedModel
        if let known = AIModel(rawValue: raw) {
            return known.displayName
        }
        // Fallback: strip the "claude-" prefix if present so arbitrary model
        // strings still render compactly.
        return raw.replacingOccurrences(of: "claude-", with: "")
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

    /// Renders a string with markdown, preserving the user-visible line
    /// breaks that Claude emits. By default AttributedString(markdown:) uses
    /// inlineOnly parsing, which collapses newlines into spaces and fuses
    /// paragraphs — so Claude's "reps.\n\nFace Pull:" rendered as
    /// "reps.Face Pull:" with nothing between them. We use
    /// `.inlineOnlyPreservingWhitespace` so the \n characters stay put, and
    /// we still pre-process single newlines into markdown hard-breaks so
    /// single-line wraps also render.
    private func markdownText(_ string: String) -> Text {
        let processed = string
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
        let footer = "\n\n---\n\(BuildInfo.summary)"
        UIPasteboard.general.string = lines.joined(separator: "\n\n") + footer
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
