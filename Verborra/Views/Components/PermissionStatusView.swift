import SwiftUI

// MARK: - PermissionStatusView (T011) [US2] [US6]

struct PermissionStatusView: View {
    let permissionType: PermissionType
    private let permissionManager = PermissionManager.shared
    private let l10n = LocalizationManager.shared

    private var status: PermissionStatus {
        switch permissionType {
        case .microphone: return permissionManager.microphoneStatus
        case .accessibility: return permissionManager.accessibilityStatus
        }
    }

    private var title: String {
        switch permissionType {
        case .microphone: return l10n.string("onboarding.permissions.microphone")
        case .accessibility: return "Accessibility"
        }
    }

    private var description: String {
        switch permissionType {
        case .microphone: return l10n.string("onboarding.permissions.microphone.description")
        case .accessibility: return l10n.string("onboarding.permissions.accessibility.description")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(status == .granted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch status {
            case .notDetermined:
                Button(l10n.string("onboarding.permissions.request")) {
                    requestAccess()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

            case .denied, .restricted:
                // T037: Use same "Request" label for microphone .denied (FR-004c)
                // PermissionManager handles the NSAlert + quit flow internally
                Button(l10n.string("onboarding.permissions.request")) {
                    requestAccess()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

            case .granted:
                EmptyView()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
    }

    private func requestAccess() {
        switch permissionType {
        case .microphone:
            permissionManager.requestMicrophoneAccess()
        case .accessibility:
            permissionManager.requestAccessibilityAccess()
        }
    }
}
