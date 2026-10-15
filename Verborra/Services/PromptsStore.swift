import Foundation

// MARK: - PromptsStore (T015, T042-T046)

@Observable
final class PromptsStore {
    private(set) var prompts: [SystemPrompt] = []
    private let fileURL: URL
    private let log = DiagnosticLogger.logger(for: .settings)

    private static let dataVersionKey = "promptsDataVersion"
    private static let currentDataVersion = 4

    var defaultPrompt: SystemPrompt {
        prompts.first(where: { $0.isDefault }) ?? prompts.first ?? SystemPrompt.makeDefault()
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Verborra", isDirectory: true)
        self.fileURL = appDir.appendingPathComponent("prompts.json")

        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        load()
        migrateIfNeeded()
        // Fresh install: seed the default prompt before adding the other system prompts,
        // otherwise ensureSystemPrompts fills the list and no prompt is marked default.
        let loadedCount = prompts.count
        if prompts.isEmpty {
            prompts = [SystemPrompt.makeDefault()]
        }
        ensureSystemPrompts()
        if prompts.count != loadedCount { save() }
    }

    // For testing
    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
        migrateIfNeeded()
        let loadedCount = prompts.count
        if prompts.isEmpty {
            prompts = [SystemPrompt.makeDefault()]
        }
        ensureSystemPrompts()
        if prompts.count != loadedCount { save() }
    }

    // MARK: - Migration v1 → v2 → v3 (T042, 013-FR-009a/FR-009b)

    // swiftlint:disable:next cyclomatic_complexity - data migrations v1→v4, pre-existing (013); splitting them risks user data
    private func migrateIfNeeded() {
        let version = UserDefaults.standard.integer(forKey: Self.dataVersionKey)
        guard version < Self.currentDataVersion else { return }

        // ---- v1 → v2: extract per-prompt languages into global settings, mark default as system prompt.
        if version < 2 {
            // Read v1 data with voiceLanguage/textLanguage using MigrationPrompt
            var migrationPrompts: [MigrationPrompt] = []
            if FileManager.default.fileExists(atPath: fileURL.path),
               let data = try? Data(contentsOf: fileURL) {
                migrationPrompts = (try? JSONDecoder().decode([MigrationPrompt].self, from: data)) ?? []
            }

            // Migrate voice/text language from default prompt to global settings.
            if let defaultMigration = migrationPrompts.first(where: { $0.isDefault }) ?? migrationPrompts.first {
                if let voiceLang = defaultMigration.voiceLanguage, !voiceLang.isEmpty {
                    UserDefaults.standard.set(voiceLang, forKey: "globalVoiceLanguage")
                }
                if let textLang = defaultMigration.textLanguage, !textLang.isEmpty {
                    UserDefaults.standard.set(textLang, forKey: "globalTextLanguage")
                }
            }

            // Replace "Стандартный" (or first prompt) with the simple-voice-to-text system prompt.
            let language = LocalizationManager.shared.currentLanguage
            let definition = SystemPromptDefinition.simpleVoiceToText

            let targetIndex = prompts.firstIndex(where: { $0.name == "Стандартный" })
                ?? prompts.firstIndex(where: { $0.isDefault })
                ?? (prompts.isEmpty ? nil : 0)

            if let idx = targetIndex {
                let wasDefault = prompts[idx].isDefault
                prompts[idx] = SystemPrompt(
                    id: prompts[idx].id,
                    name: definition.name(for: language),
                    content: definition.content(for: language),
                    isDefault: wasDefault,
                    isSystem: true,
                    systemId: definition.id,
                    answerQuestionsInFirstMessage: false
                )
            }
        }

        // ---- v2 → v3: FR-009a force-rewrite simple-voice-to-text content/name
        // to the new simplified formulation in the user's current locale, and reset
        // the read-only prompt's `answerQuestionsInFirstMessage` to `false`.
        // Any previous user customizations of this built-in prompt are discarded.
        if version < 3 {
            let language = LocalizationManager.shared.currentLanguage
            let definition = SystemPromptDefinition.simpleVoiceToText
            if let idx = prompts.firstIndex(where: { $0.isSystem && $0.systemId == definition.id }) {
                let previousLength = prompts[idx].content.count
                prompts[idx].name = definition.name(for: language)
                prompts[idx].content = definition.content(for: language)
                prompts[idx].answerQuestionsInFirstMessage = false
                log.info("Migrated simple-voice-to-text content to v3", metadata: [
                    "language": language.rawValue,
                    "previousContentLength": "\(previousLength)"
                ])
            }
        }

        // ---- v3 → v4: re-sync the stored name/content for every system prompt
        // from the registry. Needed because the English display name was
        // renamed ("Simple Voice To Text" → "Speech To Text") and the stored
        // `name` field is otherwise frozen at install time. User customizations
        // can never apply here since system prompts are read-only.
        if version < 4 {
            let language = LocalizationManager.shared.currentLanguage
            for i in prompts.indices where prompts[i].isSystem {
                guard let systemId = prompts[i].systemId,
                      let definition = SystemPromptRegistry.definition(for: systemId) else { continue }
                prompts[i].name = definition.name(for: language)
                prompts[i].content = definition.content(for: language)
            }
            log.info("Re-synced system-prompt names/content from registry (v4)", metadata: [
                "language": language.rawValue
            ])
        }

        UserDefaults.standard.set(Self.currentDataVersion, forKey: Self.dataVersionKey)
        save()
    }

    // MARK: - System Prompts Management (T043, T044)

    /// Update system prompts' name/content when UI language changes
    func updateSystemPrompts(for language: SupportedLanguage) {
        var changed = false
        for i in prompts.indices where prompts[i].isSystem {
            guard let systemId = prompts[i].systemId,
                  let definition = SystemPromptRegistry.definition(for: systemId) else { continue }
            prompts[i].name = definition.name(for: language)
            prompts[i].content = definition.content(for: language)
            changed = true
        }
        if changed { save() }
    }

    /// Ensure all registered system prompts exist (T044)
    func ensureSystemPrompts() {
        let existingIds = Set(prompts.compactMap { $0.isSystem ? $0.systemId : nil })
        let language = LocalizationManager.shared.currentLanguage

        for definition in SystemPromptRegistry.all where !existingIds.contains(definition.id) {
            let prompt = SystemPrompt(
                name: definition.name(for: language),
                content: definition.content(for: language),
                isDefault: false,
                isSystem: true,
                systemId: definition.id
            )
            prompts.append(prompt)
        }
    }

    // MARK: - CRUD (T046: system prompt protection)

    func addPrompt(_ prompt: SystemPrompt) {
        let newPrompt = prompt
        if newPrompt.isDefault {
            clearDefaults()
        }
        prompts.append(newPrompt)
        save()
    }

    func updatePrompt(_ prompt: SystemPrompt) {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else { return }
        // FR-009b: read-only prompts (currently simple-voice-to-text) cannot be modified.
        guard !prompts[index].isReadOnly else { return }
        var updated = prompt
        if updated.isDefault {
            clearDefaults()
            updated.isDefault = true
        }
        prompts[index] = updated
        save()
    }

    func deletePrompt(_ id: UUID) {
        // FR-009b: read-only prompts cannot be deleted.
        guard let prompt = prompts.first(where: { $0.id == id }), !prompt.isReadOnly else { return }

        let wasDefault = prompt.isDefault
        prompts.removeAll { $0.id == id }
        if wasDefault, !prompts.isEmpty {
            prompts[0].isDefault = true
        }
        if prompts.isEmpty {
            prompts = [SystemPrompt.makeDefault()]
        }
        save()
    }

    func setDefault(_ id: UUID) {
        clearDefaults()
        if let index = prompts.firstIndex(where: { $0.id == id }) {
            prompts[index].isDefault = true
        }
        save()
    }

    /// Updates only the `answerQuestionsInFirstMessage` toggle for the given
    /// prompt. Unlike `updatePrompt(_:)`, this method bypasses the
    /// `isReadOnly` guard: the read-only protection covers `name` and
    /// `content` (FR-009b) but the per-prompt answer toggle is a behavioural
    /// preference the user is allowed to set on any prompt, including
    /// built-in ones. No-op if the value is unchanged.
    func setAnswerInFirstMessage(promptID: UUID, value: Bool) {
        guard let index = prompts.firstIndex(where: { $0.id == promptID }) else { return }
        guard prompts[index].answerQuestionsInFirstMessage != value else { return }
        prompts[index].answerQuestionsInFirstMessage = value
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            prompts = try JSONDecoder().decode([SystemPrompt].self, from: data)
        } catch {
            prompts = []
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(prompts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silent failure — user will see stale data on next launch
        }
    }

    private func clearDefaults() {
        for i in prompts.indices {
            prompts[i].isDefault = false
        }
    }
}
