import Foundation

enum ProcessingError: LocalizedError {
    case apiKeyMissing
    case modelNotSupported(String)
    case transcriptionFailed(Error)
    case formattingFailed(Error)

    var errorDescription: String? {
        let l10n = LocalizationManager.shared
        switch self {
        case .apiKeyMissing:
            return l10n.string("error.apiKeyNotConfigured")
        case .modelNotSupported(let model):
            return l10n.string("error.modelNotSupported", args: model)
        case .transcriptionFailed(let error):
            return l10n.string("error.transcriptionFailed", args: error.localizedDescription)
        case .formattingFailed(let error):
            return l10n.string("error.formattingFailed", args: error.localizedDescription)
        }
    }
}
