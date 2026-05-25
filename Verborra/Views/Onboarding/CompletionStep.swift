import KeyboardShortcuts
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

            if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleOverlay) {
                Text(shortcut.description)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            }

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

            Text(l10n.string("onboarding.completion.skipHint"))
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(.horizontal, 40)
    }
}
