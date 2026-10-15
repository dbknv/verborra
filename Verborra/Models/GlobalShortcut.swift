import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

// MARK: - ShortcutModifiers (spec 015, T008)

/// Модификаторы глобального сочетания. `fn` хранится отдельно: у Carbon для него нет бита,
/// такие сочетания обслуживает event tap (research R5).
struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt8

    static let fn = ShortcutModifiers(rawValue: 1 << 0)
    static let control = ShortcutModifiers(rawValue: 1 << 1)
    static let option = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)
    static let command = ShortcutModifiers(rawValue: 1 << 4)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Из Carbon-флагов (`cmdKey`/`shiftKey`/`optionKey`/`controlKey`).
    init(carbonFlags: Int) {
        var result: ShortcutModifiers = []
        if carbonFlags & controlKey != 0 { result.insert(.control) }
        if carbonFlags & optionKey != 0 { result.insert(.option) }
        if carbonFlags & shiftKey != 0 { result.insert(.shift) }
        if carbonFlags & cmdKey != 0 { result.insert(.command) }
        self = result
    }

    /// В Carbon-флаги. `fn` отбрасывается — у Carbon нет для него бита.
    var carbonFlags: Int {
        var result = 0
        if contains(.control) { result |= controlKey }
        if contains(.option) { result |= optionKey }
        if contains(.shift) { result |= shiftKey }
        if contains(.command) { result |= cmdKey }
        return result
    }

    /// Из флагов NSEvent; `.function` → `fn`.
    init(nsFlags: NSEvent.ModifierFlags) {
        var result: ShortcutModifiers = []
        if nsFlags.contains(.function) { result.insert(.fn) }
        if nsFlags.contains(.control) { result.insert(.control) }
        if nsFlags.contains(.option) { result.insert(.option) }
        if nsFlags.contains(.shift) { result.insert(.shift) }
        if nsFlags.contains(.command) { result.insert(.command) }
        self = result
    }

    var nsFlags: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if contains(.fn) { result.insert(.function) }
        if contains(.control) { result.insert(.control) }
        if contains(.option) { result.insert(.option) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.command) { result.insert(.command) }
        return result
    }

    /// Из флагов CGEvent **без** `.maskSecondaryFn`: macOS ставит этот бит и на стрелки/F-клавиши,
    /// поэтому наличие Fn event tap определяет сам, по событию flagsChanged (research R6).
    init(cgFlags: CGEventFlags) {
        var result: ShortcutModifiers = []
        if cgFlags.contains(.maskControl) { result.insert(.control) }
        if cgFlags.contains(.maskAlternate) { result.insert(.option) }
        if cgFlags.contains(.maskShift) { result.insert(.shift) }
        if cgFlags.contains(.maskCommand) { result.insert(.command) }
        self = result
    }
}

// MARK: - GlobalShortcut (spec 015, T008)

/// Глобальное сочетание клавиш для открытия/закрытия плавающего окна.
struct GlobalShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: ShortcutModifiers

    /// ⌥Space — прежнее значение по умолчанию у KeyboardShortcuts.
    static let `default` = GlobalShortcut(keyCode: UInt16(kVK_Space), modifiers: [.option])

    /// Коды клавиш-модификаторов (54–63) и Fn/Globe (179) не могут быть основной клавишей.
    static let modifierKeyCodes: Set<UInt16> = Set(54...63).union([179])

    /// Сочетания с Fn обслуживает event tap, остальные — Carbon hotkey.
    var requiresEventTap: Bool { modifiers.contains(.fn) }

    /// Правила: основная клавиша — не модификатор, модификаторы не пусты.
    var isValid: Bool {
        !Self.modifierKeyCodes.contains(keyCode) && !modifiers.isEmpty
    }
}

// MARK: - ShortcutFormatter (spec 015, T008)

/// Строковое представление сочетаний для UI: символы модификаторов и имя клавиши через пробел.
enum ShortcutFormatter {
    /// Символ Fn/Globe. U+FE0E — текстовое (не эмодзи) начертание.
    static let fnSymbol = "\u{1F310}\u{FE0E}"

