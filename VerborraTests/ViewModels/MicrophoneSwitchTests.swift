import AppKit
import XCTest
@testable import Verborra

// MARK: - MicrophoneSwitchTests (spec 015, US9, T100)

/// A microphone switch during recording goes through the start path: `.starting`, retry,
/// one 5 s budget, cancel on close/hotkey (research R31, contracts/recording-start.md).
@MainActor
final class MicrophoneSwitchTests: XCTestCase {
    private var viewModel: RecordingViewModel!
    private var mockAudio: MockAudioCaptureService!
    private var transcription: MockTranscriptionService!

    /// Short budgets so the tests run fast; same proportions as production.
    private let overallBudget: Duration = .milliseconds(500)

    private let usbUID = "USBMicUID"
    private let builtInUID = "BuiltInMicUID"
    private let airPodsUID = "AirPodsUID"

    override func setUp() {
        super.setUp()
        mockAudio = MockAudioCaptureService()
        transcription = MockTranscriptionService()

        let keychain = MockKeychainService()
        try? keychain.save("sk-test", forKey: "openai-api-key")
        let settings = AppSettings(keychainService: keychain)
        let prompts = PromptsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prompts-\(UUID().uuidString).json"))

        let provider = MockAudioDeviceProvider()
        provider.mockDevices = [
            AudioDevice(uid: usbUID, name: "USB Mic", audioDeviceID: 200, transportType: .usb, isSystemDefault: false),
            AudioDevice(uid: builtInUID, name: "Built-in Mic", audioDeviceID: 201, transportType: .builtIn, isSystemDefault: false),
            AudioDevice(uid: airPodsUID, name: "AirPods", audioDeviceID: 202, transportType: .bluetooth, isSystemDefault: false)
        ]
        provider.mockBluetoothProfileStates[airPodsUID] = .a2dp(sampleRate: 48000)
        let deviceManager = AudioDeviceManager(provider: provider, settings: settings)

        viewModel = RecordingViewModel(
            audioCaptureService: mockAudio,
            transcriptionService: transcription,
            formattingService: MockFormattingService(),
            pasteService: MockPasteService(),
            settings: settings,
            promptsStore: prompts,
            audioDeviceManager: deviceManager,
            overallStartBudget: overallBudget,
            attemptSetupTimeout: .milliseconds(180),
            retrySetupTimeout: .milliseconds(240),
            firstBufferTimeout: .milliseconds(60)
        )
    }

    // MARK: - Helpers

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private var isRecording: Bool {
        if case .recording = viewModel.state { return true }
        return false
    }

    private var isStartFailed: Bool {
        if case .error(.recordingStartFailed) = viewModel.state { return true }
        return false
    }

    /// Starts recording on System Default and waits until it runs.
    private func startRecordingOnDefault() async {
        viewModel.startRecording()
        await waitUntil { isRecording }
        XCTAssertTrue(isRecording, "precondition: recording on System Default")
    }

