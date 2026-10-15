import Foundation

// MARK: - TokenEstimator

struct TokenEstimator {
    /// Консервативная оценка: 1 токен ≈ 3 символа (для кириллицы/смешанного текста)
    static func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 3)
    }

    /// Лимит контекста для модели (в токенах)
    static func contextLimit(for model: LLMModel) -> Int {
        switch model {
        case .gpt52, .gpt54Mini, .gpt54, .gpt55:
            return 1_048_576
        case .gpt56Terra, .gpt56Sol, .gpt6Luna, .gpt6Sol, .gpt61Sol, .gpt6Astra:
            return 922_000
        }
    }

    /// Бюджет сообщений = 80% лимита − токены системного промпта
    static func messageBudget(for model: LLMModel, systemPromptTokens: Int) -> Int {
        let budget = Int(Double(contextLimit(for: model)) * 0.8)
        return max(0, budget - systemPromptTokens)
    }
}
