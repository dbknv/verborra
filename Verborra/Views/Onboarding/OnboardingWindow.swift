import AppKit
import SwiftUI

final class OnboardingWindow: NSWindow {
    private let viewModel: OnboardingViewModel
    private var onComplete: (() -> Void)?

    init(viewModel: OnboardingViewModel, onComplete: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onComplete = onComplete

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        title = "Verborra"
        isReleasedWhenClosed = false
        center()

        let contentView = OnboardingContainerView(viewModel: viewModel) { [weak self] in
            self?.onComplete?()
            self?.close()
        }
        .environment(LocalizationManager.shared)
        self.contentView = NSHostingView(rootView: contentView)
    }

    override func performClose(_ sender: Any?) {
        // Block Cmd+W — window cannot be closed until onboarding is complete
    }

    override func close() {
        viewModel.stopMicTest()
        super.close()
    }
}

// MARK: - OnboardingContainerView

struct OnboardingContainerView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(LocalizationManager.self) private var l10n
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step.rawValue <= viewModel.currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            // Step content
            Group {
                switch viewModel.currentStep {
                case .welcome:
                    WelcomeStep()
                case .permissions:
                    PermissionsStep(viewModel: viewModel)
                case .microphoneTest:
                    MicrophoneTestStep(viewModel: viewModel)
                case .completion:
                    CompletionStep(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation bar
            HStack {
                if viewModel.currentStep != .welcome {
                    Button(l10n.string("onboarding.nav.back")) {
                        viewModel.goToPrevious()
                    }
                    .controlSize(.large)
                }

                Spacer()

                if viewModel.currentStep.isLast {
                    Button(viewModel.hasValidApiKey ? l10n.string("onboarding.nav.start") : l10n.string("onboarding.nav.finish")) {
                        viewModel.completeOnboarding()
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button(l10n.string("onboarding.nav.next")) {
                        viewModel.goToNext()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.currentStep == .permissions && !viewModel.isMicrophoneGranted)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 420)
    }
}
