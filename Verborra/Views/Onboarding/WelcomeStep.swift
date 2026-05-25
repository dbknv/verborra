import SwiftUI

struct WelcomeStep: View {
    @Environment(LocalizationManager.self) private var l10n

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text(l10n.string("onboarding.welcome.title"))
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(l10n.string("onboarding.welcome.description"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
        }
        .padding(.horizontal, 40)
    }
}
