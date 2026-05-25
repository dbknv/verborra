import Foundation

// MARK: - PromptEnhancer (012-vocabularies)

/// Формирует итоговый системный промпт, добавляя секции
/// Personal Preferences и Vocabulary Replacements (RFC 2119).
///
/// Порядок: basePrompt → Response Language → Personal Preferences → Vocabulary Replacements
struct PromptEnhancer {
    private let log = DiagnosticLogger.logger(for: .vocabulary)

    /// Формирует полный системный промпт.
    /// - Parameters:
    ///   - basePrompt: Основной системный промпт (из Prompts)
    ///   - textLanguage: Язык ответа
    ///   - vocabularyEntries: Записи словаря (пустой массив = секция не добавляется)
    ///   - personalPreferences: Текст персональных настроек (пустая строка = секция не добавляется)
    /// - Returns: Итоговый системный промпт
    func enhance(
        basePrompt: String,
        textLanguage: SupportedLanguage,
        vocabularyEntries: [VocabularyEntry],
        personalPreferences: String
    ) -> String {
        // Response Language (всегда присутствует)
        var result = "\(basePrompt)\n\n## Response Language\n\n"
        result += "You MUST respond in the following language: \(textLanguage.displayName).\n"
        result += "You MUST NOT use any other language in your response, even if the user's input is in a different language. "
        result += "If the input language differs from the response language, translate the content accordingly."

        // Personal Preferences (если не пусто)
        let trimmedPreferences = personalPreferences.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPreferences.isEmpty {
            log.info("Personal Preferences section added to prompt")
            log.debug("Personal Preferences content", metadata: ["text": String(trimmedPreferences.prefix(500))])
            result += "\n\n## Personal Preferences\n\n"
            result += "You MUST follow the user's personal preferences listed below in every response. "
            result += "You MUST NOT deviate from these rules.\n\n"
            result += trimmedPreferences
        }

        // Vocabulary Replacements (если есть записи)
        if !vocabularyEntries.isEmpty {
            log.info("Vocabulary Replacements section added to prompt", metadata: ["entriesCount": "\(vocabularyEntries.count)"])
            result += "\n\n## Vocabulary Replacements\n\n"
            result += "You MUST use the exact \"Target Word\" in your response whenever the user's input "
            result += "contains any of the listed alternatives. You MUST NOT use the alternative spelling "
            result += "in your output — replace it with the target word.\n\n"
            result += "| Target Word | Alternatives |\n"
            result += "|-------------|-------------|\n"
            for entry in vocabularyEntries {
                let alternatives = entry.alternatives.joined(separator: ", ")
                result += "| \(entry.targetWord) | \(alternatives) |\n"
            }
            log.debug("Vocabulary Replacements table generated", metadata: [
                "entries": vocabularyEntries.map { "\($0.targetWord): \($0.alternatives.joined(separator: ", "))" }.joined(separator: "; ")
            ])
        }

        return result
    }
}
