import AVFoundation
import Foundation
import SwiftUI

// MARK: - OnboardingServiceProtocol

@MainActor
protocol OnboardingServiceProtocol {
    var shouldShowOnboarding: Bool { get }
    var currentStep: OnboardingStep { get set }
    func completeOnboarding()
    func resetOnboarding()
}

// MARK: - OnboardingViewModel

@MainActor
@Observable
final class OnboardingViewModel: OnboardingServiceProtocol {
    var currentStep: OnboardingStep
    var audioLevel: Float = 0.0
    private let log = DiagnosticLogger.logger(for: .lifecycle)

    // T014 [US2]: Use PermissionManager instead of local state (FR-015)
    var isMicrophoneGranted: Bool {
        PermissionManager.shared.microphoneStatus == .granted
    }
    var isAccessibilityGranted: Bool {
        PermissionManager.shared.accessibilityStatus == .granted
    }

    // API key validation (US1)
    var apiKeyInput: String = ""
    var apiKeyValidationState: APIKeyValidationState = .idle
    let appSettings: AppSettings

    enum APIKeyValidationState: Equatable {
        case idle
        case validating
        case success
        case error(String)
    }

    private let audioCaptureService: AudioCaptureServiceProtocol
    private let apiKeyValidationService: APIKeyValidationServiceProtocol

    var shouldShowOnboarding: Bool {
        !appSettings.isOnboardingCompleted
    }

    init(
        audioCaptureService: AudioCaptureServiceProtocol? = nil,
        appSettings: AppSettings = AppSettings(),
        apiKeyValidationService: APIKeyValidationServiceProtocol = APIKeyValidationService()
    ) {
        self.audioCaptureService = audioCaptureService ?? AudioCaptureService()
        self.appSettings = appSettings
        self.apiKeyValidationService = apiKeyValidationService
        self.currentStep = .welcome
    }

    // MARK: - Navigation

    func goToNext() {
        if currentStep.isLast {
            completeOnboarding()
        } else if let next = currentStep.next {
            currentStep = next
        }
    }

    func goToPrevious() {
        if let previous = currentStep.previous {
            currentStep = previous
        }
    }

    func completeOnboarding() {
        appSettings.isOnboardingCompleted = true
        stopMicTest()
    }

    func resetOnboarding() {
        appSettings.isOnboardingCompleted = false
        currentStep = .welcome
    }

    // MARK: - API Key Validation (US1)

    var hasValidApiKey: Bool {
        apiKeyValidationState == .success
    }

    func validateAndSaveAPIKey() {
        guard !apiKeyInput.isEmpty else { return }
        apiKeyValidationState = .validating

        Task { @MainActor in
            do {
                let isValid = try await apiKeyValidationService.validate(apiKey: apiKeyInput)
                if isValid {
                    appSettings.apiKey = apiKeyInput
                    apiKeyValidationState = .success
                } else {
                    apiKeyValidationState = .error(LocalizationManager.shared.string("onboarding.completion.keyInvalid"))
                }
            } catch {
                apiKeyValidationState = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Microphone Test

    private var levelTimer: Timer?

    func startMicTest() {
        Task { @MainActor in
            do {
                try await audioCaptureService.startRecording(deviceID: nil, maxDuration: .oneMinute)
                // T027: Timer already on main thread — use updateLevelsFromAtomic (FR-019)
                levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.audioCaptureService.updateLevelsFromAtomic()
                        self.audioLevel = self.audioCaptureService.audioLevel
                    }
                }
                // T028: Subscribe to device errors
                audioCaptureService.onDeviceError = { @Sendable [weak self] deviceName, reason in
                    guard let self else { return }
                    self.stopMicTest()
                    // Could set an error state here if needed
                }
            } catch {
                audioLevel = 0
            }
        }
    }

    func stopMicTest() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioCaptureService.resetRecording()
        audioLevel = 0
    }

    /// T029: Cleanup resources when onboarding window closes (FR-020)
    func cleanup() {
        stopMicTest()
    }
}
