import SwiftUI

// MARK: - PermissionsStep (T012, T022)

struct PermissionsStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(LocalizationManager.self) private var l10n

    private let permissionManager = PermissionManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text(l10n.string("onboarding.permissions.title"))
                .font(.title2)
                .fontWeight(.bold)

            Text(l10n.string("onboarding.permissions.description"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                // T022 [US3]: Accessibility via PermissionStatusView
                PermissionStatusView(permissionType: .accessibility)

                // T012 [US2]: Microphone via PermissionStatusView
                PermissionStatusView(permissionType: .microphone)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.horizontal, 40)
        .onAppear {
            // T012 [US2]: Start monitoring via PermissionManager (FR-006)
            permissionManager.startMonitoring()
        }
        .onDisappear {
            permissionManager.stopMonitoring()
        }
        // T016 [US2]: Activate window on permission status change (FR-014)
        .onChange(of: permissionManager.microphoneStatus) { _, _ in
            NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: permissionManager.accessibilityStatus) { _, _ in
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
