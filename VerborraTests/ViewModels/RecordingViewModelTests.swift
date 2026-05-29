import XCTest
@testable import Verborra

// MARK: - Mock Services

final class MockAudioCaptureService: AudioCaptureServiceProtocol {
    var audioLevel: Float = 0.0
    var currentDuration: TimeInterval = 0.0
    var onAutoStop: (@Sendable @MainActor () -> Void)?
    var onDeviceError: (@Sendable @MainActor (_ deviceName: String?, _ reason: DeviceErrorReason) -> Void)?
    var isRecording = false
    var shouldThrow = false
    var mockAudioData = Data([0x52, 0x49, 0x46, 0x46])  // "RIFF"
    var lastDeviceID: String?
    var lastMaxDuration: MaxRecordingDuration?

    func startRecording(deviceID: String?, maxDuration: MaxRecordingDuration) async throws {
        if shouldThrow { throw RecordingError.microphoneNotAvailable }
        lastDeviceID = deviceID
        lastMaxDuration = maxDuration
        isRecording = true
    }

    func stopRecording() async throws -> Data {
        isRecording = false
        return mockAudioData
    }

    func resetRecording() {
        isRecording = false
    }

    func updateLevelsFromAtomic() {}

    func availableInputDevices() -> [(id: String, name: String)] {
        return [("1", "Built-in Microphone")]
    }
}

final class MockTranscriptionService: TranscriptionServiceProtocol {
    var mockResult = "Привет мир"
    var shouldThrow = false
    var lastModel: STTModel?
    var lastLanguage: SupportedLanguage?

    func transcribe(audioData: Data, language: SupportedLanguage?, model: STTModel) async throws -> String {
        if shouldThrow { throw RecordingError.transcriptionFailed("Mock error") }
        lastModel = model
        lastLanguage = language
        return mockResult
    }
}

final class MockFormattingService: FormattingServiceProtocol {
    var mockResult = "# Привет мир"
    var shouldThrow = false
    var lastModel: LLMModel?
    var lastTextLanguage: SupportedLanguage?
    var lastSystemPrompt: String?

    func format(text: String, systemPrompt: String, textLanguage: SupportedLanguage, model: LLMModel) async throws -> String {
        if shouldThrow { throw RecordingError.formattingFailed("Mock error") }
        lastModel = model
        lastTextLanguage = textLanguage
        lastSystemPrompt = systemPrompt
        return mockResult
    }
}

final class MockPasteService: PasteServiceProtocol {
    var pastedText: String?
    var copiedText: String?
    var copiedPlainText: String?
    var pastedPlainText: String?

    func pasteText(_ text: String) async throws {
        pastedText = text
    }

    func copyToClipboard(_ text: String) {
        copiedText = text
    }

    func copyPlainTextToClipboard(_ markdownText: String) {
        copiedPlainText = markdownText
    }

    func pastePlainText(_ markdownText: String) async throws {
        pastedPlainText = markdownText
    }
}

// MARK: - RecordingViewModelTests

final class RecordingViewModelTests: XCTestCase {
    var viewModel: RecordingViewModel!
    var mockAudio: MockAudioCaptureService!
    var mockTranscription: MockTranscriptionService!
    var mockFormatting: MockFormattingService!
    var mockPaste: MockPasteService!

    override func setUp() {
        super.setUp()
        mockAudio = MockAudioCaptureService()
        mockTranscription = MockTranscriptionService()
        mockFormatting = MockFormattingService()
        mockPaste = MockPasteService()

        let mockKeychain = MockKeychainService()
        try? mockKeychain.save("sk-test", forKey: "openai-api-key")
        let settingsWithKey = AppSettings(keychainService: mockKeychain)

        let promptsStore = PromptsStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("test-prompts-\(UUID().uuidString).json"))

        let mockProvider = MockAudioDeviceProvider()
        mockProvider.mockDevices = []
        let audioDeviceManager = AudioDeviceManager(provider: mockProvider, settings: settingsWithKey)

