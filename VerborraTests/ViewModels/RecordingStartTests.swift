import XCTest
@testable import Verborra

// MARK: - RecordingStartTests (spec 015, T047)

@MainActor
final class RecordingStartTests: XCTestCase {
    private var viewModel: RecordingViewModel!
    private var mockAudio: MockAudioCaptureService!
    private var observedStates: [RecordingState] = []
    private var observation: Task<Void, Never>?

    /// Short budgets so the tests run fast; same proportions as production.
    private let overallBudget: Duration = .milliseconds(500)

    override func setUp() {
        super.setUp()
        mockAudio = MockAudioCaptureService()

        let keychain = MockKeychainService()
        try? keychain.save("sk-test", forKey: "openai-api-key")
        let settings = AppSettings(keychainService: keychain)
        let prompts = PromptsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prompts-\(UUID().uuidString).json"))

        let provider = MockAudioDeviceProvider()
        provider.mockDevices = [
            AudioDevice(uid: "USBMicUID", name: "USB Mic", audioDeviceID: 200, transportType: .usb, isSystemDefault: false)
        ]
        let deviceManager = AudioDeviceManager(provider: provider, settings: settings)
        deviceManager.selectDeviceForSession(uid: "USBMicUID")

        viewModel = RecordingViewModel(
            audioCaptureService: mockAudio,
            transcriptionService: MockTranscriptionService(),
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
        viewModel.selectedAudioDeviceID = "USBMicUID"
        observedStates = []
    }

    override func tearDown() {
        observation?.cancel()
        super.tearDown()
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private var isFinished: Bool {
        switch viewModel.state {
        case .recording, .error: return true
        default: return false
        }
    }

    /// Records each distinct state while waiting.
    private func runUntilFinished() async {
        observedStates = [viewModel.state]
        let deadline = Date().addingTimeInterval(3)
        while !isFinished, Date() < deadline {
            if observedStates.last != viewModel.state { observedStates.append(viewModel.state) }
            try? await Task.sleep(for: .milliseconds(1))
        }
        if observedStates.last != viewModel.state { observedStates.append(viewModel.state) }
    }

    // (a)
    func testFirstAttemptFailsSecondSucceeds() async {
        mockAudio.startResults = [.failure(.engineStartFailed(step: "start", underlying: "x")), .success]
        mockAudio.startDelay = .milliseconds(20)

        viewModel.startRecording()
        XCTAssertEqual(viewModel.state, .starting(attempt: 1))
        await runUntilFinished()

        XCTAssertEqual(observedStates.first, .starting(attempt: 1))
        XCTAssertTrue(observedStates.contains(.starting(attempt: 2)), "\(observedStates)")
        guard case .recording = viewModel.state else { return XCTFail("got \(viewModel.state)") }
        XCTAssertEqual(mockAudio.startAttempts, [1, 2])
    }

    // (b)
    func testBothAttemptsFailShowsRetryableError() async {
        mockAudio.startResults = [
            .failure(.formatMismatch(node: 44100, hardware: 48000)),
            .failure(.formatMismatch(node: 44100, hardware: 48000))
        ]
        viewModel.startRecording()
        await waitUntil { isFinished }

        XCTAssertEqual(viewModel.state, .error(.recordingStartFailed(.formatMismatch(node: 44100, hardware: 48000), deviceName: "USB Mic")))

        mockAudio.startResults = [.hang]
        viewModel.retryFromError()
        XCTAssertEqual(viewModel.state, .starting(attempt: 1))
        viewModel.cancelStart(trigger: "test")
    }

    // (c)
    func testBothAttemptsUseTheSameDevice() async {
        mockAudio.startResults = [.failure(.deviceUnavailable(step: "setDevice")), .failure(.deviceUnavailable(step: "setDevice"))]
        viewModel.startRecording()
        await waitUntil { isFinished }

        XCTAssertEqual(mockAudio.startDeviceIDs, ["200", "200"])
        XCTAssertEqual(viewModel.selectedAudioDeviceID, "USBMicUID")
    }

    // (d) + (h)
    func testHangingStartReachesErrorWithinBudget() async {
        mockAudio.startResults = [.hang, .hang]
        let start = ContinuousClock.now
        viewModel.startRecording()
        await waitUntil { isFinished }
        let elapsed = ContinuousClock.now - start

        XCTAssertEqual(viewModel.state, .error(.recordingStartFailed(.timeout(step: "start"), deviceName: "USB Mic")))
        XCTAssertLessThan(elapsed, overallBudget + .milliseconds(200), "took \(elapsed)")
        // Attempt 2 is capped by what is left of the budget
        XCTAssertEqual(mockAudio.startTimeouts.count, 2)
        XCTAssertLessThanOrEqual(mockAudio.startTimeouts[1].setup, .milliseconds(240))
    }

    // (e)
    func testHotkeyDuringStartCancelsSynchronously() {
        mockAudio.startResults = [.hang]
        viewModel.startRecording()
        XCTAssertEqual(viewModel.state, .starting(attempt: 1))

        viewModel.handleRecordingKey()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(mockAudio.cancelStartCalls, 1)
    }

    // (f)
    func testEscDuringStartCancels() {
        mockAudio.startResults = [.hang]
        viewModel.startRecording()

        viewModel.dismissOverlay()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(mockAudio.cancelStartCalls, 1)
    }

    // (g)
    func testLateSuccessAfterCancelDoesNotChangeState() async {
        mockAudio.startResults = [.success]
        mockAudio.startDelay = .milliseconds(50)
        viewModel.startRecording()
        viewModel.cancelStart(trigger: "test")
        XCTAssertEqual(viewModel.state, .idle)

        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(viewModel.state, .idle)
    }

    func testPermissionErrorIsNotRetried() async {
        mockAudio.shouldThrowOnStart = true
        viewModel.startRecording()
        await waitUntil { isFinished }
        XCTAssertEqual(viewModel.state, .error(.microphoneNotAvailable))
        XCTAssertEqual(mockAudio.startAttempts, [1])
    }
}
