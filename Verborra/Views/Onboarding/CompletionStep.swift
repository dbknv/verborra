import SwiftUI

struct CompletionStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(LocalizationManager.self) private var l10n

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text(l10n.string("onboarding.completion.title"))
                .font(.title)
                .fontWeight(.bold)

            Text(l10n.string("onboarding.completion.description"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // spec 015 (FR-028): includes 🌐︎ for Fn shortcuts
            Text(ShortcutFormatter.string(GlobalShortcutStore.shared.current))
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))

            // API Key section
            VStack(spacing: 8) {
                SecureField(l10n.string("onboarding.completion.apiKeyPlaceholder"), text: $viewModel.apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)

                HStack(spacing: 8) {
                    Button(l10n.string("onboarding.completion.saveAndVerify")) {
                        viewModel.validateAndSaveAPIKey()
                    }
                    .disabled(viewModel.apiKeyInput.isEmpty || viewModel.apiKeyValidationState == .validating)

                    switch viewModel.apiKeyValidationState {
                    case .validating:
                        ProgressView()
                            .controlSize(.small)
                    case .success:
                        Label(l10n.string("onboarding.completion.keySaved"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    case .error(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    case .idle:
                        EmptyView()
                    }
                }
            }
            .padding(.top, 4)

            // spec 015 (FR-005): asked once, applied when the user finishes onboarding
            if viewModel.asksLaunchAtLogin {
                VStack(spacing: 4) {
                    Toggle(l10n.string("onboarding.completion.launchAtLogin"), isOn: $viewModel.launchAtLoginChoice)
                        .toggleStyle(.checkbox)
                    if let error = viewModel.launchAtLoginError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Text(l10n.string("onboarding.completion.skipHint"))
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(.horizontal, 40)
    }
}
