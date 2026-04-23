import SwiftUI

// MARK: - ChatInputView

struct ChatInputView: View {

    let onSend: (String) -> Void
    /// Drive disabled state from the ViewModel so the button also locks out
    /// while a response is streaming, not just when the input is empty.
    var isLoading: Bool = false

    @State private var inputText: String = ""
    @FocusState private var isTextFieldFocused: Bool

    private var isSendDisabled: Bool {
        isLoading || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField("Message Coach...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($isTextFieldFocused)
                .onSubmit {
                    sendMessage()
                }
                .accessibilityIdentifier("chatMessageInput")

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(isSendDisabled ? Color(.systemGray3) : BrandTheme.terracotta)
            }
            .disabled(isSendDisabled)
            .accessibilityIdentifier("sendMessage")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }
        onSend(trimmed)
        inputText = ""
    }
}
