import SwiftUI

// MARK: - ChatView

struct ChatView: View {
    let messages: [ChatMessage]
    let onToggleCollapse: (UUID) -> Void
    let onCopyMessage: (UUID) -> Void
    var onStartEdit: ((UUID) -> Void)?
    var onConfirmEdit: ((UUID, String) -> Void)?
    var onCancelEdit: ((UUID) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        HStack {
                            // Transcription/user — right-aligned (70% width)
                            if message.role == .transcription || message.role == .user {
                                Spacer(minLength: 0)
                            }

                            ChatBubbleView(
                                message: message,
                                isLastAssistant: isLastAssistantMessage(message),
                                onToggleCollapse: { onToggleCollapse(message.id) },
                                onCopy: { onCopyMessage(message.id) },
                                onStartEdit: { onStartEdit?(message.id) },
                                onConfirmEdit: { text in onConfirmEdit?(message.id, text) },
                                onCancelEdit: { onCancelEdit?(message.id) }
                            )
                            .frame(
                                maxWidth: message.role == .system
                                    ? .infinity
                                    : UIConstants.bubbleMaxWidth,
                                alignment: message.role == .transcription || message.role == .user
                                    ? .trailing
                                    : .leading
                            )

                            // Assistant — left-aligned (70% width)
                            if message.role == .assistant {
                                Spacer(minLength: 0)
                            }
                        }
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: messages.last?.content) { _, _ in
                if let lastMessage = messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }

    private func isLastAssistantMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        return messages.last(where: { $0.role == .assistant })?.id == message.id
    }

    private enum UIConstants {
        // 70% of 800px window width minus padding
        static let bubbleMaxWidth: CGFloat = 540
    }
}
