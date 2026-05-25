import Foundation
import KeyboardShortcuts

// MARK: - KeyboardShortcuts Name Extension

extension KeyboardShortcuts.Name {
    static let toggleOverlay = Self("toggleOverlay", default: .init(.space, modifiers: .option))
}

// MARK: - HotkeyServiceProtocol (T016)

protocol HotkeyServiceProtocol {
    func startListening(onToggle: @escaping () -> Void)
    func stopListening()
}

// MARK: - HotkeyService (V003: KeyboardShortcuts instead of Carbon)

final class HotkeyService: HotkeyServiceProtocol {
    private let log = DiagnosticLogger.logger(for: .userAction)

    func startListening(onToggle: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .toggleOverlay) { [log] in
            log.info("Hotkey triggered")
            DispatchQueue.main.async {
                onToggle()
            }
        }
    }

    func stopListening() {
        KeyboardShortcuts.disable(.toggleOverlay)
    }

    deinit {
        stopListening()
    }
}
