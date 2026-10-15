import Foundation
import SwiftUI

// MARK: - RecordingViewModel

@MainActor
@Observable
final class RecordingViewModel {
    // MARK: - State

    var state: RecordingState = .idle {
        didSet {
            if case .recording = state {
                DiagnosticLogger.updateFilterSnapshot(isRecordingActive: true)
            } else {
                DiagnosticLogger.updateFilterSnapshot(isRecordingActive: false)
            }
            MainThreadWatchdog.setStage(Self.watchdogStage(for: state))
        }
    }
    var windowPhase: WindowPhase = .preProcessing {
        didSet {
            if windowPhase == .postProcessing {
                MainThreadWatchdog.setStage("postProcessing")
            }
        }
    }
    var inputRecordingState: InputRecordingState = .idle
    var audioLevel: Float = 0.0
    /// `true` after the first voice-transcribed turn of the current session has been
    /// dispatched to the LLM. Reset on new session / overlay re-show. Used to gate
    /// `DoNotAnswerInstruction` injection — applies ONLY to that first turn.
    private var didConsumeFirstVoiceTurn: Bool = false
    /// Snapshot of `settings.globalTextLanguage` captured at `showOverlay()`,
    /// cleared at `cleanup()`. Lets the first-voice-turn diagnostic event
    /// (014, FR-022) classify the override source: `settings-default` when the
    /// floating-window picker still matches this snapshot at submission time,
    /// `user-changed` otherwise. In-memory only; never persisted.
    private var initialTextLanguageOnOpen: SupportedLanguage?
    var chatSession: ChatSession?
    var inputText: String = ""
    var copyConfirmation: Bool = false

    // Per-session selections (initialized from global settings, NOT persisted)
    var selectedPrompt: SystemPrompt
    var selectedVoiceLanguage: SupportedLanguage
    var selectedTextLanguage: SupportedLanguage
    var selectedAudioDeviceID: String?

    private let audioCaptureService: AudioCaptureServiceProtocol
    private let transcriptionService: TranscriptionServiceProtocol
    private let formattingService: FormattingServiceProtocol
    private(set) var streamingService: StreamingFormattingServiceProtocol?
    private(set) var pasteService: PasteServiceProtocol
    private var processingRouter: ProcessingRouter?
    private(set) var settings: AppSettings
    let promptsStore: PromptsStore
    let vocabularyStore: VocabularyStore
    let overlayManager = OverlayManager()
    let targetAppTracker = TargetAppTracker()

    /// AudioDeviceManager for device enumeration and selection (009-audio-device-selector)
    private(set) var audioDeviceManager: AudioDeviceManager

    private var durationTimer: Timer?
    private var levelTimer: Timer?
    private var recordingStart: Date?

    // spec 015 (US2): start orchestration
    private var startTask: Task<Void, Never>?
    private var startBeganAt: ContinuousClock.Instant?
    /// spec 015 (US9): what the current or last `.starting` is for (research R31).
    private(set) var startKind: StartKind = .initial
    /// Kind of the last start that finished; `.switching` after a failed switch lets a pick start again (FR-053).
    private(set) var lastStartKind: StartKind = .initial
    /// Display name of the microphone the current start targets (for `.recordingStartFailed`).
    private var startDeviceName = "System Default"
    /// Microphone a switch started from (event E16).
    private var switchFromName = "System Default"
    /// Bluetooth device prepared by the current start; returned to A2DP on cancel or failure (FR-055).
    private var preparedBluetoothDevice: AudioDevice?
    private let overallStartBudget: Duration
    private let attemptSetupTimeout: Duration
    private let retrySetupTimeout: Duration
    private let firstBufferTimeout: Duration
    private let logAudio = DiagnosticLogger.logger(for: .audio)
    private var savedAudioData: Data?

    // MARK: - Logging (T031, T036)
    private let logUserAction = DiagnosticLogger.logger(for: .userAction)
    /// API-category logger used for prompt-assembly diagnostics, sitting
    /// alongside the events emitted by `ChatSession.prepareMessagesForLLM`
    /// and `FormattingService` (014, FR-022).
    private let logApi = DiagnosticLogger.logger(for: .api)
    private(set) var currentFlowId: UUID?

