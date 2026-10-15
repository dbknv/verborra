import SwiftUI

// MARK: - HotkeysSettingsTab (spec 015, T076)

struct HotkeysSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(LocalizationManager.self) private var l10n
    @Environment(GlobalHotkeyService.self) private var hotkeyService: GlobalHotkeyService?

    var body: some View {
        Form {
            Section(l10n.string("settings.hotkeys.overlaySection")) {
                if let hotkeyService {
                    LabeledContent(l10n.string("settings.hotkeys.globalHotkey")) {
                        HStack(spacing: 8) {
                            ShortcutRecorderField(
                                shortcut: hotkeyService.shortcut,
                                onCapture: { hotkeyService.apply($0) },
                                onRecordingChanged: { hotkeyService.isPaused = $0 }
                            )
                            .frame(width: 180)
                            Button(l10n.string("settings.hotkeys.reset")) {
                                hotkeyService.resetToDefault()
                            }
                        }
                    }

                    if let rejection = hotkeyService.lastRejection {
                        Text(rejection.message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    switch hotkeyService.status {
                    case .needsAccessibility:
                        Text(l10n.string("settings.hotkeys.needsAccessibility"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        PermissionStatusView(permissionType: .accessibility)
                    case .failed(let message):
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    case .active, .paused:
                        EmptyView()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
