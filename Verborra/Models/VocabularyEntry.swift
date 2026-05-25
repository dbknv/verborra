import Foundation

// MARK: - VocabularyEntry (012-vocabularies)

/// Запись словаря: целевое слово и набор альтернативных написаний.
/// Используется для автозамены в LLM-промптах.
struct VocabularyEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var targetWord: String
    var alternatives: [String]
    let createdAt: Date

    init(id: UUID = UUID(), targetWord: String, alternatives: [String], createdAt: Date = Date()) {
        self.id = id
        self.targetWord = targetWord
        self.alternatives = alternatives
        self.createdAt = createdAt
    }

    // MARK: - Validation

    /// Проверяет, что targetWord не пустой после trim.
    var isTargetWordValid: Bool {
        !targetWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Проверяет, что есть хотя бы одна непустая альтернатива,
    /// и ни одна альтернатива не совпадает с целевым словом.
    var areAlternativesValid: Bool {
        let trimmedTarget = targetWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let validAlternatives = alternatives
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != trimmedTarget }
        return !validAlternatives.isEmpty
    }

    /// Полная валидность записи.
    var isValid: Bool {
        isTargetWordValid && areAlternativesValid
    }

    /// Возвращает очищенную копию (trimmed targetWord и alternatives без пустых/дубликатов).
    var sanitized: VocabularyEntry {
        let trimmedTarget = targetWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlternatives = alternatives
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != trimmedTarget }
        return VocabularyEntry(
            id: id,
            targetWord: trimmedTarget,
            alternatives: cleanAlternatives,
            createdAt: createdAt
        )
    }
}
