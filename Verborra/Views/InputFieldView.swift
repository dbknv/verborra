import SwiftUI

// MARK: - InputFieldView

struct InputFieldView: View {
    @Binding var text: String
    let inputRecordingState: InputRecordingState
    let audioLevel: Float
    let isEnabled: Bool

    let onSend: () -> Void
    let onStartVoice: () -> Void
    let onStopVoice: () -> Void

    private var isRecording: Bool {
        if case .recording = inputRecordingState { return true }
        return false
    }

    private var isProcessing: Bool {
        inputRecordingState == .processing
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isRecording {
                // Voice recording indicator
                HStack(spacing: 8) {
                    AudioWaveformView(audioLevel: audioLevel)
                        .frame(height: 24)

                    if case .recording(_, let remaining) = inputRecordingState {
                        Text(formatRemaining(remaining))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Color(hex: 0x9A9A9A))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Text input — starts at 1 line, grows up to 5 lines
                TextField("", text: $text, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .disabled(!isEnabled || isProcessing)
            }

            // Action buttons
            if isRecording {
                Button(action: onStopVoice) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: 0x2C2C2C))
                }
                .buttonStyle(.plain)
            } else {
                // Microphone button
                Button(action: onStartVoice) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16))
                        .foregroundColor(isEnabled ? Color(hex: 0x2C2C2C) : Color(hex: 0xACACAC))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled || isProcessing)

                // Send button
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(
                            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isEnabled
                                ? Color(hex: 0xACACAC)
                                : Color(hex: 0x2C2C2C)
                        )
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isEnabled || isProcessing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func formatRemaining(_ remaining: TimeInterval) -> String {
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
