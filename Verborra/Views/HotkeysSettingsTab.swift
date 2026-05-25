import SwiftUI
import KeyboardShortcuts

struct HotkeysSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(LocalizationManager.self) private var l10n

    var body: some View {
        Form {
            Section(l10n.string("settings.hotkeys.overlaySection")) {
                HotkeyRecorder()
            }
        }
        .formStyle(.grouped)
    }
}
