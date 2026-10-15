import Foundation

// MARK: - SystemPrompt (T008, T040, 013-extended)

struct SystemPrompt: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var isDefault: Bool
    var isSystem: Bool
    var systemId: String?
    /// Controls whether the model is allowed to answer questions that appear inside
    /// the FIRST voice-transcribed message of a chat session. When `false`, the
    /// `DoNotAnswerInstruction` is injected into the system prompt for that single turn.
    /// Has no effect on subsequent chat messages. Default: `false`.
    var answerQuestionsInFirstMessage: Bool

    /// True for built-in prompts that the user is not allowed to edit or delete via UI.
    /// Currently only the `simple-voice-to-text` system prompt is read-only.
    var isReadOnly: Bool {
        isSystem && systemId == SystemPromptDefinition.simpleVoiceToText.id
    }

    init(
        id: UUID = UUID(),
        name: String,
        content: String,
        isDefault: Bool = false,
        isSystem: Bool = false,
        systemId: String? = nil,
        answerQuestionsInFirstMessage: Bool = false
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.isDefault = isDefault
        self.isSystem = isSystem
        self.systemId = systemId
        self.answerQuestionsInFirstMessage = answerQuestionsInFirstMessage
    }

    // MARK: - Codable (backward compatibility with v1/v2 format)

    enum CodingKeys: String, CodingKey {
        case id, name, content, isDefault, isSystem, systemId
        case answerQuestionsInFirstMessage
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
        answerQuestionsInFirstMessage = try container.decodeIfPresent(
            Bool.self,
            forKey: .answerQuestionsInFirstMessage
        ) ?? false
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
        try container.encode(answerQuestionsInFirstMessage, forKey: .answerQuestionsInFirstMessage)
        // voiceLanguage/textLanguage are NOT written in v2+
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
            systemId: definition.id,
            answerQuestionsInFirstMessage: false
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

// MARK: - Prompt name limit (spec 015, US10, research R32)

extension SystemPrompt {
    /// Maximum prompt name length in user-visible characters (`String.count`, grapheme clusters).
    static let maxNameLength = 30
}

/// Rules for prompt names typed in Settings and shown in the floating window (data-model §7).
enum PromptNameRule {
    /// Typing or pasting past the limit keeps the first 30 characters. A name that was already
    /// longer (saved before the limit existed) is left as is, so opening it never cuts it silently.
    static func clamp(new: String, old: String) -> String {
        guard new.count > SystemPrompt.maxNameLength, old.count <= SystemPrompt.maxNameLength else {
            return new
        }
        return String(new.prefix(SystemPrompt.maxNameLength))
    }

    /// Floating-window title: unchanged up to 30 characters, otherwise the first 29 plus "…".
    static func display(_ name: String) -> String {
        guard name.count > SystemPrompt.maxNameLength else { return name }
        return String(name.prefix(SystemPrompt.maxNameLength - 1)) + "…"
    }
}