    init(
        audioCaptureService: AudioCaptureServiceProtocol,
        transcriptionService: TranscriptionServiceProtocol,
        formattingService: FormattingServiceProtocol,
        pasteService: PasteServiceProtocol,
        settings: AppSettings,
        promptsStore: PromptsStore,
        vocabularyStore: VocabularyStore = VocabularyStore(),
        audioDeviceManager: AudioDeviceManager,
        processingRouter: ProcessingRouter? = nil,
        streamingService: StreamingFormattingServiceProtocol? = nil,
        overallStartBudget: Duration = .seconds(5),
        attemptSetupTimeout: Duration = .milliseconds(1800),
        retrySetupTimeout: Duration = .milliseconds(2400),
        firstBufferTimeout: Duration = .milliseconds(600)
    ) {
        self.overallStartBudget = overallStartBudget
        self.attemptSetupTimeout = attemptSetupTimeout
        self.retrySetupTimeout = retrySetupTimeout
        self.firstBufferTimeout = firstBufferTimeout
        self.vocabularyStore = vocabularyStore
        self.audioCaptureService = audioCaptureService
        self.transcriptionService = transcriptionService
        self.formattingService = formattingService
        self.pasteService = pasteService
        self.processingRouter = processingRouter
        self.streamingService = streamingService
        self.settings = settings
        self.promptsStore = promptsStore
        self.audioDeviceManager = audioDeviceManager

        let defaultPrompt = promptsStore.defaultPrompt
        self.selectedPrompt = defaultPrompt
        self.selectedVoiceLanguage = settings.globalVoiceLanguage
        self.selectedTextLanguage = settings.globalTextLanguage

        self.audioCaptureService.onAutoStop = { @Sendable [weak self] in
            self?.stopRecording()
        }

        self.audioCaptureService.onDeviceError = { @Sendable [weak self] deviceName, reason in
            guard let self else { return }
            self.stopTimers()
            self.stopInputTimers()
            switch reason {
            case .disconnected:
                self.state = .error(.deviceDisconnected(deviceName))
            case .formatChanged:
                self.state = .error(.deviceFormatChanged(deviceName))
            }
        }

        // Wire up AudioDeviceManager callbacks
        self.audioDeviceManager.onDeviceDisconnected = { [weak self] in
            guard let self else { return }
            if case .recording = self.state {
                self.stopTimers()
                self.audioCaptureService.resetRecording()
                self.state = .error(.deviceDisconnected(nil))
            }
        }

        self.audioDeviceManager.onDefaultDeviceChanged = { [weak self] in
            guard let self else { return }
            if case .recording = self.state {
                // Restart recording on new system default
                self.audioCaptureService.resetRecording()
                Task { @MainActor in
                    do {
                        self.syncAudioSaveSettings()
                        try await self.audioCaptureService.startRecording(
                            deviceID: nil, // System Default — use nil
                            maxDuration: self.settings.maxRecordingDuration,
                            awaitBluetoothSwitch: false
                        )
                        self.recordingStart = Date()
                        let maxSeconds = self.settings.maxRecordingDuration.timeInterval
                        self.state = .recording(duration: 0, remaining: maxSeconds)
                    } catch {
                        self.state = .error(self.mapError(error))
                    }
                }
            }
        }

        self.audioDeviceManager.onBluetoothSwitchComplete = { _ in
            // BT switch done — if recording was pending restart, start now
            // (handled by switchAudioDevice flow)
        }

        self.audioDeviceManager.onBluetoothSwitchError = { [weak self] _ in
            guard let self else { return }
            self.state = .error(.deviceUnavailable)
        }

        // T036: Регистрируем как провайдер состояния для ERROR-контекста
        DiagnosticLogger.appStateProvider = self
        DiagnosticLogger.isRecordingActiveProvider = { [weak self] in
            guard let self else { return false }
            if case .recording = self.state { return true }
            return false
        }
    }

    func updatePasteService(_ service: PasteServiceProtocol) {
        self.pasteService = service
    }

    func updateStreamingService(_ service: StreamingFormattingServiceProtocol) {
        self.streamingService = service
    }

    // MARK: - Prompt & Language Changes

    /// Where a selection change came from, for the `.userAction` log (spec 015, FR-029).
    enum SelectionChangeSource: String {
        case menu
        case key
    }

    func changePrompt(_ prompt: SystemPrompt, source: SelectionChangeSource = .menu) {
        let old = selectedPrompt
        selectedPrompt = prompt
        // Mirror into the active session, like the language changes below
        chatSession?.systemPrompt = prompt
        logUserAction.info("Prompt changed", metadata: [
            "from": old.name,
            "to": prompt.name,
            "source": source.rawValue
        ])
    }

    /// Key 2: next prompt, wrapping around (contracts/floating-window-keys.md).
    func cyclePrompt() {
        let prompts = promptsStore.prompts
        guard !prompts.isEmpty else { return }
        guard let index = prompts.firstIndex(where: { $0.id == selectedPrompt.id }) else {
            changePrompt(promptsStore.defaultPrompt, source: .key)
            return
        }
        let next = prompts[(index + 1) % prompts.count]
        guard next.id != selectedPrompt.id else { return }
        changePrompt(next, source: .key)
    }

    func changeVoiceLanguage(_ language: SupportedLanguage) {
        selectedVoiceLanguage = language
        // Mirror into the active session so chat continuation reflects the
        // change. `session.voiceLanguage` is captured at init time only.
        chatSession?.voiceLanguage = language
    }

    func changeTextLanguage(_ language: SupportedLanguage, source: SelectionChangeSource = .menu) {
        let old = selectedTextLanguage
        selectedTextLanguage = language
        logUserAction.info("Text language changed", metadata: [
            "from": old.rawValue,
            "to": language.rawValue,
            "source": source.rawValue
        ])
        // Mirror into the active session so chat-continuation prompt
        // assembly (`ChatSession.prepareMessagesForLLM`) uses the new
        // target language for `TranslateToTargetInstruction` instead of
        // the one captured at session creation.
        chatSession?.textLanguage = language
    }

    func cycleVoiceLanguage() {
        let all = SupportedLanguage.allCases
        guard let index = all.firstIndex(of: selectedVoiceLanguage) else { return }
        let next = all[(index + 1) % all.count]
        changeVoiceLanguage(next)
    }

    func cycleTextLanguage() {
        let all = SupportedLanguage.allCases
        guard let index = all.firstIndex(of: selectedTextLanguage) else { return }
        let next = all[(index + 1) % all.count]
        changeTextLanguage(next, source: .key)
    }

    func cycleMicrophone() {
        let devices = audioDeviceManager.devices
        guard !devices.isEmpty else { return }
        let currentUID = audioDeviceManager.selectedDevice?.uid
        let newUID: String
        if let currentUID, let currentIndex = devices.firstIndex(where: { $0.uid == currentUID }) {
            newUID = devices[(currentIndex + 1) % devices.count].uid
        } else {
            newUID = devices.count > 1 ? devices[1].uid : devices[0].uid
        }
        switchAudioDevice(to: newUID, source: .key)
    }

    /// Number keys work in the pre-recording phase while idle, recording or showing an error, the same
    /// states in which the bottom-bar menus are enabled (AS 4.7). Auto-record users are always recording here.
    private var canCycleSelections: Bool {
        guard windowPhase == .preProcessing else { return false }
        switch state {
        case .idle, .recording, .error: return true
        case .starting, .transcribing, .formatting: return false
        }
    }

