import XCTest
@testable import Verborra

// MARK: - PromptNameRuleTests (spec 015, US10, T113)

@MainActor
final class PromptNameRuleTests: XCTestCase {
    private func string(_ count: Int, _ character: Character = "a") -> String {
        String(repeating: character, count: count)
    }

    // MARK: clamp

    func testTypingPastTheLimitKeepsThirtyCharacters() {
        XCTAssertEqual(PromptNameRule.clamp(new: string(31), old: string(30)), string(30))
    }

    func testPastingLongTextKeepsTheFirstThirty() {
        let pasted = "Rewrite this text in the info style, please"  // 43 characters
        XCTAssertEqual(PromptNameRule.clamp(new: pasted, old: "Short name"), String(pasted.prefix(30)))
    }

    func testLegacyOverLongNameIsNotCut() {
        XCTAssertEqual(PromptNameRule.clamp(new: string(41), old: string(42)), string(41))
    }

    func testGraphemeClustersCountAsOneCharacter() {
        let emoji = String(repeating: "👩‍💻", count: 30)
        let cjk = String(repeating: "語", count: 30)
        let accented = String(repeating: "é", count: 30)
        for name in [emoji, cjk, accented] {
            XCTAssertEqual(name.count, 30)
            XCTAssertEqual(PromptNameRule.clamp(new: name, old: ""), name)
            XCTAssertEqual(PromptNameRule.display(name), name)
        }
    }

    // MARK: display

    func testDisplayKeepsThirtyCharactersAndShortensLonger() {
        XCTAssertEqual(PromptNameRule.display(string(30)), string(30))
        XCTAssertEqual(PromptNameRule.display(string(31)), string(29) + "…")
        XCTAssertEqual(PromptNameRule.display(string(31)).count, 30)
    }

    // MARK: built-in names (FR-062)

    func testBuiltInNamesFitInEveryLanguage() {
        for definition in SystemPromptRegistry.all {
            for language in SupportedLanguage.allCases {
                let name = definition.name(for: language)
                XCTAssertLessThanOrEqual(name.count, SystemPrompt.maxNameLength, "\(language): \(name)")
            }
        }
    }

    func testNewPromptNameFitsInEnglishAndRussian() {
        // Test-only instances: changing `LocalizationManager.shared` would write the real app's `uiLanguage`
        for language in [SupportedLanguage.en, .ru] {
            guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else {
                return XCTFail("missing \(language.rawValue).lproj")
            }
            let name = LocalizationManager(language: language, bundle: bundle).string("settings.prompts.newPrompt")
            XCTAssertNotEqual(name, "settings.prompts.newPrompt")
            XCTAssertLessThanOrEqual(name.count, SystemPrompt.maxNameLength, "\(language): \(name)")
        }
    }

    // MARK: SettingsViewModel (FR-058, FR-060)

    private func makeSettingsViewModel() -> (SettingsViewModel, PromptsStore) {
        let settings = AppSettings(keychainService: MockKeychainService())
        let store = PromptsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prompts-\(UUID().uuidString).json"))
        let vocabulary = VocabularyStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("test-vocabularies-\(UUID().uuidString).json"))
        let devices = AudioDeviceManager(provider: MockAudioDeviceProvider(), settings: settings)
        let viewModel = SettingsViewModel(
            settings: settings, promptsStore: store, vocabularyStore: vocabulary, audioDeviceManager: devices
        )
        return (viewModel, store)
    }

    func testEditingNameIsClampedWhenTyping() {
        let (viewModel, _) = makeSettingsViewModel()
        viewModel.editingPromptName = string(10)
        viewModel.editingPromptName = string(45)
        XCTAssertEqual(viewModel.editingPromptName, string(30))
        XCTAssertFalse(viewModel.isPromptNameTooLong)
    }

    func testLegacyLongNameIsKeptButCannotBeSaved() {
        let (viewModel, store) = makeSettingsViewModel()
        let legacy = SystemPrompt(name: string(42), content: "c")
        store.addPrompt(legacy)

        viewModel.selectPrompt(legacy)
        XCTAssertEqual(viewModel.editingPromptName, string(42), "opening a legacy prompt doesn't cut its name")
        XCTAssertTrue(viewModel.isPromptNameTooLong)

        viewModel.editingPromptContent = "changed"
        viewModel.saveCurrentPrompt()
        XCTAssertEqual(store.prompts.first(where: { $0.id == legacy.id })?.content, "c", "save is refused while too long")

        viewModel.editingPromptName = string(30)
        viewModel.saveCurrentPrompt()
        XCTAssertEqual(store.prompts.first(where: { $0.id == legacy.id })?.name, string(30))
    }
}
