import Foundation

// MARK: - STTModel (T009)

enum STTModel: String, Codable, CaseIterable {
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case whisper1 = "whisper-1"

    var displayName: String {
        switch self {
        case .gpt4oMiniTranscribe: return "GPT-4o Mini Transcribe"
        case .gpt4oTranscribe: return "GPT-4o Transcribe"
        case .whisper1: return "Whisper-1"
        }
    }

    var infoDescription: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .gpt4oMiniTranscribe: return l10n.string("model.stt.gpt4oMiniTranscribe.info")
        case .gpt4oTranscribe: return l10n.string("model.stt.gpt4oTranscribe.info")
        case .whisper1: return l10n.string("model.stt.whisper1.info")
        }
    }

    static var `default`: STTModel { .gpt4oMiniTranscribe }
}
