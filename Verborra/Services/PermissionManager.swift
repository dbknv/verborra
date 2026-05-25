import AVFoundation
import AppKit
import Foundation

// MARK: - PermissionManager (T003)

@Observable
final class PermissionManager: PermissionChecking {
    static let shared = PermissionManager()
    private let log = DiagnosticLogger.logger(for: .permissions)

    // Observable properties (T003)
    private(set) var microphoneStatus: PermissionStatus = .notDetermined
    private(set) var accessibilityStatus: PermissionStatus = .notDetermined

    // Internal state (T003)
    private var monitoringCount = 0
    private var pollingTimer: Timer?
    private var isRequestInProgress = false
    private var hasPromptedAccessibility: Bool {
        get { UserDefaults.standard.bool(forKey: "hasPromptedAccessibility") }
        set { UserDefaults.standard.set(newValue, forKey: "hasPromptedAccessibility") }
    }

    private init() {
        checkMicrophoneStatus()
        checkAccessibilityStatus()
    }

    // For testing only
    init(forTesting: Bool) {
        checkMicrophoneStatus()
        checkAccessibilityStatus()
    }

    // MARK: - Status Checks

    /// T004: Check microphone status without side effects (R1)
    func checkMicrophoneStatus() {
        let previousStatus = microphoneStatus
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .notDetermined:
            microphoneStatus = .notDetermined
        case .authorized:
            microphoneStatus = .granted
        case .denied:
            microphoneStatus = .denied
        case .restricted:
            microphoneStatus = .restricted
        @unknown default:
            microphoneStatus = .notDetermined
        }
        // T043: Логирование при изменении статуса
        if microphoneStatus != previousStatus {
            log.info("Microphone status changed", metadata: [
                "from": "\(previousStatus)",
                "to": "\(microphoneStatus)"
            ])
        }
    }

    /// T005: Check accessibility status without side effects (R2)
    func checkAccessibilityStatus() {
        let previousStatus = accessibilityStatus
        let trusted = AXIsProcessTrusted()
        if trusted {
            accessibilityStatus = .granted
        } else if hasPromptedAccessibility {
            accessibilityStatus = .denied
        } else {
            accessibilityStatus = .notDetermined
        }
        // T043: Логирование при изменении статуса
        if accessibilityStatus != previousStatus {
            log.info("Accessibility status changed", metadata: [
                "from": "\(previousStatus)",
                "to": "\(accessibilityStatus)"
            ])
        }
    }

    // MARK: - Access Requests

    /// T006/T033: Request microphone access — three-branch logic (R3, FR-016–FR-020)
    func requestMicrophoneAccess() {
        guard !isRequestInProgress else { return }

        switch microphoneStatus {
        case .notDetermined:
            isRequestInProgress = true
            log.info("Requesting microphone access")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.microphoneStatus = granted ? .granted : .denied
                    self?.isRequestInProgress = false
                    self?.log.info("Microphone access result", metadata: ["granted": "\(granted)"])
                    if !granted {
                        self?.log.error("Microphone access denied by user", errorCode: "microphonePermissionDenied")
                    }
                }
            }
        case .denied:
            // T033: Show instruction alert instead of opening System Settings directly
            // TCC cache prevents detecting permission changes without app restart (R8)
            showMicrophoneDeniedAlert()
        case .restricted:
            openSystemSettings(for: .microphone)
        case .granted:
            break
        }
    }

    // MARK: - Microphone Denied Alert (T034, T035)

    /// T034/T035: Show NSAlert explaining restart requirement for .denied microphone (R9, R10)
    private func showMicrophoneDeniedAlert() {
        let l10n = LocalizationManager.shared

        let alert = NSAlert()
        alert.messageText = l10n.string("permission.mic.denied.alert.title")
        alert.informativeText = l10n.string("permission.mic.denied.alert.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: l10n.string("permission.mic.denied.alert.confirm"))
        alert.addButton(withTitle: l10n.string("permission.mic.denied.alert.cancel"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // T035: Open System Settings, then quit after short delay (R10)
            openSystemSettings(for: .microphone)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        }
        // .alertSecondButtonReturn (Cancel) — do nothing (FR-019)
    }

    /// T007: Request accessibility access — two-branch logic (R4)
    func requestAccessibilityAccess() {
        guard !isRequestInProgress else { return }

        isRequestInProgress = true

        switch accessibilityStatus {
        case .notDetermined:
            // First time: show system dialog via AXIsProcessTrustedWithOptions
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            hasPromptedAccessibility = true
            accessibilityStatus = trusted ? .granted : .denied

        case .denied, .restricted:
            // Already prompted — open System Settings directly
            openSystemSettings(for: .accessibility)

        case .granted:
            break
        }

        isRequestInProgress = false
    }

    // MARK: - Monitoring (T008)

    /// T008: Start monitoring — reference counting pattern (R5)
    func startMonitoring() {
        monitoringCount += 1
        if monitoringCount == 1 {
            startPollingTimer()
        }
    }

    /// T008: Stop monitoring — reference counting pattern (R5)
    func stopMonitoring() {
        monitoringCount = max(monitoringCount - 1, 0)
        if monitoringCount == 0 {
            stopPollingTimer()
        }
    }

    // MARK: - Private

    private func startPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollStatuses()
        }
    }

    private func stopPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    /// T009: Detect status changes and publish via @Observable (R6)
    private func pollStatuses() {
        let previousMic = microphoneStatus
        let previousAcc = accessibilityStatus

        checkMicrophoneStatus()
        checkAccessibilityStatus()

        // T009: Status change detection — PermissionManager only publishes changes,
        // UI layer is responsible for calling NSApp.activate via .onChange(of:)
        _ = (previousMic != microphoneStatus || previousAcc != accessibilityStatus)
    }

    /// T028: Open system settings with error handling
    private func openSystemSettings(for type: PermissionType) {
        guard let url = URL(string: type.systemSettingsURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
