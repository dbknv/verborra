import SwiftUI

// MARK: - OverlayContentView

struct OverlayContentView: View {
    @Bindable var viewModel: RecordingViewModel

    private let permissionManager = PermissionManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Group {
                if permissionManager.microphoneStatus != .granted {
                    RecordingView(viewModel: viewModel)
                } else if viewModel.windowPhase == .postProcessing,
                          let chatSession = viewModel.chatSession,
                          !chatSession.messages.isEmpty {
                    ChatView(
                        messages: chatSession.messages,
                        onToggleCollapse: { id in
                            if let msg = chatSession.messages.first(where: { $0.id == id }) {
                                msg.isCollapsed.toggle()
                            }
                        },
                        onCopyMessage: { id in
                            if let msg = chatSession.messages.first(where: { $0.id == id }) {
                                viewModel.pasteService.copyToClipboard(msg.content)
                            }
                        },
                        onStartEdit: { id in
                            if let msg = chatSession.messages.first(where: { $0.id == id }) {
                                msg.isEditing = true
                            }
                        },
                        onConfirmEdit: { id, text in
                            if let msg = chatSession.messages.first(where: { $0.id == id }) {
                                msg.content = text
                                msg.isEditing = false
                            }
                        },
                        onCancelEdit: { id in
                            if let msg = chatSession.messages.first(where: { $0.id == id }) {
                                msg.isEditing = false
                            }
                        }
                    )
                } else {
                    RecordingView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Input field (postProcessing only)
            if viewModel.windowPhase == .postProcessing {
                InputFieldView(
                    text: $viewModel.inputText,
                    inputRecordingState: viewModel.inputRecordingState,
                    audioLevel: viewModel.audioLevel,
                    isEnabled: viewModel.chatSession?.lastAssistantMessage?.isStreaming != true,
                    onSend: { viewModel.sendMessage() },
                    onStartVoice: { viewModel.startInputRecording() },
                    onStopVoice: { viewModel.stopInputRecording() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Control Bar (bottom)
            ControlBarView(
                viewModel: viewModel,
                hasAccessibility: permissionManager.accessibilityStatus == .granted
            )
        }
        .background(Color(hex: 0xE9E9E9))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if viewModel.windowPhase == .postProcessing {
                viewModel.overlayManager.updateHeight(newHeight)
            }
        }
        .onAppear {
            permissionManager.startMonitoring()
        }
        .onDisappear {
            viewModel.cleanup()  // T025: FR-020 — stop timers and recording
            permissionManager.stopMonitoring()
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
