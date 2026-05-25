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

    func testSimpleVoiceToText_fallbackToEnglish() {
        let def = SystemPromptDefinition.simpleVoiceToText
        // Languages without translations should fall back to English
        let enName = def.name(for: .en)
        XCTAssertEqual(def.name(for: .es), enName)
        XCTAssertEqual(def.name(for: .zh), enName)
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
