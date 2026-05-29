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
        case .gpt4oMini:
            return 128_000
        case .gpt41Mini,
             .gpt5Nano, .gpt5Mini, .gpt51, .gpt52,
             .gpt54Nano, .gpt54Mini, .gpt54, .gpt54Pro,
             .gpt55, .gpt55Pro:
            return 1_048_576
        }
    }

    /// Бюджет сообщений = 80% лимита − токены системного промпта
    static func messageBudget(for model: LLMModel, systemPromptTokens: Int) -> Int {
        let budget = Int(Double(contextLimit(for: model)) * 0.8)
        return max(0, budget - systemPromptTokens)
    }
}
