import SwiftUI

struct MicrophoneTestStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(LocalizationManager.self) private var l10n

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text(l10n.string("onboarding.micTest.title"))
                .font(.title2)
                .fontWeight(.bold)

            Text(l10n.string("onboarding.micTest.description"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            AudioWaveformView(audioLevel: viewModel.audioLevel)
                .frame(height: 60)
                .padding(.horizontal, 40)

            if viewModel.audioLevel > 0.05 {
                Label(l10n.string("onboarding.micTest.working"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text(l10n.string("onboarding.micTest.speakNow"))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
        .onAppear {
            viewModel.startMicTest()
        }
        .onDisappear {
            viewModel.stopMicTest()
        }
    }
}