    /// Switch audio device by UID. Empty string = System Default.
    /// While recording (or after a failed switch) this starts a switch through the start path (research R31):
    /// `.starting`, retry, one 5 s budget, cancel on close/hotkey. Otherwise only the selection changes.
    func switchAudioDevice(to deviceUID: String, source: SelectionChangeSource = .menu) {
        guard deviceUID != audioDeviceManager.selectedDevice?.uid else { return }
        let previousName = audioDeviceManager.selectedDevice?.name ?? "System Default"
        logUserAction.info("Microphone changed", metadata: [
            "from": previousName,
            "to": audioDeviceManager.devices.first(where: { $0.uid == deviceUID })?.name ?? "System Default",
            "source": source.rawValue
        ])

        audioDeviceManager.bluetoothProfileManager.cancelPreparation()

        // T018: If switching FROM Bluetooth device, restore A2DP on old device
        if let oldDevice = audioDeviceManager.selectedDevice,
           oldDevice.transportType.isBluetooth,
           !oldDevice.isSystemDefaultEntry {
            audioDeviceManager.bluetoothProfileManager.restoreA2DP(device: oldDevice)
        }

        // FR-006: Session-only switch — does NOT change settings default
        audioDeviceManager.selectDeviceForSession(uid: deviceUID)
        selectedAudioDeviceID = deviceUID.isEmpty ? nil : deviceUID
        let newName = audioDeviceManager.selectedDevice?.name ?? "System Default"

        switch state {
        case .recording:
            // Audio recorded so far is discarded; recording restarts on the new microphone (Clarifications)
            stopTimers()
            audioCaptureService.resetRecording()
            switchFromName = previousName
            beginStart(kind: .switching(to: newName))
        case .error(.recordingStartFailed) where lastStartKind != .initial:
            // FR-053: after a failed switch, picking a microphone starts recording on it
            switchFromName = previousName
            beginStart(kind: .switching(to: newName))
        default:
            break
        }
    }

    /// Resolve a stable UID to the numeric AudioDeviceID string that AudioCaptureService expects.
    /// Returns nil for System Default (empty UID).
    private func resolveDeviceIDForCapture(uid: String) -> String? {
        guard !uid.isEmpty else { return nil }
        // Find device in manager's list and return its AudioDeviceID as string
        if let device = audioDeviceManager.devices.first(where: { $0.uid == uid }) {
            return String(device.audioDeviceID)
        }
        return nil
    }

    // MARK: - Text Input (Scenario 2)

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let session = chatSession else { return }

        // FR-015: no parallel requests within a single session.
        if session.lastAssistantMessage?.isStreaming == true { return }

        inputText = ""

        // Add user message
        let userMessage = ChatMessage(role: .user, content: text)
        session.addMessage(userMessage)

        // Create assistant message for streaming
        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        session.addMessage(assistantMessage)

