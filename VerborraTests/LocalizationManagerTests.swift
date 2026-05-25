import XCTest
@testable import Verborra

final class LocalizationManagerTests: XCTestCase {

    // MARK: - T029: detectSystemLanguage tests

    func testDetectSystemLanguage_supportedLanguage_returnsMatching() {
        let detected = LocalizationManager.detectSystemLanguage()
        XCTAssertTrue(LocalizationManager.isUILanguage(detected),
                      "Detected language should be a supported UI language")
    }

    func testIsUILanguage_enAndRu_returnsTrue() {
        XCTAssertTrue(LocalizationManager.isUILanguage(.en))
        XCTAssertTrue(LocalizationManager.isUILanguage(.ru))
    }

    func testIsUILanguage_otherLanguages_returnsFalse() {
        XCTAssertFalse(LocalizationManager.isUILanguage(.es))
        XCTAssertFalse(LocalizationManager.isUILanguage(.fr))
        XCTAssertFalse(LocalizationManager.isUILanguage(.de))
        XCTAssertFalse(LocalizationManager.isUILanguage(.zh))
        XCTAssertFalse(LocalizationManager.isUILanguage(.ja))
    }

    // MARK: - T031: Language persistence tests

    func testLanguageChange_updatesUserDefaults() {
        let manager = LocalizationManager.shared
        let originalLanguage = manager.currentLanguage

        manager.currentLanguage = .ru
        XCTAssertEqual(UserDefaults.standard.string(forKey: "uiLanguage"), "ru")

        manager.currentLanguage = .en
        XCTAssertEqual(UserDefaults.standard.string(forKey: "uiLanguage"), "en")

        manager.currentLanguage = originalLanguage
    }

    func testStringMethod_returnsKeyAsFallback() {
        let manager = LocalizationManager(language: .en)
        let result = manager.string("nonexistent.key.for.testing")
        XCTAssertEqual(result, "nonexistent.key.for.testing",
                       "Should return key itself when no translation found")
    }

    // MARK: - T032: UI language independence

    func testUILanguage_independentFromGlobalVoiceTextLanguage() {
        let settings = AppSettings()
        let originalLanguage = settings.uiLanguage
        let originalVoice = settings.globalVoiceLanguage
        let originalText = settings.globalTextLanguage

        // Set known values for voice/text
        settings.globalVoiceLanguage = .es
        settings.globalTextLanguage = .fr

        // Change UI language
        settings.uiLanguage = .en

        // Voice and text languages should remain unchanged
        XCTAssertEqual(settings.globalVoiceLanguage, .es)
        XCTAssertEqual(settings.globalTextLanguage, .fr)

        // Change UI language again
        settings.uiLanguage = .ru

        // Still unchanged
        XCTAssertEqual(settings.globalVoiceLanguage, .es)
        XCTAssertEqual(settings.globalTextLanguage, .fr)

        // Restore
        settings.uiLanguage = originalLanguage
        settings.globalVoiceLanguage = originalVoice
        settings.globalTextLanguage = originalText
    }

    func testUILanguageChange_updatesSystemPromptContent() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prompts-l10n-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = PromptsStore(fileURL: fileURL)
        let systemPrompt = store.prompts.first(where: { $0.isSystem })!

        // Update to English
        store.updateSystemPrompts(for: .en)
        let enPrompt = store.prompts.first(where: { $0.id == systemPrompt.id })!
        XCTAssertEqual(enPrompt.name, SystemPromptDefinition.simpleVoiceToText.name(for: .en))

        // Update to Russian
        store.updateSystemPrompts(for: .ru)
        let ruPrompt = store.prompts.first(where: { $0.id == systemPrompt.id })!
        XCTAssertEqual(ruPrompt.name, SystemPromptDefinition.simpleVoiceToText.name(for: .ru))
    }

    func testUILanguageChange_doesNotAffectUserPrompts() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prompts-user-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = PromptsStore(fileURL: fileURL)
        let userPrompt = SystemPrompt(name: "My Prompt", content: "My content")
        store.addPrompt(userPrompt)

        store.updateSystemPrompts(for: .en)

        let unchanged = store.prompts.first(where: { $0.id == userPrompt.id })!
        XCTAssertEqual(unchanged.name, "My Prompt")
        XCTAssertEqual(unchanged.content, "My content")
    }
}
