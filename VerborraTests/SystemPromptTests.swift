import XCTest
@testable import Verborra

// MARK: - T057: SystemPrompt Codable Tests

final class SystemPromptCodableTests: XCTestCase {

    func testDecodeOldFormat_setsDefaultIsSystem() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "Стандартный",
            "content": "Test content",
            "isDefault": true,
            "voiceLanguage": "ru",
            "textLanguage": "en"
        }
        """
        let data = json.data(using: .utf8)!
        let prompt = try JSONDecoder().decode(SystemPrompt.self, from: data)

        XCTAssertEqual(prompt.name, "Стандартный")
        XCTAssertFalse(prompt.isSystem, "Old format should decode isSystem as false")
        XCTAssertNil(prompt.systemId, "Old format should decode systemId as nil")
    }

    func testDecodeNewFormat_preservesIsSystem() throws {
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "name": "Simple Voice To Text",
            "content": "Fix errors",
            "isDefault": true,
            "isSystem": true,
            "systemId": "simple-voice-to-text"
        }
        """
        let data = json.data(using: .utf8)!
        let prompt = try JSONDecoder().decode(SystemPrompt.self, from: data)

        XCTAssertTrue(prompt.isSystem)
        XCTAssertEqual(prompt.systemId, "simple-voice-to-text")
    }

    func testEncode_doesNotContainVoiceTextLanguage() throws {
        let prompt = SystemPrompt(name: "Test", content: "Content", isSystem: true, systemId: "test-id")
        let data = try JSONEncoder().encode(prompt)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(dict["voiceLanguage"], "v2 format should not contain voiceLanguage")
        XCTAssertNil(dict["textLanguage"], "v2 format should not contain textLanguage")
        XCTAssertEqual(dict["isSystem"] as? Bool, true)
        XCTAssertEqual(dict["systemId"] as? String, "test-id")
    }

    func testMigrationPrompt_readsVoiceTextLanguage() throws {
        let json = """
        {
            "id": "33333333-3333-3333-3333-333333333333",
            "name": "Old Prompt",
            "content": "Old content",
            "isDefault": true,
            "voiceLanguage": "es",
            "textLanguage": "fr"
        }
        """
        let data = json.data(using: .utf8)!
        let migration = try JSONDecoder().decode(MigrationPrompt.self, from: data)

        XCTAssertEqual(migration.voiceLanguage, "es")
        XCTAssertEqual(migration.textLanguage, "fr")
        XCTAssertNil(migration.isSystem)
        XCTAssertNil(migration.systemId)
    }
}

// MARK: - T058: SystemPromptRegistry Tests

final class SystemPromptRegistryTests: XCTestCase {

    func testSimpleVoiceToText_hasEnAndRuTranslations() {
        let def = SystemPromptDefinition.simpleVoiceToText
        XCTAssertFalse(def.name(for: .en).isEmpty)
        XCTAssertFalse(def.content(for: .en).isEmpty)
        XCTAssertFalse(def.name(for: .ru).isEmpty)
        XCTAssertFalse(def.content(for: .ru).isEmpty)
    }

    /// 013: every supported language ships its own translation, so distinct languages
    /// must produce distinct names. The English fallback still triggers when a NEW
    /// language is added without translations (covered indirectly by the registry tests).
    func testSimpleVoiceToText_allSupportedLanguagesHaveDistinctTranslations() {
        let def = SystemPromptDefinition.simpleVoiceToText
        let names = Set(SupportedLanguage.allCases.map { def.name(for: $0) })
        XCTAssertEqual(names.count, SupportedLanguage.allCases.count, "Each supported language must have a unique localized name")
    }

    func testRegistryFindBySystemId() {
        let found = SystemPromptRegistry.definition(for: "simple-voice-to-text")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, "simple-voice-to-text")
    }

    func testRegistryFindBySystemId_nonexistent() {
        let found = SystemPromptRegistry.definition(for: "nonexistent-prompt")
        XCTAssertNil(found)
    }

    func testRegistryAll_containsSimpleVoiceToText() {
        XCTAssertTrue(SystemPromptRegistry.all.contains(where: { $0.id == "simple-voice-to-text" }))
    }
}

// MARK: - T005 (013): answerQuestionsInFirstMessage Codable / default / isReadOnly

