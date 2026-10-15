import Foundation

// MARK: - ModelSelectionMigrator (spec 015, T030)

/// Переводит пользователей с удалённых моделей на новые значения по умолчанию (FR-037).
/// Молча, без UI (FR-038) — только запись в лог. Идемпотентен: повторный запуск ничего не меняет.
/// Вызывается один раз за запуск, до того как кто-либо прочитал настройки моделей.
enum ModelSelectionMigrator {
    enum Kind: String, Equatable {
        case stt
        case llm
    }

    enum Reason: String, Equatable {
        /// Сохранено значение, которого больше нет (удалённая или неизвестная модель).
        case removed
        /// Значение не сохранено, но пользователь уже проходил онбординг —
        /// он неявно пользовался прежним значением по умолчанию.
        case inheritedDefault
    }

    struct Migration: Equatable {
        let kind: Kind
        let old: String
        let new: String
        let reason: Reason
    }

    static let sttKey = "selectedSTTModelRawValue"
    static let llmKey = "selectedLLMModelRawValue"
    static let onboardingCompletedKey = "onboardingCompleted"

    @discardableResult
    static func run(
        defaults: UserDefaults = .standard,
        log: DiagnosticLogger? = DiagnosticLogger.logger(for: .lifecycle)
    ) -> [Migration] {
        let isExistingUser = defaults.object(forKey: onboardingCompletedKey) != nil
        let selections = [
            Selection(kind: .stt, key: sttKey, isCurrent: { STTModel(rawValue: $0) != nil },
                      newDefault: STTModel.default.rawValue, legacyDefault: STTModel.legacyDefaultRawValue),
            Selection(kind: .llm, key: llmKey, isCurrent: { LLMModel(rawValue: $0) != nil },
                      newDefault: LLMModel.default.rawValue, legacyDefault: LLMModel.legacyDefaultRawValue)
        ]
        let migrations = selections.compactMap {
            migrate($0, isExistingUser: isExistingUser, defaults: defaults)
        }

        for migration in migrations {
            log?.info("Model selection migrated", metadata: [
                "kind": migration.kind.rawValue,
                "old": migration.old,
                "new": migration.new,
                "reason": migration.reason.rawValue
            ])
        }
        return migrations
    }

    // MARK: - Private

    /// One saved model selection and its current catalog.
    private struct Selection {
        let kind: Kind
        let key: String
        let isCurrent: (String) -> Bool
        let newDefault: String
        let legacyDefault: String
    }

    private static func migrate(_ selection: Selection, isExistingUser: Bool, defaults: UserDefaults) -> Migration? {
        if let saved = defaults.string(forKey: selection.key) {
            guard !selection.isCurrent(saved) else { return nil }
            defaults.set(selection.newDefault, forKey: selection.key)
            return Migration(kind: selection.kind, old: saved, new: selection.newDefault, reason: .removed)
        }
        guard isExistingUser else { return nil }
        defaults.set(selection.newDefault, forKey: selection.key)
        return Migration(kind: selection.kind, old: selection.legacyDefault, new: selection.newDefault, reason: .inheritedDefault)
    }
}
