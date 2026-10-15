import Foundation

// MARK: - StartKind (spec 015, US9)

/// Why the recording is starting: a fresh start, or a microphone switch during recording.
enum StartKind: Equatable {
    /// Hotkey, Start button, Retry, auto-record.
    case initial
    /// Microphone switch during recording; display name of the target microphone.
    case switching(to: String)
}

// MARK: - RecordingState

enum RecordingState: Equatable {
    case idle
    /// spec 015 (US2): microphone start in progress; `attempt` is 1 or 2 (one automatic retry).
    case starting(attempt: Int)
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
    /// spec 015 (US2, US9): both start attempts failed; retryable. `deviceName` is the microphone's display name.
    case recordingStartFailed(StartFailureReason, deviceName: String)
    /// spec 015 (FR-040): OpenAI rejected the selected model for this account. Not retried, no fallback model.
    case modelUnavailable(modelName: String, kind: ModelKind)
}

// MARK: - ModelKind

enum ModelKind: Equatable {
    case speechToText
    case text
}

// MARK: - Model availability (spec 015, T087)

extension RecordingError {
    /// `true` when OpenAI says the model doesn't exist or isn't available to this account:
    /// any 404, or a 400/403 whose `error.code` is `model_not_found` / `model_not_available`.
    static func isModelUnavailable(status: Int, body: String) -> Bool {
        if status == 404 { return true }
        guard status == 400 || status == 403 else { return false }
        return ["model_not_found", "model_not_available"].contains(openAIError(in: body).code ?? "")
    }

    var isModelUnavailable: Bool {
        if case .modelUnavailable = self { return true }
        return false
    }

    /// `error.code` and `error.message` from an OpenAI error body, if present.
    static func openAIError(in body: String) -> (code: String?, message: String?) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return (nil, nil)
        }
        return (error["code"] as? String, error["message"] as? String)
    }
}

// MARK: - StartFailureReason (spec 015, T044)

/// Why the microphone didn't start (contracts/recording-start.md).
enum StartFailureReason: Equatable {
    case timeout(step: String)
    case formatMismatch(node: Double, hardware: Double)
    case audioException(name: String, reason: String)
    case engineStartFailed(String)
    case deviceUnavailable

    /// Short, non-localized reason shown in brackets in the error message and written to logs.
    var shortDescription: String {
        switch self {
        case .timeout(let step):
            return "timeout: \(step)"
        case .formatMismatch(let node, let hardware):
            return "format \(Int(node)) Hz ≠ \(Int(hardware)) Hz"
        case .audioException(let name, _):
            return name
        case .engineStartFailed(let message):
            return message
        case .deviceUnavailable:
            return "device unavailable"
        }
    }
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
        case .recordingStartFailed(let reason, let deviceName):
            return l10n.string("error.recordingStartFailed", args: deviceName, reason.shortDescription)
        case .modelUnavailable(let modelName, .text):
            return l10n.string("error.modelUnavailable.text", args: modelName)
        case .modelUnavailable(let modelName, .speechToText):
            return l10n.string("error.modelUnavailable.stt", args: modelName)
        }
    }
}
