import AppKit
import AVFoundation
import Foundation
import KeyboardShortcuts
import ServiceManagement

// MARK: - SettingsViewModel (T036, T050)

@MainActor
@Observable
final class SettingsViewModel {
    var settings: AppSettings
    var promptsStore: PromptsStore
    var vocabularyStore: VocabularyStore
    var apiKeyInput: String = ""
    var isApiKeySaved = false
    var isValidating = false
    var validationResult: Bool?
    var launchAtLoginError: String?

    // T015 [US2]: Use PermissionManager instead of local state (FR-015)
    var isAccessibilityGranted: Bool {
        PermissionManager.shared.accessibilityStatus == .granted
    }
    var isMicrophoneGranted: Bool {
        PermissionManager.shared.microphoneStatus == .granted
    }

    // Prompt editing
    var selectedPromptID: UUID?
    var editingPromptName: String = ""
    var editingPromptContent: String = ""
    /// 013: Toggle state for the active prompt's `answerQuestionsInFirstMessage`.
    /// Mirrors the persisted value while the user is editing; saved via `saveCurrentPrompt()`.
    var editingAnswerInFirstMessage: Bool = false

    private let apiKeyValidationService: APIKeyValidationServiceProtocol
    let audioCaptureService: AudioCaptureServiceProtocol
    let audioDeviceManager: AudioDeviceManager
    private let log = DiagnosticLogger.logger(for: .settings)

    /// Non-System-Default devices for the settings picker.
    var audioDevices: [AudioDevice] {
        audioDeviceManager.devices.filter { !$0.isSystemDefaultEntry }
    }

    var selectedPrompt: SystemPrompt? {
        guard let id = selectedPromptID else { return nil }
        return promptsStore.prompts.first(where: { $0.id == id })
    }

    init(
        settings: AppSettings,
        promptsStore: PromptsStore,
        vocabularyStore: VocabularyStore,
        audioDeviceManager: AudioDeviceManager,
        apiKeyValidationService: APIKeyValidationServiceProtocol = APIKeyValidationService(),
        audioCaptureService: AudioCaptureServiceProtocol? = nil
    ) {
        self.settings = settings
        self.promptsStore = promptsStore
        self.vocabularyStore = vocabularyStore
        self.audioDeviceManager = audioDeviceManager
        self.apiKeyValidationService = apiKeyValidationService
        self.audioCaptureService = audioCaptureService ?? AudioCaptureService()
        self.apiKeyInput = settings.apiKey

        if let first = promptsStore.prompts.first {
            selectPrompt(first)
        }

        // Refresh editing fields when UI language changes (system prompts update)
        NotificationCenter.default.addObserver(
            forName: .uiLanguageDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            // Defer to ensure PromptsStore has already processed the same notification
            DispatchQueue.main.async {
                self?.refreshSelectedPrompt()
            }
        }
    }

    /// Re-read selected prompt from store (e.g. after language change updates system prompts)
    private func refreshSelectedPrompt() {
        guard let id = selectedPromptID,
              let prompt = promptsStore.prompts.first(where: { $0.id == id }) else { return }
        editingPromptName = prompt.name
        editingPromptContent = prompt.content
        editingAnswerInFirstMessage = prompt.answerQuestionsInFirstMessage
    }

    // MARK: - API Key

    func saveApiKey() {
        settings.apiKey = apiKeyInput
        isApiKeySaved = true
        validationResult = nil

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            isApiKeySaved = false
        }
    }

    func validateAndSaveApiKey() {
        isValidating = true
        validationResult = nil

        Task { @MainActor in
            do {
                let isValid = try await apiKeyValidationService.validate(apiKey: apiKeyInput)
                validationResult = isValid
                if isValid {
                    settings.apiKey = apiKeyInput
                    isApiKeySaved = true
                    try? await Task.sleep(for: .seconds(2))
                    isApiKeySaved = false
                }
            } catch {
                validationResult = false
            }
            isValidating = false
        }
    }

    func validateApiKey() -> Bool {
        apiKeyInput.hasPrefix("sk-") && apiKeyInput.count > 20
    }

    // MARK: - Prompts (T050)

    func selectPrompt(_ prompt: SystemPrompt) {
        selectedPromptID = prompt.id
        editingPromptName = prompt.name
        editingPromptContent = prompt.content
        editingAnswerInFirstMessage = prompt.answerQuestionsInFirstMessage
    }

    func addPrompt() {
        let prompt = SystemPrompt(
            name: LocalizationManager.shared.string("settings.prompts.newPrompt"),
            content: ""
        )
        promptsStore.addPrompt(prompt)
        selectPrompt(prompt)
    }

    func saveCurrentPrompt() {
        guard let id = selectedPromptID,
              var prompt = promptsStore.prompts.first(where: { $0.id == id }) else { return }
        // FR-009b: read-only prompts (currently only simple-voice-to-text) cannot have
        // their name/content edited. The answer-toggle is still user-settable on
        // them — handled via `persistAnswerInFirstMessage()` (auto-saved on change
        // from the UI, since the read-only branch hides the Save button).
        guard !prompt.isReadOnly else { return }

        prompt.name = editingPromptName
        prompt.content = editingPromptContent
        prompt.answerQuestionsInFirstMessage = editingAnswerInFirstMessage
        promptsStore.updatePrompt(prompt)
    }

    /// Persists the current value of `editingAnswerInFirstMessage` to the
    /// selected prompt, bypassing the read-only guard. Called from the
    /// settings UI on toggle change so that built-in prompts (which have no
    /// Save button) still pick up the change. No-op if the value is unchanged.
    func persistAnswerInFirstMessage() {
        guard let id = selectedPromptID else { return }
        promptsStore.setAnswerInFirstMessage(promptID: id, value: editingAnswerInFirstMessage)
    }

    func deletePrompt(_ id: UUID) {
        // FR-009b: read-only prompts cannot be deleted by user.
        if let prompt = promptsStore.prompts.first(where: { $0.id == id }), prompt.isReadOnly {
            return
        }
        promptsStore.deletePrompt(id)
        if selectedPromptID == id {
            if let first = promptsStore.prompts.first {
                selectPrompt(first)
            }
        }
    }

    func setDefaultPrompt(_ id: UUID) {
        promptsStore.setDefault(id)
    }

    // MARK: - Hotkey Conflict Detection (T036)

    var hasRecordingHotkeyConflict: Bool {
        guard let overlayShortcut = KeyboardShortcuts.getShortcut(for: .toggleOverlay) else {
            return false
        }
        let overlayKeyCode = Int(overlayShortcut.carbonKeyCode)
        let overlayModifiers = Int(overlayShortcut.carbonModifiers)
        return overlayKeyCode == settings.recordingKeyCode
            && overlayModifiers == settings.recordingModifiers
    }

    // MARK: - Onboarding (Debug)

    func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "onboardingCompleted")
    }

    // MARK: - System

    // T068: Логирование автозапуска (SMAppService)
    func updateLaunchAtLogin(_ enabled: Bool) {
        log.info("Launch at login", metadata: ["enabled": "\(enabled)"])
        settings.launchAtLogin = enabled
        do {
            if enabled {
                try SMAppService.mainApp.register()
                log.info("SMAppService registered")
            } else {
                try SMAppService.mainApp.unregister()
                log.info("SMAppService unregistered")
            }
            launchAtLoginError = nil
        } catch {
            log.error("SMAppService failed", parameters: ["enabled": "\(enabled)"], errorCode: error.localizedDescription)
            launchAtLoginError = error.localizedDescription
        }
    }
}
