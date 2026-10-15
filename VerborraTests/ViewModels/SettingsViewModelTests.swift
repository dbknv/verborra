import XCTest
@testable import Verborra

// MARK: - SettingsViewModelTests

@MainActor
final class SettingsViewModelTests: XCTestCase {
    var viewModel: SettingsViewModel!
    var mockKeychain: MockKeychainService!

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainService()
        let settings = AppSettings(keychainService: mockKeychain)
        let promptsStore = PromptsStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("test-prompts-\(UUID().uuidString).json"))

        let vocabularyStore = VocabularyStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("test-vocabularies-\(UUID().uuidString).json"))
        let deviceProvider = MockAudioDeviceProvider()
        deviceProvider.mockDevices = [
            AudioDevice(uid: "BuiltInMicUID", name: "MacBook Pro Microphone",
                        audioDeviceID: 100, transportType: .builtIn, isSystemDefault: true)
        ]
        deviceProvider.mockDefaultUID = "BuiltInMicUID"
        let audioDeviceManager = AudioDeviceManager(provider: deviceProvider, settings: settings)

        viewModel = SettingsViewModel(
            settings: settings,
            promptsStore: promptsStore,
            vocabularyStore: vocabularyStore,
            audioDeviceManager: audioDeviceManager
        )
    }

    func testInitialApiKeyEmpty() {
        XCTAssertTrue(viewModel.apiKeyInput.isEmpty)
    }

    func testValidateApiKey() {
        viewModel.apiKeyInput = "sk-"
        XCTAssertFalse(viewModel.validateApiKey())

        viewModel.apiKeyInput = "sk-12345678901234567890123"
        XCTAssertTrue(viewModel.validateApiKey())

        viewModel.apiKeyInput = "not-a-key"
        XCTAssertFalse(viewModel.validateApiKey())
    }

    func testSaveApiKey() {
        viewModel.apiKeyInput = "sk-test-key-12345678901234567890"
        viewModel.saveApiKey()
        XCTAssertTrue(viewModel.isApiKeySaved)
        XCTAssertEqual(mockKeychain.storage["openai-api-key"], "sk-test-key-12345678901234567890")
    }

    func testDefaultSettings() {
        XCTAssertTrue(viewModel.settings.autoRecord)
    }

    func testAddPrompt() {
        let initialCount = viewModel.promptsStore.prompts.count
        viewModel.addPrompt()
        XCTAssertEqual(viewModel.promptsStore.prompts.count, initialCount + 1)
    }

    func testDeletePrompt() {
        viewModel.addPrompt()
        let addedPrompt = viewModel.promptsStore.prompts.last!
        viewModel.deletePrompt(addedPrompt.id)
        XCTAssertNil(viewModel.promptsStore.prompts.first(where: { $0.id == addedPrompt.id }))
    }

    func testSelectPromptUpdatesEditing() {
        let prompt = SystemPrompt(name: "Test", content: "Test content")
        viewModel.promptsStore.addPrompt(prompt)
        viewModel.selectPrompt(prompt)

        XCTAssertEqual(viewModel.selectedPromptID, prompt.id)
        XCTAssertEqual(viewModel.editingPromptName, "Test")
        XCTAssertEqual(viewModel.editingPromptContent, "Test content")
    }

    func testSaveCurrentPrompt() {
        let prompt = SystemPrompt(name: "Original", content: "Original content")
        viewModel.promptsStore.addPrompt(prompt)
        viewModel.selectPrompt(prompt)

        viewModel.editingPromptName = "Updated"
        viewModel.editingPromptContent = "Updated content"
        viewModel.saveCurrentPrompt()

        let saved = viewModel.promptsStore.prompts.first(where: { $0.id == prompt.id })
        XCTAssertEqual(saved?.name, "Updated")
        XCTAssertEqual(saved?.content, "Updated content")
    }

    func testSetDefaultPrompt() {
        let prompt = SystemPrompt(name: "New Default", content: "content")
        viewModel.promptsStore.addPrompt(prompt)
        viewModel.setDefaultPrompt(prompt.id)

        let newDefault = viewModel.promptsStore.prompts.first(where: { $0.id == prompt.id })
        XCTAssertTrue(newDefault?.isDefault ?? false)
    }

    func testAudioDevices() {
        let devices = viewModel.audioDevices
        XCTAssertFalse(devices.isEmpty)
    }

    func testDefaultModelSettings() {
        XCTAssertEqual(viewModel.settings.selectedSTTModel, .gptTranscribe)
        XCTAssertEqual(viewModel.settings.selectedLLMModel, .gpt6Luna)
    }

    // MARK: - T050: System prompt protection in ViewModel

    func testCannotDeleteSystemPrompt() {
        let systemPrompt = viewModel.promptsStore.prompts.first(where: { $0.isSystem })!
        viewModel.selectedPromptID = systemPrompt.id
        viewModel.deletePrompt(systemPrompt.id)
        XCTAssertNotNil(viewModel.promptsStore.prompts.first(where: { $0.id == systemPrompt.id }))
    }

    func testCannotSaveSystemPrompt() {
        let systemPrompt = viewModel.promptsStore.prompts.first(where: { $0.isSystem })!
        viewModel.selectPrompt(systemPrompt)
        let originalName = systemPrompt.name
        viewModel.editingPromptName = "Hacked Name"
        viewModel.saveCurrentPrompt()
        XCTAssertEqual(viewModel.promptsStore.prompts.first(where: { $0.id == systemPrompt.id })?.name, originalName)
    }
}
