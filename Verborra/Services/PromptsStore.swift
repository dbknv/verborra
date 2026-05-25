import Foundation

// MARK: - PromptsStore (T015, T042-T046)

@Observable
final class PromptsStore {
    private(set) var prompts: [SystemPrompt] = []
    private let fileURL: URL
    private let log = DiagnosticLogger.logger(for: .settings)

    private static let dataVersionKey = "promptsDataVersion"
    private static let currentDataVersion = 2

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
        ensureSystemPrompts()

        if prompts.isEmpty {
            prompts = [SystemPrompt.makeDefault()]
            save()
        }
    }

    // For testing
    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
        migrateIfNeeded()
        ensureSystemPrompts()
        if prompts.isEmpty {
            prompts = [SystemPrompt.makeDefault()]
            save()
        }
    }

    // MARK: - Migration v1 → v2 (T042)

    private func migrateIfNeeded() {
        let version = UserDefaults.standard.integer(forKey: Self.dataVersionKey)
        guard version < Self.currentDataVersion else { return }

        // Read v1 data with voiceLanguage/textLanguage using MigrationPrompt
        var migrationPrompts: [MigrationPrompt] = []
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL) {
            migrationPrompts = (try? JSONDecoder().decode([MigrationPrompt].self, from: data)) ?? []
        }

        // Step 1: Migrate voice/text language from default prompt to global settings
        if let defaultMigration = migrationPrompts.first(where: { $0.isDefault }) ?? migrationPrompts.first {
            if let voiceLang = defaultMigration.voiceLanguage, !voiceLang.isEmpty {
                UserDefaults.standard.set(voiceLang, forKey: "globalVoiceLanguage")
            }
            if let textLang = defaultMigration.textLanguage, !textLang.isEmpty {
                UserDefaults.standard.set(textLang, forKey: "globalTextLanguage")
            }
        }

        // Step 2: Replace "Стандартный" (or first prompt) with system prompt
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
                systemId: "simple-voice-to-text"
            )
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
        // T046: Protect system prompts from user modification
        guard !prompts[index].isSystem else { return }
        var updated = prompt
        if updated.isDefault {
            clearDefaults()
            updated.isDefault = true
        }
        prompts[index] = updated
        save()
    }

    func deletePrompt(_ id: UUID) {
        // T046: Protect system prompts from deletion
        guard let prompt = prompts.first(where: { $0.id == id }), !prompt.isSystem else { return }

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
