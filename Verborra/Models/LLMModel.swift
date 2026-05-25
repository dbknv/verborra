import Foundation

// MARK: - LLMModel (T010)

enum LLMModel: String, Codable, CaseIterable {
    case gpt41Nano = "gpt-4.1-nano"
    case gpt4oMini = "gpt-4o-mini"
    case gpt41Mini = "gpt-4.1-mini"
    case gpt5Nano = "gpt-5-nano"
    case gpt5Mini = "gpt-5-mini"
    case gpt51 = "gpt-5.1"
    case gpt52 = "gpt-5.2"
    case gpt53 = "gpt-5.3"

    var displayName: String {
        switch self {
        case .gpt41Nano: return "GPT-4.1 Nano"
        case .gpt4oMini: return "GPT-4o Mini"
        case .gpt41Mini: return "GPT-4.1 Mini"
        case .gpt5Nano: return "GPT-5 Nano"
        case .gpt5Mini: return "GPT-5 Mini"
        case .gpt51: return "GPT-5.1"
        case .gpt52: return "GPT-5.2"
        case .gpt53: return "GPT-5.3"
        }
    }

    var infoDescription: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .gpt41Nano: return l10n.string("model.llm.gpt41Nano.info")
        case .gpt4oMini: return l10n.string("model.llm.gpt4oMini.info")
        case .gpt41Mini: return l10n.string("model.llm.gpt41Mini.info")
        case .gpt5Nano: return l10n.string("model.llm.gpt5Nano.info")
        case .gpt5Mini: return l10n.string("model.llm.gpt5Mini.info")
        case .gpt51: return l10n.string("model.llm.gpt51.info")
        case .gpt52: return l10n.string("model.llm.gpt52.info")
        case .gpt53: return l10n.string("model.llm.gpt53.info")
        }
    }

    static var `default`: LLMModel { .gpt41Nano }
}
