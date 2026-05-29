import Foundation

// MARK: - LLMModel (T010)

enum LLMModel: String, Codable, CaseIterable {
    case gpt4oMini = "gpt-4o-mini"
    case gpt41Mini = "gpt-4.1-mini"
    case gpt5Nano = "gpt-5-nano"
    case gpt5Mini = "gpt-5-mini"
    case gpt51 = "gpt-5.1"
    case gpt52 = "gpt-5.2"
    case gpt54Nano = "gpt-5.4-nano"
    case gpt54Mini = "gpt-5.4-mini"
    case gpt54 = "gpt-5.4"
    case gpt54Pro = "gpt-5.4-pro"
    case gpt55 = "gpt-5.5"
    case gpt55Pro = "gpt-5.5-pro"

    var displayName: String {
        switch self {
        case .gpt4oMini: return "GPT-4o Mini"
        case .gpt41Mini: return "GPT-4.1 Mini"
        case .gpt5Nano: return "GPT-5 Nano"
        case .gpt5Mini: return "GPT-5 Mini"
        case .gpt51: return "GPT-5.1"
        case .gpt52: return "GPT-5.2"
        case .gpt54Nano: return "GPT-5.4 Nano"
        case .gpt54Mini: return "GPT-5.4 Mini"
        case .gpt54: return "GPT-5.4"
        case .gpt54Pro: return "GPT-5.4 Pro"
        case .gpt55: return "GPT-5.5"
        case .gpt55Pro: return "GPT-5.5 Pro"
        }
    }

    var infoDescription: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .gpt4oMini: return l10n.string("model.llm.gpt4oMini.info")
        case .gpt41Mini: return l10n.string("model.llm.gpt41Mini.info")
        case .gpt5Nano: return l10n.string("model.llm.gpt5Nano.info")
        case .gpt5Mini: return l10n.string("model.llm.gpt5Mini.info")
        case .gpt51: return l10n.string("model.llm.gpt51.info")
        case .gpt52: return l10n.string("model.llm.gpt52.info")
        case .gpt54Nano: return l10n.string("model.llm.gpt54Nano.info")
        case .gpt54Mini: return l10n.string("model.llm.gpt54Mini.info")
        case .gpt54: return l10n.string("model.llm.gpt54.info")
        case .gpt54Pro: return l10n.string("model.llm.gpt54Pro.info")
        case .gpt55: return l10n.string("model.llm.gpt55.info")
        case .gpt55Pro: return l10n.string("model.llm.gpt55Pro.info")
        }
    }

    static var `default`: LLMModel { .gpt51 }

    /// `true` if the model accepts arbitrary `temperature` values in the
    /// Chat Completions request. OpenAI's GPT-5 reasoning tier (the *-nano
    /// and *-mini variants) only accepts the default value (1.0) and
    /// returns 400 (`unsupported_value`) for anything else — confirmed
    /// for `gpt-5-nano` and `gpt-5-mini` in production logs (see
    /// `verborra-2026-05-29T13.jsonl`). The same heuristic is applied to
    /// the gpt-5.4 family pending live confirmation:
    /// - `gpt-5.4-nano`, `gpt-5.4-mini` → `false` (reasoning-tier convention)
    /// - flagship and *-pro variants → `true` (accept arbitrary temperature)
    ///
    /// When `false`, callers (`StreamingFormattingService.buildRequest`,
    /// `FormattingService` builders) MUST omit the `temperature` key from
    /// the request body entirely.
    var supportsTemperature: Bool {
        switch self {
        case .gpt5Nano, .gpt5Mini, .gpt54Nano, .gpt54Mini:
            return false
        case .gpt4oMini, .gpt41Mini, .gpt51, .gpt52, .gpt54, .gpt54Pro, .gpt55, .gpt55Pro:
            return true
        }
    }
}
