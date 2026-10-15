import Foundation

// MARK: - LLMModel (T010, spec 015 T011)

/// Текстовые модели. Порядок case = порядок в списке настроек (FR-030).
enum LLMModel: String, Codable, CaseIterable {
    case gpt52 = "gpt-5.2"
    case gpt54Mini = "gpt-5.4-mini"
    case gpt54 = "gpt-5.4"
    case gpt55 = "gpt-5.5"
    case gpt56Terra = "gpt-5.6-terra"
    case gpt56Sol = "gpt-5.6-sol"
    case gpt6Luna = "gpt-6-luna"
    case gpt6Sol = "gpt-6-sol"
    case gpt61Sol = "gpt-6.1-sol"
    case gpt6Astra = "gpt-6-astra"

    var displayName: String {
        switch self {
        case .gpt52: return "GPT-5.2"
        case .gpt54Mini: return "GPT-5.4 Mini"
        case .gpt54: return "GPT-5.4"
        case .gpt55: return "GPT-5.5"
        case .gpt56Terra: return "GPT-5.6 Terra"
        case .gpt56Sol: return "GPT-5.6 Sol"
        case .gpt6Luna: return "GPT-6 Luna"
        case .gpt6Sol: return "GPT-6 Sol"
        case .gpt61Sol: return "GPT-6.1 Sol"
        case .gpt6Astra: return "GPT-6 Astra"
        }
    }

    var infoDescription: String {
        LocalizationManager.shared.string("model.llm.\(caseName).info")
    }

    static var `default`: LLMModel { .gpt6Luna }

    /// Прежнее значение по умолчанию: пользователи без явного выбора хранили его
    /// неявно, миграция (spec 015, US7) переводит их на новое значение по умолчанию.
    static let legacyDefaultRawValue = "gpt-5.1"

    /// `true`, если модель принимает произвольный `temperature` в Chat Completions.
    /// Значения заданы для каждой модели отдельно (FR-035, research R21) и
    /// подтверждаются живой проверкой из quickstart 5.2. Если `false`, вызывающий код
    /// (`FormattingService`, `StreamingFormattingService.buildRequest`) НЕ отправляет
    /// ключ `temperature` вообще — иначе OpenAI отвечает 400 `unsupported_value`.
    var supportsTemperature: Bool {
        switch self {
        case .gpt52: return true
        case .gpt54Mini: return false
        case .gpt54: return true
        case .gpt55: return true
        case .gpt56Terra: return false
        case .gpt56Sol: return false
        case .gpt6Luna: return false
        case .gpt6Sol: return false
        case .gpt61Sol: return false
        case .gpt6Astra: return false
        }
    }

    /// Минимальный поддерживаемый `reasoning_effort` (research R20); `nil` — ключ не отправляется.
    /// Значения заданы для каждой модели отдельно и подтверждаются quickstart 5.2.
    var reasoningEffort: ReasoningEffort? {
        switch self {
        case .gpt52: return nil
        case .gpt54Mini: return nil
        case .gpt54: return nil
        case .gpt55: return nil
        case .gpt56Terra: return ReasoningEffort.none
        case .gpt56Sol: return ReasoningEffort.none
        case .gpt6Luna: return ReasoningEffort.none
        case .gpt6Sol: return ReasoningEffort.none
        case .gpt61Sol: return .low
        case .gpt6Astra: return .low
        }
    }

    /// Имя case для ключей локализации (`model.llm.<caseName>.info`).
    private var caseName: String { String(describing: self) }
}

// MARK: - ReasoningEffort (spec 015, T012)

enum ReasoningEffort: String {
    case none
    case low
}
