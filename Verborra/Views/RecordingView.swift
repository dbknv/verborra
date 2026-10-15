import SwiftUI

// MARK: - RecordingView

struct RecordingView: View {
    @Bindable var viewModel: RecordingViewModel
    private let l10n = LocalizationManager.shared
    private let permissionManager = PermissionManager.shared

    var body: some View {
        VStack(spacing: 16) {
            if permissionManager.microphoneStatus != .granted {
                noMicrophoneAccessView
            } else {
                switch viewModel.state {
                case .idle:
                    idleView
                case .starting:
                    startingView
                case .recording(let duration, let remaining):
                    recordingView(duration: duration, remaining: remaining)
                case .transcribing:
                    transcribingView
                case .formatting:
                    formattingView
                case .error(let error):
                    errorView(error: error)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .padding(.top, 6)
    }

    // MARK: - States

    private var noMicrophoneAccessView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)

            Text(l10n.string("recording.noMicAccess.title"))
                .font(.headline)
                .foregroundStyle(.primary)

            Text(l10n.string("recording.noMicAccess.description"))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button(l10n.string("recording.noMicAccess.openSettings")) {
                viewModel.openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(l10n.string("recording.idle.hint"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(l10n.string("recording.idle.maxDuration", args: viewModel.settings.maxRecordingDuration.displayName))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func recordingView(duration: TimeInterval, remaining: TimeInterval) -> some View {
        let isWarning = remaining <= 30 && remaining > 0

        return VStack(spacing: 2) {
            AudioWaveformView(audioLevel: viewModel.audioLevel)
                .frame(height: 110)

            Text(formatRemaining(remaining))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isWarning ? Color(hex: 0xD94040) : Color(hex: 0x9A9A9A))

        }
    }

    /// "Starting microphone…", or "Switching to <name>…" during a microphone switch (spec 015, US9).
    private var startingCaption: String {
        if case .switching(let name) = viewModel.startKind {
            return l10n.string("recording.switching", args: name)
        }
        return l10n.string("recording.starting")
    }

    private var startingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(startingCaption)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 110)
    }

    private var transcribingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text(l10n.string("recording.transcribing"))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var formattingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text(l10n.string("recording.formatting"))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(error: RecordingError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)

            Text(error.errorDescription ?? l10n.string("error.unknown"))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            if error == .apiKeyNotConfigured || error.isModelUnavailable {
                Button(l10n.string("recording.error.openSettings")) {
                    viewModel.openSettings()
                }
                .buttonStyle(.borderedProminent)
            }

            if case .microphonePermissionDenied = error {
                Button(l10n.string("recording.error.openSystemSettings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            if case .accessibilityNotGranted = error {
                Button(l10n.string("recording.error.openSystemSettings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            if isRetryableError(error) {
                Button {
                    viewModel.retryFromError()
                } label: {
                    Label(l10n.string("recording.error.retry"), systemImage: "arrow.clockwise.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }

        }
    }

    // MARK: - Helpers

    private func isRetryableError(_ error: RecordingError) -> Bool {
        switch error {
        case .transcriptionFailed, .formattingFailed, .networkUnavailable, .silenceDetected, .emptyTranscription,
             .recordingStartFailed:
            return true
        default:
            return false
        }
    }

    private func formatRemaining(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
