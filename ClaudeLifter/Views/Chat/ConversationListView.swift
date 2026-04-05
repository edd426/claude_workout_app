import SwiftUI

// MARK: - ConversationListView

struct ConversationListView: View {

    @State var viewModel: ChatViewModel
    @Binding var isPresented: Bool
    @State private var conversations: [(id: UUID, preview: String, date: Date)] = []

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    ContentUnavailableView(
                        "No Past Chats",
                        systemImage: "message",
                        description: Text("Your past conversations will appear here.")
                    )
                } else {
                    List(conversations, id: \.id) { convo in
                        Button {
                            Task {
                                await viewModel.loadConversation(id: convo.id)
                                isPresented = false
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(convo.preview)
                                    .font(.body)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                                Text(convo.date, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Past Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .task {
                conversations = await viewModel.listConversations()
            }
        }
    }
}