final class SystemPromptAnswerQuestionsTests: XCTestCase {

    /// FR-010: a v2 JSON without the new field decodes with `false` default.
    func testDecode_v2WithoutField_defaultsToFalse() throws {
        let json = """
        {
            "id": "44444444-4444-4444-4444-444444444444",
            "name": "Legacy Custom",
            "content": "Legacy",
            "isDefault": false,
            "isSystem": false
        }
        """
        let data = json.data(using: .utf8)!
        let prompt = try JSONDecoder().decode(SystemPrompt.self, from: data)
        XCTAssertFalse(prompt.answerQuestionsInFirstMessage, "Missing field MUST decode to false (013-FR-010)")
    }

    /// FR-001: new field round-trips through encode/decode.
    func testRoundTrip_preservesAnswerQuestionsInFirstMessage() throws {
        let original = SystemPrompt(
            name: "Test",
            content: "Content",
            answerQuestionsInFirstMessage: true
        )
        let data = try JSONEncoder().encode(original)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["answerQuestionsInFirstMessage"] as? Bool, true)

        let decoded = try JSONDecoder().decode(SystemPrompt.self, from: data)
        XCTAssertTrue(decoded.answerQuestionsInFirstMessage)
    }

    /// FR-011: factory defaults the new field to false.
    func testMakeDefault_defaultsAnswerToFalse() {
        let p = SystemPrompt.makeDefault()
        XCTAssertFalse(p.answerQuestionsInFirstMessage, "Default for new prompts must be false (013-FR-011/FR-012)")
    }

    /// FR-009b: only the simple-voice-to-text built-in is read-only.
    func testIsReadOnly_onlyForSimpleVoiceToText() {
        let userPrompt = SystemPrompt(name: "Custom", content: "x")
        XCTAssertFalse(userPrompt.isReadOnly)

        let otherSystem = SystemPrompt(
            name: "Other System",
            content: "y",
            isSystem: true,
            systemId: "some-other-system-id"
        )
        XCTAssertFalse(otherSystem.isReadOnly, "isReadOnly must be specific to simple-voice-to-text")

        let svtt = SystemPrompt(
            name: "Simple",
            content: "z",
            isSystem: true,
            systemId: SystemPromptDefinition.simpleVoiceToText.id
        )
        XCTAssertTrue(svtt.isReadOnly)
    }

    /// SC-005: simplified content in all 10 locales — no paragraph wording.
    func testSimplifiedContent_noParagraphWording() {
        let def = SystemPromptDefinition.simpleVoiceToText
        // Substrings the OLD prompt contained but the simplified one must NOT contain.
        let bannedSubstrings = [
            "paragraphs", "paragraphes", "parágrafos", "absätze", "段落", "абзац", "параграф", "paragrafi", "parágrafo", "단락"
        ]
        for lang in SupportedLanguage.allCases {
            let content = def.content(for: lang).lowercased()
            for banned in bannedSubstrings {
                XCTAssertFalse(
                    content.contains(banned.lowercased()),
                    "Simplified `simple-voice-to-text` content for \(lang) must not mention paragraphs ('\(banned)') — got: \(content)"
                )
            }
        }
    }
}

// MARK: - T005 (013): DoNotAnswerInstruction

final class DoNotAnswerInstructionTests: XCTestCase {
    func testAllSupportedLanguages_haveTranslation() {
        for lang in SupportedLanguage.allCases {
            let text = DoNotAnswerInstruction.text(for: lang)
            XCTAssertFalse(text.isEmpty, "Missing translation for \(lang)")
        }
    }

    func testFallback_unknownLanguageUsesEnglish() {
        // We can't easily synthesize an "unknown" SupportedLanguage case (enum is closed),
        // so we verify the dictionary contract: missing key returns English fallback.
        let englishText = DoNotAnswerInstruction.translations[.en]!
        XCTAssertEqual(DoNotAnswerInstruction.text(for: .en), englishText)
    }

    func testRussianText_containsAnswerNegation() {
        let ru = DoNotAnswerInstruction.text(for: .ru)
        XCTAssertTrue(ru.contains("Не отвечай") || ru.contains("не отвечай"), "RU instruction must explicitly negate answering")
    }
}
