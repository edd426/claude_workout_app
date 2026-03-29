import SwiftUI

// MARK: - ChatView

struct ChatView: View {

    @State var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            contextBanner
            messageList
            Divider()
            ChatInputView(onSend: { text in
                Task { await viewModel.sendMessage(text) }
            })
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
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

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        ChatMessageBubbleView(message: message)
                            .id(message.id)
                    }
                    if !viewModel.currentStreamingText.isEmpty {
                        streamingBubble
                            .id("streaming")
                    }
                    if viewModel.isLoading && viewModel.currentStreamingText.isEmpty {
                        loadingIndicator
                            .id("loading")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.currentStreamingText) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var streamingBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(viewModel.currentStreamingText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 280, alignment: .leading)
            Spacer()
        }
    }

    private var loadingIndicator: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            Spacer()
        }
    }

    // MARK: - Helpers

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if !viewModel.currentStreamingText.isEmpty {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let last = viewModel.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