        Task { @MainActor in
            do {
                let systemPromptTokens = TokenEstimator.estimateTokens(
                    selectedPrompt.contentForLanguage(selectedTextLanguage)
                )
                let budget = TokenEstimator.messageBudget(
                    for: settings.selectedLLMModel,
                    systemPromptTokens: systemPromptTokens
                )
                // FR-004 / FR-005 / FR-006 / FR-007 / FR-008:
                // continuation always sends full session history through prepareMessagesForLLM.
                // `isFirstVoiceTurn` is false here — this is a chat-input message, not voice.
                let messagesForAPI = session.prepareMessagesForLLM(
                    maxTokenBudget: budget,
                    systemPromptTokens: systemPromptTokens,
                    isFirstVoiceTurn: false,
                    answerQuestionsInFirstMessage: selectedPrompt.answerQuestionsInFirstMessage
                )

                guard let streaming = streamingService else {
                    throw RecordingError.formattingFailed("Streaming service unavailable")
                }

                let stream = streaming.streamChat(messages: messagesForAPI, model: settings.selectedLLMModel)
                var accumulated = ""
                for try await token in stream {
                    accumulated += token
                    session.updateLastAssistantContent(accumulated)
                }

                assistantMessage.isStreaming = false
            } catch {
                assistantMessage.isStreaming = false
                assistantMessage.content = error.localizedDescription
            }
        }
    }

    // MARK: - Voice Input in Input Field (Scenario 2)

    func startInputRecording() {
        guard windowPhase == .postProcessing else { return }
        guard inputRecordingState == .idle else { return }

        Task { @MainActor in
            do {
                let selectedDevice = audioDeviceManager.selectedDevice
                var needsBTSwitch = false
                if let device = selectedDevice,
                   device.transportType.isBluetooth,
                   !device.isSystemDefaultEntry {
                    _ = await audioDeviceManager.bluetoothProfileManager
                        .prepareForRecording(device: device, context: .firstStart)
                    needsBTSwitch = true
                }

                let captureDeviceID = resolveDeviceIDForCapture(uid: selectedDevice?.uid ?? "")
                syncAudioSaveSettings()
                try await audioCaptureService.startRecording(
                    deviceID: captureDeviceID,
                    maxDuration: settings.maxRecordingDuration,
                    awaitBluetoothSwitch: needsBTSwitch
                )
                recordingStart = Date()
                let maxSeconds = settings.maxRecordingDuration.timeInterval
                inputRecordingState = .recording(duration: 0, remaining: maxSeconds)
                startInputTimers()
            } catch {
                state = .error(mapError(error))
            }
        }
    }

    func stopInputRecording() {
        guard case .recording(let duration, _) = inputRecordingState, duration >= 2.0 else {
            return
        }

        stopInputTimers()
        inputRecordingState = .processing

        Task { @MainActor in
            do {
                let audioData = try await audioCaptureService.stopRecording()

                let rawText: String
                if let router = processingRouter {
                    rawText = try await router.transcribe(audioData: audioData, language: selectedVoiceLanguage)
                } else {
                    rawText = try await transcriptionService.transcribe(
                        audioData: audioData,
                        language: selectedVoiceLanguage,
                        model: settings.selectedSTTModel
                    )
                }

                // Append to existing input text (FR-030: no auto-send)
                if inputText.isEmpty {
                    inputText = rawText
                } else {
                    inputText += " " + rawText
                }

                inputRecordingState = .idle
            } catch {
                inputRecordingState = .idle
                state = .error(mapError(error))
            }
        }
    }

    private var inputDurationTimer: Timer?
    private var inputLevelTimer: Timer?

    private func startInputTimers() {
        let maxSeconds = settings.maxRecordingDuration.timeInterval

        // T022: Timer on main RunLoop — assumeIsolated safe (R-006)
        inputDurationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let start = self.recordingStart else { return }
                let duration = Date().timeIntervalSince(start)
                let remaining = max(0, maxSeconds - duration)
                self.inputRecordingState = .recording(duration: duration, remaining: remaining)
                if remaining <= 0 {
                    self.stopInputRecording()
                }
            }
        }

        // T023: Use updateLevelsFromAtomic() (FR-016)
        inputLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.audioCaptureService.updateLevelsFromAtomic()
                self.audioLevel = self.audioCaptureService.audioLevel
            }
        }
    }

    private func stopInputTimers() {
        inputDurationTimer?.invalidate()
        inputDurationTimer = nil
        inputLevelTimer?.invalidate()
        inputLevelTimer = nil
    }

    // MARK: - Actions

    func toggleOverlay() {
        guard settings.isOnboardingCompleted else { return }
        if overlayManager.isVisible {
            // Overlay visible — handle as recording key, not dismiss
            handleRecordingKey()
        } else {
            showOverlay()
        }
    }

    func showOverlay() {
        // T031: beginFlow при открытии overlay
        if let oldFlow = currentFlowId {
            _ = FlowTracker.shared.endFlow(oldFlow)
        }
        currentFlowId = FlowTracker.shared.beginFlow()
        FlowTracker.shared.addBreadcrumb(
            Breadcrumb(label: "overlay_shown", category: .userAction),
            to: currentFlowId!
        )

        state = .idle
        windowPhase = .preProcessing
        inputRecordingState = .idle
        inputText = ""
        copyConfirmation = false
        savedAudioData = nil

        // Reset to defaults from global settings (session-only, not persisted)
        let defaultPrompt = promptsStore.defaultPrompt
        selectedPrompt = defaultPrompt
        selectedVoiceLanguage = settings.globalVoiceLanguage
        selectedTextLanguage = settings.globalTextLanguage
        // FR-005/FR-007: Load default device from settings (not session state)
        let defaultUID = settings.selectedAudioDeviceUID
        audioDeviceManager.selectDeviceForSession(uid: defaultUID)
        selectedAudioDeviceID = defaultUID.isEmpty ? nil : defaultUID

        // Create new chat session
        chatSession = ChatSession(
            systemPrompt: selectedPrompt,
            voiceLanguage: selectedVoiceLanguage,
            textLanguage: selectedTextLanguage,
            audioDevice: selectedAudioDeviceID
        )
        // FR-013: every new session restarts the first-voice-turn gate.
        didConsumeFirstVoiceTurn = false
        // 014 FR-013: snapshot the Settings default at window-open so the
        // first-voice-turn diagnostic event (FR-022) can classify the
        // override source. Reset on cleanup() — see ephemeral lifecycle.
        initialTextLanguageOnOpen = settings.globalTextLanguage

        targetAppTracker.startTracking()
        MainThreadWatchdog.setStage("overlayShown")

        let contentView = OverlayContentView(viewModel: self)
        overlayManager.show(with: contentView)
        overlayManager.installKeyMonitor { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }

        // Auto-record if enabled
        if settings.autoRecord {
            startRecording()
        }
    }

    func startRecording() {
        if !settings.hasApiKey {
            state = .error(.apiKeyNotConfigured)
            return
        }

        // T032: breadcrumb
        if let flowId = currentFlowId {
            FlowTracker.shared.addBreadcrumb(
                Breadcrumb(label: "recording_started", category: .audio, metadata: [
                    "deviceID": selectedAudioDeviceID ?? "default"
                ]),
                to: flowId
            )
        }

        beginStart(kind: .initial)
    }

    /// spec 015 (US2, US9): `.starting` → up to two attempts on the same device → `.recording` or `.error`.
    /// `.initial`: the 5 s budget starts after the Bluetooth mode switch, which has its own 5 s (FR-007).
    /// `.switching`: one 5 s budget from the request, Bluetooth step included (FR-049).
    private func beginStart(kind: StartKind) {
        startTask?.cancel()
        let requestedAt = ContinuousClock.now
        startBeganAt = requestedAt
        startKind = kind
        preparedBluetoothDevice = nil
        let isSwitch = kind != .initial
        startDeviceName = audioDeviceManager.selectedDevice?.name ?? "System Default"
        state = .starting(attempt: 1)

        startTask = Task { @MainActor in
            let selectedDevice = audioDeviceManager.selectedDevice
            let deviceName = selectedDevice?.name ?? "System Default"
            let btSwitchMs = await prepareBluetoothIfNeeded(selectedDevice, isSwitch: isSwitch)
            let needsBTSwitch = btSwitchMs != nil
            guard !Task.isCancelled else { return }

            let captureDeviceID = resolveDeviceIDForCapture(uid: selectedDevice?.uid ?? "")
            MainThreadWatchdog.setDevice(name: deviceName, id: captureDeviceID)
            syncAudioSaveSettings()

            let budgetStart = isSwitch ? requestedAt : ContinuousClock.now
            var lastError: Error?
            var attemptsMade = 0
            for attempt in 1...2 {
                guard !Task.isCancelled else { return }
                state = .starting(attempt: attempt)

                guard let timeouts = attemptTimeouts(attempt: attempt, isSwitch: isSwitch, budgetStart: budgetStart) else {
                    lastError = AudioSetupError.timeout(step: "budget")
                    break
                }
                attemptsMade = attempt

                do {
                    try await audioCaptureService.startRecording(
                        deviceID: captureDeviceID,
                        maxDuration: settings.maxRecordingDuration,
                        awaitBluetoothSwitch: needsBTSwitch && attempt == 1,
                        attempt: attempt,
                        timeouts: timeouts
                    )
                    guard !Task.isCancelled else { return }
                    lastStartKind = kind
                    preparedBluetoothDevice = nil
                    if isSwitch { logMicrophoneSwitch(outcome: "ok", attempts: attempt) }
                    recordingStart = Date()
                    let maxSeconds = settings.maxRecordingDuration.timeInterval
                    state = .recording(duration: 0, remaining: maxSeconds)
                    startTimers()
                    let deviceSwitchMs = (btSwitchMs ?? 0) + audioCaptureService.lastBluetoothSwitchMs
                    logAudio.info("Recording ready", metadata: [
                        "hotkeyToReadyMs": "\(Int(max(0, Self.ms(since: requestedAt) - deviceSwitchMs)))",
                        "btSwitchMs": "\(Int(deviceSwitchMs))",
                        "attempts": "\(attempt)",
                        "deviceName": deviceName,
                        "deviceID": captureDeviceID ?? "default"
                    ])
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    // Permission and similar errors aren't fixed by retrying
                    if error is RecordingError {
                        finishFailedStart(kind: kind, attempts: attempt, reason: "\(error)")
                        state = .error(mapError(error))
                        return
                    }
                    lastError = error
                }
            }

            guard !Task.isCancelled else { return }
            let reason = (lastError as? AudioSetupError)?.startFailureReason ?? .deviceUnavailable
            finishFailedStart(kind: kind, attempts: attemptsMade, reason: reason.shortDescription)
            logAudio.error(
                "Recording start failed after retry",
                parameters: [
                    "deviceName": deviceName,
                    "deviceID": captureDeviceID ?? "default",
                    "totalMs": "\(Int(Self.ms(since: requestedAt)))",
                    "reason": reason.shortDescription
                ],
                errorCode: "recordingStartFailed"
            )
            state = .error(.recordingStartFailed(reason, deviceName: deviceName))
        }
    }

    /// FR-031: every Bluetooth device needs stabilization — even "already HFP" can have a stale rate
    /// after A2DP restore. Returns the preparation time in ms, or `nil` when the device isn't Bluetooth.
    private func prepareBluetoothIfNeeded(_ device: AudioDevice?, isSwitch: Bool) async -> Double? {
        guard let device, device.transportType.isBluetooth, !device.isSystemDefaultEntry else { return nil }
        let btStart = ContinuousClock.now
        _ = await audioDeviceManager.bluetoothProfileManager
            .prepareForRecording(device: device, context: isSwitch ? .deviceSwitch : .firstStart)
        preparedBluetoothDevice = device
        return Self.ms(since: btStart)
    }

    /// Time limits for one attempt from what is left of the 5 s budget; `nil` when nothing is left.
    /// A switch leaves room for setup and the first buffer after the Bluetooth step (FR-049).
    private func attemptTimeouts(attempt: Int, isSwitch: Bool, budgetStart: ContinuousClock.Instant) -> StartTimeouts? {
        let remaining = overallStartBudget - (ContinuousClock.now - budgetStart)
        guard remaining > .zero else { return nil }
        let setup = min(attempt == 1 ? attemptSetupTimeout : retrySetupTimeout, remaining)
        // What's left after setup also caps the first-buffer wait
        let firstBuffer = min(firstBufferTimeout, max(remaining - setup, .milliseconds(1)))
        let bluetooth: Duration = isSwitch ? max(remaining - setup - firstBuffer, .milliseconds(1)) : .seconds(5)
        return StartTimeouts(setup: setup, firstBuffer: firstBuffer, bluetooth: bluetooth)
    }

    /// After the last failed attempt: remember the kind (FR-053), restore A2DP on a prepared
    /// Bluetooth target, and log the switch outcome (E16).
    private func finishFailedStart(kind: StartKind, attempts: Int, reason: String) {
        lastStartKind = kind
        restorePreparedBluetoothDevice()
        if kind != .initial {
            logMicrophoneSwitch(outcome: "failed", attempts: attempts, reason: reason)
        }
    }

    private func restorePreparedBluetoothDevice() {
        if let device = preparedBluetoothDevice {
            audioDeviceManager.bluetoothProfileManager.restoreA2DP(device: device)
            preparedBluetoothDevice = nil
        }
    }

    /// Event E16 `Microphone switch` (contracts/diagnostic-events.md, FR-057).
    private func logMicrophoneSwitch(outcome: String, attempts: Int, trigger: String? = nil, reason: String? = nil) {
        guard case .switching(let target) = startKind else { return }
        var metadata = [
            "from": switchFromName,
            "to": target,
            "outcome": outcome,
            "durationMs": "\(Int(startBeganAt.map { Self.ms(since: $0) } ?? 0))",
            "attempts": "\(attempts)"
        ]
        if let trigger { metadata["trigger"] = trigger }
        if outcome == "failed" {
            metadata["reason"] = reason ?? "unknown"
            metadata["deviceID"] = selectedAudioDeviceID ?? "default"
            logAudio.error("Microphone switch", parameters: metadata, errorCode: "microphoneSwitchFailed")
        } else {
            logAudio.info("Microphone switch", metadata: metadata)
        }
    }

    /// Cancels a start in progress (hotkey, Esc, window close, Cancel button). Returns to `.idle`
    /// synchronously; the audio host is torn down in the background (FR-013a).
    func cancelStart(trigger: String) {
        guard case .starting(let attempt) = state else { return }
        startTask?.cancel()
        startTask = nil
        audioCaptureService.cancelStart()
        audioDeviceManager.bluetoothProfileManager.cancelPreparation()
        restorePreparedBluetoothDevice()  // FR-055
        state = .idle
        logUserAction.info("Recording start cancelled", metadata: [
            "attempt": "\(attempt)",
            "elapsedMs": "\(Int(startBeganAt.map { Self.ms(since: $0) } ?? 0))",
            "trigger": trigger
        ])
        logMicrophoneSwitch(outcome: "cancelled", attempts: attempt, trigger: trigger)
    }

    private static func ms(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    // swiftlint:disable:next cyclomatic_complexity - dictation pipeline, pre-existing (013/014); refactor out of scope for 015
    func stopRecording() {
        guard case .recording(let duration, _) = state, duration >= 2.0 else {
            return
        }

        stopTimers()

        // FR-033: Restore A2DP after stopping recording on Bluetooth device
        if let device = audioDeviceManager.selectedDevice,
           device.transportType.isBluetooth,
           !device.isSystemDefaultEntry {
            audioDeviceManager.bluetoothProfileManager.restoreA2DP(device: device)
        }

        state = .transcribing

        Task { @MainActor in
            do {
                let audioData = try await audioCaptureService.stopRecording()
                savedAudioData = audioData
                chatSession?.audioData = audioData

                let rawText: String
                if let router = processingRouter {
                    rawText = try await router.transcribe(audioData: audioData, language: selectedVoiceLanguage)
                } else {
                    rawText = try await transcriptionService.transcribe(
                        audioData: audioData,
                        language: selectedVoiceLanguage,
                        model: settings.selectedSTTModel
                    )
                }

                guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    state = .error(.emptyTranscription)
                    return
                }

                // Add transcription message to chat
                let transcriptionMessage = ChatMessage(role: .transcription, content: rawText)
                chatSession?.addMessage(transcriptionMessage)

                // Add system prompt message if first time
                if chatSession?.messages.first(where: { $0.role == .system }) == nil {
                    let systemContent = selectedPrompt.contentForLanguage(selectedTextLanguage)
                    let systemMessage = ChatMessage(role: .system, content: systemContent)
                    chatSession?.insertSystemMessage(systemMessage)
                }

                // Start streaming formatting
                state = .formatting

                let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
                chatSession?.addMessage(assistantMessage)

                // FR-003 / FR-003a / FR-004: only the FIRST voice turn of the session
                // can receive the do-not-answer injection. Capture the flag value
                // before the await so the consumption is atomic with respect to
                // subsequent voice recordings in this session.
                let isFirstVoiceTurn = !didConsumeFirstVoiceTurn
                let shouldInjectDoNotAnswer = isFirstVoiceTurn && !selectedPrompt.answerQuestionsInFirstMessage
                let shouldInjectAnswerQuestion = isFirstVoiceTurn && selectedPrompt.answerQuestionsInFirstMessage
                // 014: single canonical assembly via SystemPromptBuilder. Base
                // prompt is taken from the English locale; output language is
                // enforced by Translate Response Language Override at the end
                // of the prompt.
                let enhancedSystemPrompt = SystemPromptBuilder.build(.init(
                    basePrompt: selectedPrompt.contentForLanguage(.en),
                    targetLanguage: selectedTextLanguage,
                    personalPreferences: settings.personalPreferencesText,
                    vocabularyEntries: vocabularyStore.entries,
                    injectDoNotAnswer: shouldInjectDoNotAnswer,
                    injectAnswerQuestion: shouldInjectAnswerQuestion
                ))
                // 014 FR-022: emit one structured diagnostic event per first
                // voice turn of a chat session, BEFORE the LLM network call so a
                // failed call still produces the event for triage.
                if isFirstVoiceTurn {
                    let overrideSource: String
                    if let initial = initialTextLanguageOnOpen, initial != selectedTextLanguage {
                        overrideSource = "user-changed"
                    } else {
                        overrideSource = "settings-default"
                    }
                    logApi.info(
                        "Language resolution for first voice turn",
                        metadata: [
                            "resolvedTargetLanguage": selectedTextLanguage.rawValue,
                            "directiveInjected": "true",
                            "overrideSource": overrideSource,
                            "isFirstVoiceTurn": "true"
                        ]
                    )
                }
                didConsumeFirstVoiceTurn = true

                let firstTurnMessages: [(role: String, content: String)] = [
                    ("system", enhancedSystemPrompt),
                    ("user", rawText)
                ]

                if let streaming = streamingService {
                    do {
                        let stream = streaming.streamChat(
                            messages: firstTurnMessages,
                            model: settings.selectedLLMModel
                        )
                        var accumulated = ""
                        for try await token in stream {
                            accumulated += token
                            chatSession?.updateLastAssistantContent(accumulated)
                        }
                    } catch let error as RecordingError where error.isModelUnavailable {
                        // Same model would be rejected again — show the error (FR-040)
                        throw error
                    } catch {
                        // Fallback to non-streaming on SSE error. The service
                        // accepts the already-assembled prompt as-is.
                        let formattedText = try await formattingService.format(
                            text: rawText,
                            systemPrompt: enhancedSystemPrompt,
                            textLanguage: selectedTextLanguage,
                            model: settings.selectedLLMModel
                        )
                        chatSession?.updateLastAssistantContent(formattedText)
                    }
                } else {
                    let formattedText: String
                    if let router = processingRouter {
                        formattedText = try await router.process(
                            text: rawText,
                            systemPrompt: enhancedSystemPrompt
                        )
                    } else {
                        formattedText = try await formattingService.format(
                            text: rawText,
                            systemPrompt: enhancedSystemPrompt,
                            textLanguage: selectedTextLanguage,
                            model: settings.selectedLLMModel
                        )
                    }
                    chatSession?.updateLastAssistantContent(formattedText)
                }

                assistantMessage.isStreaming = false
                windowPhase = .postProcessing
                expandToPostProcessingHeight()
                state = .idle

            } catch {
                state = .error(mapError(error))
            }
        }
    }

    private func expandToPostProcessingHeight() {
        guard let screen = NSScreen.main else { return }
        let targetHeight = screen.visibleFrame.height * 0.5
        overlayManager.updateHeight(targetHeight)
    }

    /// Sync audio save settings from AppSettings to capture service before recording.
    private func syncAudioSaveSettings() {
        audioCaptureService.audioSaveSettings = (
            enabled: settings.isAudioSaveEnabled,
            folderBookmark: settings.audioSaveFolderBookmark
        )
    }

    func resetRecording() {
        stopTimers()
        audioCaptureService.resetRecording()
        state = .idle
    }

    /// T025: Cleanup all resources when overlay window closes (FR-020)
    func cleanup() {
        cancelStart(trigger: "close")
        stopTimers()
        stopInputTimers()
        audioCaptureService.resetRecording()
        streamingService?.cancelStream()
        // 014 FR-015: discard the floating-window override snapshot on close
        // so the next showOverlay() re-initializes from the (possibly
        // updated) Settings default.
        initialTextLanguageOnOpen = nil
    }

    func copyMarkdown() {
        guard let text = chatSession?.lastAssistantMessage?.content, !text.isEmpty else { return }
        pasteService.copyToClipboard(text)
        dismissOverlay()
    }

    func copyPlainText() {
        guard let text = chatSession?.lastAssistantMessage?.content, !text.isEmpty else { return }
        pasteService.copyPlainTextToClipboard(text)
        dismissOverlay()
    }

    func pastePlainText() {
        guard let text = chatSession?.lastAssistantMessage?.content, !text.isEmpty else { return }

        Task { @MainActor in
            do {
                try await pasteService.pastePlainText(text)
                dismissOverlay()
            } catch let error as PasteError {
                switch error {
                case .accessibilityNotGranted:
                    state = .error(.accessibilityNotGranted)
                case .targetAppUnavailable:
                    state = .error(.pasteTargetUnavailable)
                case .eventSourceUnavailable:
                    pasteService.copyPlainTextToClipboard(text)
                    dismissOverlay()
                }
            } catch {
                pasteService.copyPlainTextToClipboard(text)
                dismissOverlay()
            }
        }
    }

    func pasteMarkdown() {
        guard let text = chatSession?.lastAssistantMessage?.content, !text.isEmpty else { return }

        Task { @MainActor in
            do {
                try await pasteService.pasteText(text)
                dismissOverlay()
            } catch let error as PasteError {
                switch error {
                case .accessibilityNotGranted:
                    state = .error(.accessibilityNotGranted)
                case .targetAppUnavailable:
                    state = .error(.pasteTargetUnavailable)
                case .eventSourceUnavailable:
                    pasteService.copyToClipboard(text)
                    dismissOverlay()
                }
            } catch {
                pasteService.copyToClipboard(text)
                dismissOverlay()
            }
        }
    }

    func dismissOverlay() {
        // T031: endFlow при закрытии overlay
        if let flowId = currentFlowId {
            _ = FlowTracker.shared.endFlow(flowId)
            currentFlowId = nil
        }

        cancelStart(trigger: "esc")
        stopTimers()
        audioCaptureService.resetRecording()
        streamingService?.cancelStream()
        targetAppTracker.stopTracking()
        overlayManager.dismiss()
        state = .idle
        windowPhase = .preProcessing
        inputRecordingState = .idle
        chatSession = nil
        inputText = ""
        copyConfirmation = false
        savedAudioData = nil
    }

    func openSettings() {
        dismissOverlay()
        NotificationCenter.default.post(name: .openSettingsFromOverlay, object: nil)
    }

    // MARK: - Keyboard

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let eventModifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])

        // Recording start/stop handled via GlobalHotkeyService → toggleOverlay → handleRecordingKey
        // No in-window recording hotkey — only the global shortcut

        // Block ⌥-generated characters (ç, √) from being typed — FR-011
        if eventModifiers == [.option, .shift] || eventModifiers == .option {
            return handleOptionKey(event.keyCode, withShift: eventModifiers.contains(.shift))
        }

        // ⌘-shortcuts — allow standard macOS editing in input
        if eventModifiers == .command {
            switch event.keyCode {
            case 13:  // ⌘W
                dismissOverlay()
                return true
            case 8, 9, 0, 7, 6:  // ⌘C, ⌘V, ⌘A, ⌘X, ⌘Z — pass through for input
                return false
            default:
                break
            }
        }

        // ⌘⇧Z — Redo in input, pass through
        if eventModifiers == [.command, .shift] && event.keyCode == 6 {
            return false
        }

        switch event.keyCode {
        case 53:  // Escape
            dismissOverlay()
            return true
        case 36 where windowPhase == .postProcessing && eventModifiers.isEmpty:  // Enter
            sendMessage()
            return true
        case 18, 19, 20:
            return eventModifiers.isEmpty && handleNumberKey(event.keyCode)
        default:
            return false
        }
    }

    /// ⌥C/⌥V copy or paste Markdown, ⌥⇧C/⌥⇧V plain text (post-processing only).
    /// Every other ⌥ or ⌥⇧ combination is swallowed so it can't type ç, √ … (FR-011).
    private func handleOptionKey(_ keyCode: UInt16, withShift: Bool) -> Bool {
        guard windowPhase == .postProcessing else { return true }
        switch (keyCode, withShift) {
        case (8, true): copyPlainText()    // ⌥⇧C
        case (9, true): pastePlainText()   // ⌥⇧V
        case (8, false): copyMarkdown()    // ⌥C
        case (9, false): pasteMarkdown()   // ⌥V
        default: break
        }
        return true
    }

    /// spec 015 (US4, R29): 1 microphone, 2 output language, 3 prompt — matches the bar order;
    /// pre-recording phase while idle, recording or showing an error.
    private func handleNumberKey(_ keyCode: UInt16) -> Bool {
        guard canCycleSelections else { return false }
        switch keyCode {
        case 18: cycleMicrophone()     // 1
        case 19: cycleTextLanguage()   // 2
        case 20: cyclePrompt()         // 3
        default: return false
        }
        return true
    }

    func retryFromError() {
        if let audioData = savedAudioData {
            state = .transcribing
            Task { @MainActor in
                do {
                    let rawText: String
                    if let router = processingRouter {
                        rawText = try await router.transcribe(audioData: audioData, language: selectedVoiceLanguage)
                    } else {
                        rawText = try await transcriptionService.transcribe(
                            audioData: audioData,
                            language: selectedVoiceLanguage,
                            model: settings.selectedSTTModel
                        )
                    }

                    guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        state = .error(.emptyTranscription)
                        return
                    }

                    let transcriptionMessage = ChatMessage(role: .transcription, content: rawText)
                    chatSession?.addMessage(transcriptionMessage)

                    state = .formatting
                    let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
                    chatSession?.addMessage(assistantMessage)

                    // 014: assemble once via SystemPromptBuilder. This path is a
                    // continuation/post-processing turn — no DoNotAnswer.
                    let inputSystemPrompt = SystemPromptBuilder.build(.init(
                        basePrompt: selectedPrompt.contentForLanguage(.en),
                        targetLanguage: selectedTextLanguage,
                        personalPreferences: settings.personalPreferencesText,
                        vocabularyEntries: vocabularyStore.entries,
                        injectDoNotAnswer: false
                    ))

                    if let streaming = streamingService {
                        do {
                            let stream = streaming.streamFormat(
                                text: rawText,
                                systemPrompt: inputSystemPrompt,
                                textLanguage: selectedTextLanguage,
                                model: settings.selectedLLMModel
                            )
                            var accumulated = ""
                            for try await token in stream {
                                accumulated += token
                                chatSession?.updateLastAssistantContent(accumulated)
                            }
                        } catch let error as RecordingError where error.isModelUnavailable {
                            // Same model would be rejected again — show the error (FR-040)
                            throw error
                        } catch {
                            // Fallback to non-streaming on SSE error.
                            let formattedText = try await formattingService.format(
                                text: rawText,
                                systemPrompt: inputSystemPrompt,
                                textLanguage: selectedTextLanguage,
                                model: settings.selectedLLMModel
                            )
                            chatSession?.updateLastAssistantContent(formattedText)
                        }
                    } else {
                        let formattedText = try await formattingService.format(
                            text: rawText,
                            systemPrompt: inputSystemPrompt,
                            textLanguage: selectedTextLanguage,
                            model: settings.selectedLLMModel
                        )
                        chatSession?.updateLastAssistantContent(formattedText)
                    }

                    assistantMessage.isStreaming = false
                    windowPhase = .postProcessing
                    expandToPostProcessingHeight()
                    state = .idle
                } catch {
                    state = .error(mapError(error))
                }
            }
        } else {
            startRecording()
        }
    }

    /// Internal (not private) so tests can drive the hotkey path without showing the overlay.
    func handleRecordingKey() {
        // In postProcessing: ⌥Space toggles voice input in input field
        if windowPhase == .postProcessing {
            switch inputRecordingState {
            case .idle:
                startInputRecording()
            case .recording:
                stopInputRecording()
            case .processing:
                break
            }
            return
        }

        // In preProcessing: ⌥Space toggles main recording
        switch state {
        case .idle:
            startRecording()
        case .starting:
            cancelStart(trigger: "hotkey")
        case .recording:
            stopRecording()
        case .error:
            retryFromError()
        default:
            break
        }
    }

    // MARK: - Timers

    private func startTimers() {
        let maxSeconds = settings.maxRecordingDuration.timeInterval

        // T020: Timer on main RunLoop — assumeIsolated safe (R-006)
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let start = self.recordingStart else { return }
                let duration = Date().timeIntervalSince(start)
                let remaining = max(0, maxSeconds - duration)
                self.state = .recording(duration: duration, remaining: remaining)
                if remaining <= 0 {
                    self.stopRecording()
                }
            }
        }

        // T021: Use updateLevelsFromAtomic() (FR-016)
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.audioCaptureService.updateLevelsFromAtomic()
                self.audioLevel = self.audioCaptureService.audioLevel
            }
        }
    }

    private func stopTimers() {
        durationTimer?.invalidate()
        durationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
    }

    // MARK: - Error Mapping

    private func mapError(_ error: Error) -> RecordingError {
        if let recordingError = error as? RecordingError {
            return recordingError
        }
        if let setupError = error as? AudioSetupError {
            return .recordingStartFailed(setupError.startFailureReason, deviceName: startDeviceName)
        }
        if let processingError = error as? ProcessingError {
            switch processingError {
            case .apiKeyMissing:
                return .apiKeyNotConfigured
            case .transcriptionFailed(let inner):
                return .transcriptionFailed(inner.localizedDescription)
            case .formattingFailed(let inner):
                return .formattingFailed(inner.localizedDescription)
            case .modelNotSupported(let model):
                return .formattingFailed(LocalizationManager.shared.string("error.modelNotSupported", args: model))
            }
        }
        let nsError = error as NSError
        if nsError.domain == "com.apple.coreaudio.avfaudio" {
            return .microphoneNotAvailable
        }
        return .transcriptionFailed(error.localizedDescription)
    }
}

// MARK: - Watchdog stage (spec 015, T058)

extension RecordingViewModel {
    nonisolated static func watchdogStage(for state: RecordingState) -> String {
        switch state {
        case .idle: return "idle"
        case .starting(let attempt): return "starting.\(attempt)"
        case .recording: return "recording"
        case .transcribing: return "transcribing"
        case .formatting: return "formatting"
        case .error: return "error"
        }
    }
}

// MARK: - AppStateProvider (T036)

extension RecordingViewModel: @preconcurrency AppStateProvider {
    func currentAppState() -> AppState {
        let status: String
        switch state {
        case .idle: status = "idle"
        case .starting: status = "starting"
        case .recording: status = "recording"
        case .transcribing: status = "transcribing"
        case .formatting: status = "formatting"
        case .error: status = "error"
        }

        let duration: Double?
        if let start = recordingStart {
            duration = Date().timeIntervalSince(start)
        } else {
            duration = nil
        }

        let operation: String?
        switch state {
        case .transcribing: operation = "transcription"
        case .formatting: operation = "formatting"
        default: operation = nil
        }

        return AppState(
            activeDevice: selectedAudioDeviceID,
            recordingStatus: status,
            recordingDuration: duration,
            currentOperation: operation
        )
    }
}