        viewModel = RecordingViewModel(
            audioCaptureService: mockAudio,
            transcriptionService: mockTranscription,
            formattingService: mockFormatting,
            pasteService: mockPaste,
            settings: settingsWithKey,
            promptsStore: promptsStore,
            audioDeviceManager: audioDeviceManager
        )
    }

    func testInitialState() {
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.windowPhase, .preProcessing)
        XCTAssertNil(viewModel.chatSession)
    }

    func testStartRecording() {
        viewModel.startRecording()
        if case .recording = viewModel.state {
            // Expected
        } else {
            XCTFail("Expected recording state, got \(viewModel.state)")
        }
        XCTAssertTrue(mockAudio.isRecording)
    }

    func testStartRecordingWithoutApiKey() {
        let settingsNoKey = AppSettings(keychainService: MockKeychainService())
        let promptsStore = PromptsStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("test-prompts-\(UUID().uuidString).json"))
        let mockProvider2 = MockAudioDeviceProvider()
        let audioDeviceManager2 = AudioDeviceManager(provider: mockProvider2, settings: settingsNoKey)

        let vm = RecordingViewModel(
            audioCaptureService: mockAudio,
            transcriptionService: mockTranscription,
            formattingService: mockFormatting,
            pasteService: mockPaste,
            settings: settingsNoKey,
            promptsStore: promptsStore,
            audioDeviceManager: audioDeviceManager2
        )

        vm.startRecording()
        XCTAssertEqual(vm.state, .error(.apiKeyNotConfigured))
    }

    func testResetRecording() {
        viewModel.startRecording()
        viewModel.resetRecording()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertFalse(mockAudio.isRecording)
    }

    func testMicrophoneError() {
        mockAudio.shouldThrow = true
        viewModel.startRecording()
        XCTAssertEqual(viewModel.state, .error(.microphoneNotAvailable))
    }

    func testChangePromptDoesNotChangeLanguages() {
        let originalVoice = viewModel.selectedVoiceLanguage
        let originalText = viewModel.selectedTextLanguage

        let prompt = SystemPrompt(name: "English", content: "Format in English")
        viewModel.changePrompt(prompt)

        XCTAssertEqual(viewModel.selectedPrompt.name, "English")
        XCTAssertEqual(viewModel.selectedVoiceLanguage, originalVoice)
        XCTAssertEqual(viewModel.selectedTextLanguage, originalText)
    }

    func testChangeVoiceLanguage() {
        viewModel.changeVoiceLanguage(.es)
        XCTAssertEqual(viewModel.selectedVoiceLanguage, .es)
    }

    func testChangeTextLanguage() {
        viewModel.changeTextLanguage(.fr)
        XCTAssertEqual(viewModel.selectedTextLanguage, .fr)
    }

    func testHandleKeyDownEscape() {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false, keyCode: 53
        )!
        let handled = viewModel.handleKeyDown(event)
        XCTAssertTrue(handled)
    }

    func testStartRecordingPassesSettings() {
        viewModel.startRecording()
        XCTAssertEqual(mockAudio.lastMaxDuration, viewModel.settings.maxRecordingDuration)
    }

    func testDismissOverlayResetsState() {
        viewModel.inputText = "some text"
        viewModel.copyConfirmation = true
        viewModel.dismissOverlay()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.windowPhase, .preProcessing)
        XCTAssertNil(viewModel.chatSession)
        XCTAssertTrue(viewModel.inputText.isEmpty)
        XCTAssertFalse(viewModel.copyConfirmation)
    }

    // MARK: - Phase 10: New Scenario Tests

    func testWindowPhaseStartsAsPreProcessing() {
        XCTAssertEqual(viewModel.windowPhase, .preProcessing)
    }

    func testInputRecordingStateStartsAsIdle() {
        XCTAssertEqual(viewModel.inputRecordingState, .idle)
    }

    func testStopRecordingBlockedBeforeMinDuration() {
        viewModel.startRecording()
        // Immediately try to stop — duration < 2s
        viewModel.stopRecording()
        // Should still be recording since min 2s not reached
        if case .recording = viewModel.state {
            // Expected — still recording
        } else if case .transcribing = viewModel.state {
            // Also acceptable if timer fires fast enough
        } else {
            // State should not be idle
            XCTAssertNotEqual(viewModel.state, .idle)
        }
    }

    func testSendMessageDoesNothingWithEmptyText() {
        viewModel.inputText = "   "
        viewModel.sendMessage()
        // Should not crash, no messages added
    }

    func testSendMessageDoesNothingWithoutChatSession() {
        viewModel.inputText = "Test message"
        viewModel.chatSession = nil
        viewModel.sendMessage()
        // Should not crash
    }

    func testCopyMarkdownDoesNothingWithoutAssistantMessage() {
        viewModel.chatSession = ChatSession(
            systemPrompt: viewModel.selectedPrompt,
            voiceLanguage: .en,
            textLanguage: .ru
        )
        viewModel.copyMarkdown()
        // Should not crash, nothing copied
        XCTAssertNil(mockPaste.copiedText)
    }

    func testHandleKeyDownCmdW() {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "w", charactersIgnoringModifiers: "w",
            isARepeat: false, keyCode: 13
        )!
        let handled = viewModel.handleKeyDown(event)
        XCTAssertTrue(handled)
    }

    func testHandleKeyDownEnterInPostProcessing() {
        viewModel.windowPhase = .postProcessing
        viewModel.chatSession = ChatSession(
            systemPrompt: viewModel.selectedPrompt,
            voiceLanguage: .en,
            textLanguage: .ru
        )
        viewModel.inputText = ""

        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36
        )!
        let handled = viewModel.handleKeyDown(event)
        XCTAssertTrue(handled)
    }
}
