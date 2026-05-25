import SwiftUI

// MARK: - ChatBubbleView

struct ChatBubbleView: View {
    let message: ChatMessage
    let isLastAssistant: Bool
    let onToggleCollapse: () -> Void
    let onCopy: () -> Void
    var onStartEdit: (() -> Void)?
    var onConfirmEdit: ((String) -> Void)?
    var onCancelEdit: (() -> Void)?

    @State private var editText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header with role label and actions
            HStack {
                roleLabel

                Spacer()

                // Edit button (pencil) — only for last assistant message
                if isLastAssistant && !message.isStreaming && !message.isEditing {
                    Button(action: {
                        editText = message.content
                        onStartEdit?()
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0x9A9A9A))
                    }
                    .buttonStyle(.plain)
                }

                // Copy button for all messages
                if !message.content.isEmpty && !message.isStreaming {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0x9A9A9A))
                    }
                    .buttonStyle(.plain)
                }

                // Collapse/Expand for system and transcription
                if message.role == .system || message.role == .transcription {
                    Button(action: onToggleCollapse) {
                        Image(systemName: message.isCollapsed ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0x9A9A9A))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Content — no scroll, height adapts to content
            if !message.isCollapsed {
                if message.isEditing {
                    editingView
                } else {
                    contentView
                }
            }
        }
        .padding(10)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            editText = message.content
        }
    }

    // MARK: - Bubble Background

    private var bubbleBackground: Color {
        Color(hex: 0xF4F4F4)
    }

    // MARK: - Role Label

    @ViewBuilder
    private var roleLabel: some View {
        switch message.role {
        case .system:
            Label("System", systemImage: "gearshape.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: 0x9A9A9A))
        case .transcription:
            Label("Transcription", systemImage: "waveform.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: 0x9A9A9A))
        case .user:
            Label("You", systemImage: "person.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: 0x9A9A9A))
        case .assistant:
            Label("AI", systemImage: "sparkles.rectangle.stack.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: 0x9A9A9A))
        }
    }

    // MARK: - Content (no scroll — height adapts to content)

    @ViewBuilder
    private var contentView: some View {
        Text(message.content)
            .font(.system(size: 14))
            .foregroundColor(Color(hex: 0x2F2F2F))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)

        if message.isStreaming {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("...")
                    .foregroundColor(Color(hex: 0x9A9A9A))
            }
        }
    }

    // MARK: - Editing View

    private var editingView: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField("", text: $editText, axis: .vertical)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(action: {
                    onCancelEdit?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0x9A9A9A))
                        .padding(6)
                        .background(Color(hex: 0xDCDCDC))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    onConfirmEdit?(editText)
                }) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color(hex: 0x2C2C2C))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