    private func key(_ keyCode: UInt16, _ characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        )!
    }

    // MARK: - 1. Switch enters `.starting` after stopping capture

    func testSwitchWhileRecordingStopsCaptureThenStarts() async {
        await startRecordingOnDefault()
        mockAudio.startDelay = .milliseconds(100)

        viewModel.switchAudioDevice(to: usbUID)

        XCTAssertEqual(viewModel.state, .starting(attempt: 1))
        XCTAssertEqual(viewModel.startKind, .switching(to: "USB Mic"))
        await waitUntil { mockAudio.calls.count >= 3 }
        XCTAssertEqual(Array(mockAudio.calls.suffix(2)), ["reset", "start"], "capture stops before the switch starts")
    }

    // MARK: - 2. Success restarts recording from zero

    func testSwitchSuccessRestartsRecordingFromZero() async {
        await startRecordingOnDefault()

        viewModel.switchAudioDevice(to: usbUID)
        await waitUntil { isRecording }

        guard case .recording(let duration, _) = viewModel.state else {
            return XCTFail("expected .recording, got \(viewModel.state)")
        }
        XCTAssertLessThan(duration, 0.5)
        XCTAssertEqual(mockAudio.startDeviceIDs.last, "200")
        XCTAssertEqual(viewModel.lastStartKind, .switching(to: "USB Mic"))
    }

    // MARK: - 3. Retry on the same device, then error naming the microphone

    func testSwitchRetriesOnSameDeviceThenSucceeds() async {
        await startRecordingOnDefault()
        mockAudio.startResults = [.failure(.timeout(step: "engineCreate")), .success]

        viewModel.switchAudioDevice(to: usbUID)
        await waitUntil { isRecording }

        XCTAssertTrue(isRecording)
        XCTAssertEqual(Array(mockAudio.startDeviceIDs.suffix(2)), ["200", "200"])
        XCTAssertEqual(Array(mockAudio.startAttempts.suffix(2)), [1, 2])
    }

    func testSwitchFailingTwiceShowsErrorNamingMicrophone() async {
        await startRecordingOnDefault()
        mockAudio.startResults = [.failure(.timeout(step: "engineCreate")), .failure(.timeout(step: "engineCreate"))]

        viewModel.switchAudioDevice(to: usbUID)
        await waitUntil { isStartFailed }

        XCTAssertEqual(viewModel.state, .error(.recordingStartFailed(.timeout(step: "engineCreate"), deviceName: "USB Mic")))
        XCTAssertEqual(viewModel.lastStartKind, .switching(to: "USB Mic"))
    }

    // MARK: - 4. Picking a microphone after a failed switch starts recording

    func testPickingMicrophoneAfterFailedSwitchStartsNewSwitch() async {
        await startRecordingOnDefault()
        mockAudio.startResults = [.failure(.timeout(step: "engineCreate")), .failure(.timeout(step: "engineCreate"))]
        viewModel.switchAudioDevice(to: usbUID)
        await waitUntil { isStartFailed }
        let startsBefore = mockAudio.startDeviceIDs.count

        viewModel.switchAudioDevice(to: builtInUID)

        XCTAssertEqual(viewModel.state, .starting(attempt: 1))
        XCTAssertEqual(viewModel.startKind, .switching(to: "Built-in Mic"))
        await waitUntil { isRecording }
        XCTAssertEqual(mockAudio.startDeviceIDs.count, startsBefore + 1)
        XCTAssertEqual(mockAudio.startDeviceIDs.last, "201")
    }

    func testPickingMicrophoneAfterFailedInitialStartOnlyChangesSelection() async {
        mockAudio.startResults = [.failure(.timeout(step: "engineCreate")), .failure(.timeout(step: "engineCreate"))]
        viewModel.startRecording()
        await waitUntil { isStartFailed }
        XCTAssertEqual(viewModel.lastStartKind, .initial)
        let startsBefore = mockAudio.startDeviceIDs.count

        viewModel.switchAudioDevice(to: builtInUID)

        XCTAssertTrue(isStartFailed, "selection only; no new start")
        XCTAssertEqual(mockAudio.startDeviceIDs.count, startsBefore)
        XCTAssertEqual(viewModel.audioDeviceManager.selectedDevice?.uid, builtInUID)
    }

    // MARK: - 5. Keys 1–3 are ignored during a switch

    func testNumberKeysIgnoredDuringSwitch() async {
        await startRecordingOnDefault()
        mockAudio.startDelay = .milliseconds(300)
        viewModel.promptsStore.addPrompt(SystemPrompt(name: "Second", content: "b"))
        viewModel.switchAudioDevice(to: usbUID)
        XCTAssertEqual(viewModel.state, .starting(attempt: 1))

        let prompt = viewModel.selectedPrompt.id
        let language = viewModel.selectedTextLanguage
        XCTAssertFalse(viewModel.handleKeyDown(key(18, "1")))
        XCTAssertFalse(viewModel.handleKeyDown(key(19, "2")))
        XCTAssertFalse(viewModel.handleKeyDown(key(20, "3")))
        XCTAssertEqual(viewModel.audioDeviceManager.selectedDevice?.uid, usbUID)
        XCTAssertEqual(viewModel.selectedPrompt.id, prompt)
        XCTAssertEqual(viewModel.selectedTextLanguage, language)
    }

    // MARK: - 6. Closing the window cancels the switch for good

    func testClosingWindowDuringSwitchCancelsItAndMicStaysOff() async {
        await startRecordingOnDefault()
        mockAudio.startDelay = .milliseconds(150)
        viewModel.switchAudioDevice(to: usbUID)
        XCTAssertEqual(viewModel.state, .starting(attempt: 1))

        viewModel.dismissOverlay()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertTrue(mockAudio.calls.contains("cancel"))
        // The delayed mock start finishes after the close; it must not bring recording back
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(viewModel.state, .idle)
    }

    // MARK: - 7. The hotkey during a switch cancels it; nothing is transcribed

    func testHotkeyDuringSwitchCancelsWithoutTranscribing() async {
        await startRecordingOnDefault()
        mockAudio.startDelay = .milliseconds(150)
        viewModel.switchAudioDevice(to: usbUID)

        viewModel.handleRecordingKey()

        XCTAssertEqual(viewModel.state, .idle)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertFalse(mockAudio.stopRecordingCalled)
        XCTAssertNil(transcription.lastModel, "nothing is sent for transcription")
    }

    // MARK: - 8. Budgets

    func testInitialStartGivesBluetoothItsOwnFiveSeconds() async {
        viewModel.startRecording()
        await waitUntil { isRecording }
        XCTAssertEqual(mockAudio.bluetoothTimeouts.first, .seconds(5))
    }

    func testBluetoothSwitchFitsInsideTheSwitchBudget() async {
        await startRecordingOnDefault()

        viewModel.switchAudioDevice(to: airPodsUID)
        await waitUntil { isRecording }

        let switchTimeout = try? XCTUnwrap(mockAudio.bluetoothTimeouts.last)
        XCTAssertNotNil(switchTimeout)
        XCTAssertLessThanOrEqual(switchTimeout ?? .seconds(99), overallBudget)
        XCTAssertGreaterThan(switchTimeout ?? .zero, .zero)
    }
}
