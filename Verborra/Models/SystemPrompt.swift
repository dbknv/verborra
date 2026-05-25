import Foundation

// MARK: - SystemPrompt (T008, T040)

struct SystemPrompt: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var isDefault: Bool
    var isSystem: Bool
    var systemId: String?

    init(
        id: UUID = UUID(),
        name: String,
        content: String,
        isDefault: Bool = false,
        isSystem: Bool = false,
        systemId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.isDefault = isDefault
        self.isSystem = isSystem
        self.systemId = systemId
    }

    // MARK: - Codable (backward compatibility with v1 format)

    enum CodingKeys: String, CodingKey {
        case id, name, content, isDefault, isSystem, systemId
        case voiceLanguage, textLanguage // v1 fields — read-only for migration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        content = try container.decode(String.self, forKey: .content)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        isSystem = try container.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false
        systemId = try container.decodeIfPresent(String.self, forKey: .systemId)
        // voiceLanguage/textLanguage are intentionally not stored — read via MigrationPrompt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(content, forKey: .content)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(isSystem, forKey: .isSystem)
        try container.encodeIfPresent(systemId, forKey: .systemId)
        // voiceLanguage/textLanguage are NOT written in v2
    }

    /// Returns content localized for the given language (for system prompts),
    /// or the stored content (for user prompts).
    func contentForLanguage(_ language: SupportedLanguage) -> String {
        guard isSystem, let systemId,
              let definition = SystemPromptRegistry.definition(for: systemId) else {
            return content
        }
        return definition.content(for: language)
    }

    // MARK: - Factory

    static func makeDefault() -> SystemPrompt {
        let language = LocalizationManager.shared.currentLanguage
        let definition = SystemPromptDefinition.simpleVoiceToText
        return SystemPrompt(
            name: definition.name(for: language),
            content: definition.content(for: language),
            isDefault: true,
            isSystem: true,
            systemId: "simple-voice-to-text"
        )
    }
}

// MARK: - MigrationPrompt (T042)

/// Helper struct to read v1 fields (voiceLanguage, textLanguage) during migration
struct MigrationPrompt: Codable {
    let id: UUID
    var name: String
    var content: String
    var isDefault: Bool
    var voiceLanguage: String?
    var textLanguage: String?
    var isSystem: Bool?
    var systemId: String?
}
