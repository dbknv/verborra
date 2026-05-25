import Foundation

// MARK: - RecordingState

enum RecordingState: Equatable {
    case idle
    case recording(duration: TimeInterval, remaining: TimeInterval)
    case transcribing
    case formatting
    case error(RecordingError)
}

// MARK: - RecordingError

enum RecordingError: Equatable {
    case microphoneNotAvailable
    case microphonePermissionDenied
    case apiKeyNotConfigured
    case networkUnavailable
    case transcriptionFailed(String)
    case formattingFailed(String)
    case silenceDetected
    case recordingTooLong
    case fileSizeLimitReached
    case accessibilityNotGranted
    case pasteTargetUnavailable
    case emptyTranscription
    case notRecording
    case deviceDisconnected(String?)
    case deviceFormatChanged(String?)
    case deviceNotResponding
    case deviceUnavailable
}

extension RecordingError: LocalizedError {
    var errorDescription: String? {
        let l10n = LocalizationManager.shared
        switch self {
        case .microphoneNotAvailable:
            return l10n.string("error.micNotAvailable")
        case .microphonePermissionDenied:
            return l10n.string("error.micPermissionDenied")
        case .apiKeyNotConfigured:
            return l10n.string("error.apiKeyNotConfigured")
        case .networkUnavailable:
            return l10n.string("error.networkUnavailable")
        case .transcriptionFailed(let message):
            return l10n.string("error.transcriptionFailed", args: message)
        case .formattingFailed(let message):
            return l10n.string("error.formattingFailed", args: message)
        case .silenceDetected:
            return l10n.string("error.silenceDetected")
        case .recordingTooLong:
            return l10n.string("error.recordingTooLong")
        case .fileSizeLimitReached:
            return l10n.string("error.fileSizeLimit")
        case .accessibilityNotGranted:
            return l10n.string("error.accessibilityNotGranted")
        case .pasteTargetUnavailable:
            return l10n.string("error.pasteTargetUnavailable")
        case .emptyTranscription:
            return l10n.string("error.silenceDetected")
        case .notRecording:
            return l10n.string("error.notRecording")
        case .deviceDisconnected(let name):
            return l10n.string("error.deviceDisconnected", args: name ?? "Unknown")
        case .deviceFormatChanged(let name):
            return l10n.string("error.deviceFormatChanged", args: name ?? "Unknown")
        case .deviceNotResponding:
            return l10n.string("error.deviceNotResponding")
        case .deviceUnavailable:
            return l10n.string("error.deviceUnavailable")
        }
    }
}
