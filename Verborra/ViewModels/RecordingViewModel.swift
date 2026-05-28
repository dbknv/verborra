import Foundation
import SwiftUI

// MARK: - RecordingViewModel

@MainActor
@Observable
final class RecordingViewModel {
    // MARK: - State

    var state: RecordingState = .idle
    var windowPhase: WindowPhase = .preProcessing
    var inputRecordingState: InputRecordingState = .idle
    var audioLevel: Float = 0.0
    /// `true` after the first voice-transcribed turn of the current session has been
    /// dispatched to the LLM. Reset on new session / overlay re-show. Used to gate
    /// `DoNotAnswerInstruction` injection — applies ONLY to that first turn.
    private var didConsumeFirstVoiceTurn: Bool = false
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
    private var savedAudioData: Data?

    // MARK: - Logging (T031, T036)
    private let logUserAction = DiagnosticLogger.logger(for: .userAction)
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
        streamingService: StreamingFormattingServiceProtocol? = nil
    ) {
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

        self.audioCaptureService.onDeviceFallback = { @Sendable [weak self] fallbackDeviceName in
            guard let self else { return }
            // Engine failed on selected device — switch to System Default via standard flow
            self.switchAudioDevice(to: "")
        }

        self.audioDeviceManager.onBluetoothSwitchError = { [weak self] message in
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

    func changePrompt(_ prompt: SystemPrompt) {
        selectedPrompt = prompt
    }

    func changeVoiceLanguage(_ language: SupportedLanguage) {
        selectedVoiceLanguage = language
    }

    func changeTextLanguage(_ language: SupportedLanguage) {
        selectedTextLanguage = language
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
        changeTextLanguage(next)
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
        switchAudioDevice(to: newUID)
    }

    /// Active device switch task — cancelled on rapid re-switch (T021).
    private var switchTask: Task<Void, Never>?

    /// Switch audio device by UID. Empty string = System Default.
    func switchAudioDevice(to deviceUID: String) {
        guard deviceUID != audioDeviceManager.selectedDevice?.uid else { return }

        // T021/T023: Cancel previous in-flight switch
        switchTask?.cancel()
        switchTask = nil
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

        // If recording is active, restart with the new device
        if case .recording = state {
            switchTask = Task { @MainActor in
                audioCaptureService.resetRecording()
                guard !Task.isCancelled else { return }
                do {
                    // All BT devices need stabilization — rate can be stale
                    var needsBTSwitch = false
                    if let newDevice = audioDeviceManager.selectedDevice,
                       newDevice.transportType.isBluetooth,
                       !newDevice.isSystemDefaultEntry {
                        let _ = await audioDeviceManager.bluetoothProfileManager
                            .prepareForRecording(device: newDevice, context: .deviceSwitch)
                        needsBTSwitch = true
                    }

                    let captureDeviceID = resolveDeviceIDForCapture(uid: deviceUID)
                    syncAudioSaveSettings()
                    try await audioCaptureService.startRecording(
                        deviceID: captureDeviceID,
                        maxDuration: settings.maxRecordingDuration,
                        awaitBluetoothSwitch: needsBTSwitch
                    )
                    guard !Task.isCancelled else { return }
                    recordingStart = Date()
                    let maxSeconds = settings.maxRecordingDuration.timeInterval
                    state = .recording(duration: 0, remaining: maxSeconds)
                } catch {
                    guard !Task.isCancelled else { return }
                    state = .error(mapError(error))
                }
            }
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
                    let _ = await audioDeviceManager.bluetoothProfileManager
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

        targetAppTracker.startTracking()

        let contentView = OverlayContentView(viewModel: self)
        overlayManager.show(with: contentView)

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

        Task { @MainActor in
            do {
                let selectedDevice = audioDeviceManager.selectedDevice
                var needsBTSwitch = false

                // FR-031: All Bluetooth devices need stabilization —
                // even "already HFP" can have stale rate after A2DP restore
                if let device = selectedDevice,
                   device.transportType.isBluetooth,
                   !device.isSystemDefaultEntry {
                    let _ = await audioDeviceManager.bluetoothProfileManager
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
                state = .recording(duration: 0, remaining: maxSeconds)
                startTimers()
            } catch {
                state = .error(mapError(error))
            }
        }
    }

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
                let basePromptForFirstTurn = selectedPrompt.contentForLanguage(selectedTextLanguage)
                let shouldInjectDoNotAnswer = isFirstVoiceTurn && !selectedPrompt.answerQuestionsInFirstMessage
                // Compose the full system prompt: PromptEnhancer adds Response
                // Language / Personal Preferences / Vocabulary first, then we
                // append the DoNotAnswerInstruction LAST so the model sees it as
                // the highest-priority directive (small models like gpt-4.1-nano
                // weight later instructions more strongly).
                let enhancedSystemPrompt: String = {
                    let enhanced = PromptEnhancer().enhance(
                        basePrompt: basePromptForFirstTurn,
                        textLanguage: selectedTextLanguage,
                        vocabularyEntries: vocabularyStore.entries,
                        personalPreferences: settings.personalPreferencesText
                    )
                    if shouldInjectDoNotAnswer {
                        return enhanced + "\n\n## Critical Instruction\n\n"
                            + DoNotAnswerInstruction.text(for: selectedVoiceLanguage)
                    }
                    return enhanced
                }()
                didConsumeFirstVoiceTurn = true

                let firstTurnMessages: [(role: String, content: String)] = [
                    ("system", enhancedSystemPrompt),
                    ("user", rawText),
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
                    } catch {
                        // Fallback to non-streaming on SSE error — use the same
                        // composed system prompt.
                        let formattedText = try await formattingService.format(
                            text: rawText,
                            systemPrompt: basePromptForFirstTurn
                                + (shouldInjectDoNotAnswer
                                    ? "\n\n## Critical Instruction\n\n" + DoNotAnswerInstruction.text(for: selectedVoiceLanguage)
                                    : ""),
                            textLanguage: selectedTextLanguage,
                            model: settings.selectedLLMModel,
                            vocabularyEntries: vocabularyStore.entries,
                            personalPreferences: settings.personalPreferencesText
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
        stopTimers()
        stopInputTimers()
        audioCaptureService.resetRecording()
        streamingService?.cancelStream()
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

        // Recording start/stop handled via global HotkeyService → toggleOverlay → handleRecordingKey
        // No in-window recording hotkey — only global ⌥Space

        // Block ⌥-generated characters (ç, √) from being typed — FR-011
        // Check ⌥⇧ BEFORE ⌥ to avoid ⌥⇧C falling into ⌥C branch
        if eventModifiers == [.option, .shift] {
            if windowPhase == .postProcessing {
                if event.keyCode == 8 { copyPlainText(); return true }   // ⌥⇧C
                if event.keyCode == 9 { pastePlainText(); return true }  // ⌥⇧V
            }
            return true // block other ⌥⇧-combinations
        }

        if eventModifiers == .option {
            if windowPhase == .postProcessing {
                if event.keyCode == 8 { copyMarkdown(); return true }    // ⌥C
                if event.keyCode == 9 { pasteMarkdown(); return true }   // ⌥V
            }
            return true // block other ⌥-combinations
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
        case 36:  // Enter
            if windowPhase == .postProcessing && eventModifiers.isEmpty {
                sendMessage()
                return true
            }
        case 18:  // 1 — cycle microphone
            if windowPhase == .preProcessing && eventModifiers.isEmpty {
                cycleMicrophone()
                return true
            }
        case 19:  // 2 — cycle text language (was voice language before 011-language-ui-rework)
            if windowPhase == .preProcessing && eventModifiers.isEmpty {
                cycleTextLanguage()
                return true
            }
        default:
            break
        }
        return false
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

                    if let streaming = streamingService {
                        do {
                            let stream = streaming.streamFormat(
                                text: rawText,
                                systemPrompt: selectedPrompt.contentForLanguage(selectedTextLanguage),
                                textLanguage: selectedTextLanguage,
                                model: settings.selectedLLMModel,
                                vocabularyEntries: vocabularyStore.entries,
                                personalPreferences: settings.personalPreferencesText
                            )
                            var accumulated = ""
                            for try await token in stream {
                                accumulated += token
                                chatSession?.updateLastAssistantContent(accumulated)
                            }
                        } catch {
                            // Fallback to non-streaming on SSE error
                            let formattedText = try await formattingService.format(
                                text: rawText,
                                systemPrompt: selectedPrompt.contentForLanguage(selectedTextLanguage),
                                textLanguage: selectedTextLanguage,
                                model: settings.selectedLLMModel,
                                vocabularyEntries: vocabularyStore.entries,
                                personalPreferences: settings.personalPreferencesText
                            )
                            chatSession?.updateLastAssistantContent(formattedText)
                        }
                    } else {
                        let formattedText = try await formattingService.format(
                            text: rawText,
                            systemPrompt: selectedPrompt.contentForLanguage(selectedTextLanguage),
                            textLanguage: selectedTextLanguage,
                            model: settings.selectedLLMModel,
                            vocabularyEntries: vocabularyStore.entries,
                            personalPreferences: settings.personalPreferencesText
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

    private func handleRecordingKey() {
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

// MARK: - AppStateProvider (T036)

extension RecordingViewModel: @preconcurrency AppStateProvider {
    func currentAppState() -> AppState {
        let status: String
        switch state {
        case .idle: status = "idle"
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
