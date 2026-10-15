import Carbon.HIToolbox
import Foundation

// MARK: - ShortcutRejection (spec 015, T071)

enum ShortcutRejection: String, Equatable {
    case modifierRequired
    case conflictsWithOverlay
    case reservedByApp
    case reservedBySystem
    case inUseByAnotherApp

    var message: String {
        LocalizationManager.shared.string("shortcut.rejection.\(rawValue)")
    }
}

enum ShortcutValidationResult: Equatable {
    case ok
    case rejected(ShortcutRejection)
}

// MARK: - ShortcutValidator

/// Checks a candidate global shortcut; the first matching rule wins (contracts/global-shortcut.md).
struct ShortcutValidator {
    typealias SymbolicHotKey = (keyCode: UInt16, modifiers: ShortcutModifiers)

    /// Enabled macOS system shortcuts (Mission Control, Spotlight, …).
    var symbolicHotKeys: () -> [SymbolicHotKey] = ShortcutValidator.systemSymbolicHotKeys
    /// Registers and immediately unregisters the shortcut; `false` if another app holds it.
    var trialRegister: (GlobalShortcut) -> Bool = ShortcutValidator.carbonTrialRegister

    func validate(_ candidate: GlobalShortcut, current: GlobalShortcut? = nil) -> ShortcutValidationResult {
        let keyCode = Int(candidate.keyCode)
        let modifiers = candidate.modifiers

        // 1. At least one modifier
        if modifiers.isEmpty {
            return .rejected(.modifierRequired)
        }

        // 2. Keys the floating window uses: Esc, 1, 2, 3 (alone or with Fn/⇧), ⌥C/⌥V (+⇧), ⌘W
        let overlayKeys = [kVK_Escape, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3]
        if overlayKeys.contains(keyCode) && modifiers.isSubset(of: [.fn, .shift]) {
            return .rejected(.conflictsWithOverlay)
        }
        if [kVK_ANSI_C, kVK_ANSI_V].contains(keyCode) && (modifiers == [.option] || modifiers == [.option, .shift]) {
            return .rejected(.conflictsWithOverlay)
        }
        if keyCode == kVK_ANSI_W && modifiers == [.command] {
            return .rejected(.conflictsWithOverlay)
        }

        // 3. Verborra's own menu: ⌘Q, ⌘,
        if [kVK_ANSI_Q, kVK_ANSI_Comma].contains(keyCode) && modifiers == [.command] {
            return .rejected(.reservedByApp)
        }

        // 4. macOS system shortcuts (Fn ignored for the comparison)
        var withoutFn = modifiers
        withoutFn.remove(.fn)
        if symbolicHotKeys().contains(where: { $0.keyCode == candidate.keyCode && $0.modifiers == withoutFn }) {
            return .rejected(.reservedBySystem)
        }

        // 5. Another app holds it (Carbon only; Fn shortcuts go through the event tap)
        if !candidate.requiresEventTap && candidate != current && !trialRegister(candidate) {
            return .rejected(.inUseByAnotherApp)
        }

        return .ok
    }

    // MARK: - Production lookups

    static func systemSymbolicHotKeys() -> [SymbolicHotKey] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }
        return entries.compactMap { entry in
            guard (entry[kHISymbolicHotKeyEnabled] as? Bool) == true,
                  let code = entry[kHISymbolicHotKeyCode] as? Int,
                  let keyCode = UInt16(exactly: code),
                  let carbon = entry[kHISymbolicHotKeyModifiers] as? Int else {
                return nil
            }
            return (keyCode, ShortcutModifiers(carbonFlags: carbon))
        }
    }

    static func carbonTrialRegister(_ shortcut: GlobalShortcut) -> Bool {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5642_5274), id: 9999)  // "VBRt"
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            UInt32(shortcut.modifiers.carbonFlags),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if let ref { UnregisterEventHotKey(ref) }
        return status != OSStatus(eventHotKeyExistsErr)
    }
}
