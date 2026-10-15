import Foundation

// MARK: - STTModel (T009, spec 015 T013)

enum STTModel: String, Codable, CaseIterable {
    case gptTranscribe = "gpt-transcribe"

    var displayName: String {
        switch self {
        case .gptTranscribe: return "GPT Transcribe"
        }
    }

    var infoDescription: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .gptTranscribe: return l10n.string("model.stt.gptTranscribe.info")
        }
    }

    static var `default`: STTModel { .gptTranscribe }

    /// Прежнее значение по умолчанию (см. `LLMModel.legacyDefaultRawValue`).
    static let legacyDefaultRawValue = "gpt-4o-mini-transcribe"

    /// Как модель принимает язык распознавания в multipart-запросе.
    enum LanguageField {
        /// `language=<code>`
        case singular
        /// `languages[]=<code>`
        case languagesArray
    }

    var languageField: LanguageField {
        switch self {
        case .gptTranscribe: return .languagesArray
        }
    }
}
