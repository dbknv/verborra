import SwiftUI
import KeyboardShortcuts

// MARK: - HotkeyRecorder (V004: Real KeyboardShortcuts.Recorder)

struct HotkeyRecorder: View {
    private let l10n = LocalizationManager.shared

    var body: some View {
        LabeledContent(l10n.string("settings.hotkeys.globalHotkey")) {
            KeyboardShortcuts.Recorder(for: .toggleOverlay)
        }
    }
}