    static func symbols(_ modifiers: ShortcutModifiers) -> [String] {
        var result: [String] = []
        if modifiers.contains(.fn) { result.append(fnSymbol) }
        if modifiers.contains(.control) { result.append("⌃") }
        if modifiers.contains(.option) { result.append("⌥") }
        if modifiers.contains(.shift) { result.append("⇧") }
        if modifiers.contains(.command) { result.append("⌘") }
        return result
    }

    static func keyName(_ keyCode: UInt16) -> String {
        if let name = namedKeys[Int(keyCode)] {
            return name
        }
        if let name = ansiKeys[Int(keyCode)] {
            return name
        }
        return layoutCharacter(for: keyCode) ?? "Key \(keyCode)"
    }

    static func string(_ shortcut: GlobalShortcut) -> String {
        (symbols(shortcut.modifiers) + [keyName(shortcut.keyCode)]).joined(separator: " ")
    }

    // MARK: - Private

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
        kVK_ForwardDelete: "⌦", kVK_Escape: "Esc", kVK_ANSI_KeypadEnter: "Enter",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "PgUp", kVK_PageDown: "PgDn",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

    /// Буквы и цифры по физическому положению (ANSI), в верхнем регистре — не зависят от раскладки.
    private static let ansiKeys: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9"
    ]

    /// Символ клавиши в текущей раскладке (UCKeyTranslate).
    private static func layoutCharacter(for keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        UCKeyTranslate(keyboardLayout, keyCode, UInt16(kUCKeyActionDown),
                       0, UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                       &deadKeyState, chars.count, &length, &chars)
        guard length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text.uppercased()
    }
}

// MARK: - GlobalShortcutStore (spec 015, T009)

/// Хранит текущее глобальное сочетание в UserDefaults (`globalShortcut.v1`, JSON).
/// При первом запуске переносит значение из KeyboardShortcuts (`KeyboardShortcuts_toggleOverlay`).
@MainActor
@Observable
final class GlobalShortcutStore {
    static let shared = GlobalShortcutStore()

    static let storageKey = "globalShortcut.v1"
    static let legacyStorageKey = "KeyboardShortcuts_toggleOverlay"

    private(set) var current: GlobalShortcut

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let log = DiagnosticLogger.logger(for: .hotkey)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(GlobalShortcut.self, from: data),
           stored.isValid {
            current = stored
            return
        }

        let migrated = Self.legacyShortcut(in: defaults) ?? .default
        current = migrated
        persist(migrated)
        log.info("Global shortcut migrated", metadata: [
            "from": Self.legacyDescription(in: defaults),
            "to": ShortcutFormatter.string(migrated)
        ])
    }

    func save(_ shortcut: GlobalShortcut) {
        guard shortcut != current else { return }
        current = shortcut
        persist(shortcut)
    }

    // MARK: - Private

    private func persist(_ shortcut: GlobalShortcut) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private struct LegacyShortcut: Decodable {
        let carbonKeyCode: Int
        let carbonModifiers: Int
    }

    /// KeyboardShortcuts хранит JSON-строку `{"carbonKeyCode":Int,"carbonModifiers":Int}`.
    private static func legacyShortcut(in defaults: UserDefaults) -> GlobalShortcut? {
        guard let data = legacyData(in: defaults),
              let legacy = try? JSONDecoder().decode(LegacyShortcut.self, from: data),
              let keyCode = UInt16(exactly: legacy.carbonKeyCode) else {
            return nil
        }
        let shortcut = GlobalShortcut(keyCode: keyCode, modifiers: ShortcutModifiers(carbonFlags: legacy.carbonModifiers))
        return shortcut.isValid ? shortcut : nil
    }

    private static func legacyData(in defaults: UserDefaults) -> Data? {
        switch defaults.object(forKey: legacyStorageKey) {
        case let string as String: string.data(using: .utf8)
        case let data as Data: data
        default: nil
        }
    }

    private static func legacyDescription(in defaults: UserDefaults) -> String {
        guard defaults.object(forKey: legacyStorageKey) != nil else { return "absent" }
        return legacyShortcut(in: defaults).map(ShortcutFormatter.string) ?? "unreadable"
    }
}
