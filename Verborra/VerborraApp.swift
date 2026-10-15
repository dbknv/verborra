import SwiftUI

// MARK: - App Entry Point (T017)

@main
struct VerborraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Verborra", systemImage: "mic.fill") {
            MenuBarView()
                .environment(appDelegate.appSettings)
                .environment(LocalizationManager.shared)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(appDelegate.appSettings)
                .environment(appDelegate.promptsStore)
                .environment(appDelegate.vocabularyStore)
                .environment(LocalizationManager.shared)
                .environment(appDelegate.appController?.audioDeviceManager)
                .environment(appDelegate.loginItemService)
                .environment(appDelegate.hotkeyService)
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appSettings = AppSettings()
    let promptsStore = PromptsStore()
    let vocabularyStore = VocabularyStore()
    private(set) var appController: AppController?
    /// spec 015 (US1): the only owner of SMAppService calls.
    private(set) lazy var loginItemService = LoginItemService(intentStore: appSettings)
    /// spec 015 (US3): created here, not in AppController, so the Settings scene (built before
    /// `applicationDidFinishLaunching`) gets a non-nil service for the shortcut recorder.
    let hotkeyService = GlobalHotkeyService()
    private var onboardingViewModel: OnboardingViewModel?
    private let mainThreadWatchdog = MainThreadWatchdog()
    private var onboardingWindow: OnboardingWindow?
    private let lifecycleLog = DiagnosticLogger.logger(for: .lifecycle)

    /// Stored OpenSettingsAction captured from SwiftUI environment
    static var openSettingsAction: (() -> Void)?

    // MARK: - Lifecycle (T016, T017, T064)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // spec 015 (R11): log uncaught exceptions in all builds; crash on them in DEBUG only
        NSSetUncaughtExceptionHandler { exception in
            DiagnosticLogger.logger(for: .lifecycle).error(
                "Uncaught exception",
                parameters: [
                    "name": exception.name.rawValue,
                    "reason": exception.reason ?? "",
                    "thread": Thread.isMainThread ? "main" : "background",
                    "callStack": exception.callStackSymbols.prefix(20).joined(separator: "\n")
                ]
            )
            JSONLFileWriter.shared.flushSync()
        }
        #if DEBUG
        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
        #endif

        // T016: Инициализация системы логирования
        DiagnosticLogger.logLevelProvider = { [weak self] in
            self?.appSettings.logLevel ?? .info
        }
        DiagnosticLogger.updateFilterSnapshot(level: appSettings.logLevel)
        JSONLFileWriter.shared.start()
        LogFileManager.shared.cleanupOldLogs(retentionHours: appSettings.logRetentionHours)

        lifecycleLog.info("Application launched", metadata: [
            "sessionId": DiagnosticLogger.sessionId,
            "logLevel": appSettings.logLevel.displayName
        ])

        // spec 015 (US2, FR-011): report main-thread stalls longer than 2 s
        mainThreadWatchdog.start()

        // spec 015 (US3): the old in-window recording key is gone
        UserDefaults.standard.removeObject(forKey: "recordingKeyCode")
        UserDefaults.standard.removeObject(forKey: "recordingModifiers")

        // spec 015 (US7): move users off removed models before anything reads the model settings
        ModelSelectionMigrator.run()

        // spec 015 (US1): keep the login item in line with the user's choice (contracts/login-item.md)
        loginItemService.reconcileAtLaunch(onboardingCompleted: appSettings.isOnboardingCompleted)

        appController = AppController(
            settings: appSettings,
            promptsStore: promptsStore,
            vocabularyStore: vocabularyStore,
            hotkeyService: hotkeyService
        )
        showOnboardingIfNeeded()

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenSettings),
            name: .openSettingsFromOverlay, object: nil
        )

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleUILanguageChange(_:)),
            name: .uiLanguageDidChange, object: nil
        )
    }

    // T017
    func applicationWillTerminate(_ notification: Notification) {
        lifecycleLog.info("Application will terminate")
        JSONLFileWriter.shared.flushSync()
        JSONLFileWriter.shared.stop()
    }

    // T064
    func applicationDidBecomeActive(_ notification: Notification) {
        lifecycleLog.info("Application did become active")
        loginItemService.refresh()
    }

    func applicationDidResignActive(_ notification: Notification) {
        lifecycleLog.info("Application did resign active")
    }

    @objc private func handleUILanguageChange(_ notification: Notification) {
        guard let language = notification.userInfo?["language"] as? SupportedLanguage else { return }
        promptsStore.updateSystemPrompts(for: language)
    }

    @objc private func handleOpenSettings() {
        NSApp.setActivationPolicy(.regular)
        Self.openSettingsAction?()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows
                .first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }?
                .makeKeyAndOrderFront(nil)
        }
    }

    private func showOnboardingIfNeeded() {
        if onboardingViewModel == nil {
            onboardingViewModel = OnboardingViewModel(appSettings: appSettings, loginItemService: loginItemService)
        }
        // T010 [US1]: If microphone not granted, show onboarding regardless of isOnboardingCompleted (FR-001, FR-002)
        let needsMicrophone = PermissionManager.shared.microphoneStatus != .granted
        let shouldShow = onboardingViewModel?.shouldShowOnboarding == true || needsMicrophone
        guard shouldShow, onboardingWindow == nil else { return }
        guard let onboardingViewModel else { return }

        let window = OnboardingWindow(viewModel: onboardingViewModel) { [weak self] in
            self?.onboardingWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
        onboardingWindow = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - AppController

@MainActor
@Observable
final class AppController {
    let recordingViewModel: RecordingViewModel
    let audioDeviceManager: AudioDeviceManager
    /// spec 015 (US3): Carbon or Fn event tap, depending on the shortcut.
    let hotkeyService: GlobalHotkeyService

    let vocabularyStore: VocabularyStore

    init(
        settings: AppSettings,
        promptsStore: PromptsStore,
        vocabularyStore: VocabularyStore,
        hotkeyService: GlobalHotkeyService
    ) {
        self.vocabularyStore = vocabularyStore
        let audioCaptureService = AudioCaptureService()
        let transcriptionService = TranscriptionService(apiKeyProvider: { settings.apiKey })
        let formattingService = FormattingService(apiKeyProvider: { settings.apiKey })
        let streamingService = StreamingFormattingService(apiKeyProvider: { settings.apiKey })
        let processingRouter = ProcessingRouter(settings: settings, apiKeyProvider: { settings.apiKey })

        // 009-audio-device-selector: AudioDeviceManager via CoreAudioDeviceProvider
        let audioDeviceProvider = CoreAudioDeviceProvider()
        let audioDeviceManager = AudioDeviceManager(provider: audioDeviceProvider, settings: settings)
        self.audioDeviceManager = audioDeviceManager

        let recordingVM = RecordingViewModel(
            audioCaptureService: audioCaptureService,
            transcriptionService: transcriptionService,
            formattingService: formattingService,
            pasteService: PasteService(targetPIDProvider: { 0 }),
            settings: settings,
            promptsStore: promptsStore,
            vocabularyStore: vocabularyStore,
            audioDeviceManager: audioDeviceManager,
            processingRouter: processingRouter,
            streamingService: streamingService
        )

        self.recordingViewModel = recordingVM
        self.hotkeyService = hotkeyService

        let targetTracker = recordingVM.targetAppTracker
        let pasteService = PasteService(targetPIDProvider: { targetTracker.targetPID })
        recordingVM.updatePasteService(pasteService)

        hotkeyService.start { [weak recordingVM] in
            recordingVM?.toggleOverlay()
        }
    }
}

// MARK: - MenuBarView

struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(AppSettings.self) private var appSettings
    @Environment(LocalizationManager.self) private var l10n

    var body: some View {
        // Capture openSettings for programmatic use from outside SwiftUI
        // swiftlint:disable:next redundant_discardable_let - `let _` is required inside a view builder
        let _ = AppDelegate.openSettingsAction = { [openSettings] in openSettings() }

        Button(l10n.string("menu.settings")) {
            NSApp.setActivationPolicy(.regular)
            openSettings()
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows
                    .first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }?
                    .makeKeyAndOrderFront(nil)
            }
        }
        .keyboardShortcut(",", modifiers: .command)
        .disabled(!appSettings.isOnboardingCompleted)

        Divider()

        Button(l10n.string("menu.quit")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

extension Notification.Name {
    static let openSettingsFromOverlay = Notification.Name("openSettingsFromOverlay")
    static let uiLanguageDidChange = Notification.Name("uiLanguageDidChange")
}
