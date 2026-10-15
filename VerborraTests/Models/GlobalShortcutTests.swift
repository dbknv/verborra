import Foundation
import Testing
@testable import Verborra

// MARK: - GlobalShortcutTests (spec 015, T010)

@MainActor
struct GlobalShortcutTests {

    private func isolatedDefaults() -> UserDefaults {
        let suite = "GlobalShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func jsonRoundTrip() throws {
        let shortcut = GlobalShortcut(keyCode: 15, modifiers: [.fn, .command, .shift])
        let decoded = try JSONDecoder().decode(GlobalShortcut.self, from: JSONEncoder().encode(shortcut))
        #expect(decoded == shortcut)
    }

    @Test func migratesFromKeyboardShortcuts() {
        let defaults = isolatedDefaults()
        defaults.set(#"{"carbonKeyCode":49,"carbonModifiers":2048}"#, forKey: GlobalShortcutStore.legacyStorageKey)
        let store = GlobalShortcutStore(defaults: defaults)
        #expect(store.current == GlobalShortcut(keyCode: 49, modifiers: [.option]))
        #expect(ShortcutFormatter.string(store.current) == "⌥ Space")
        #expect(defaults.data(forKey: GlobalShortcutStore.storageKey) != nil)
    }

    @Test func migrationFallsBackToDefaultOnGarbage() {
        let defaults = isolatedDefaults()
        defaults.set("not json", forKey: GlobalShortcutStore.legacyStorageKey)
        #expect(GlobalShortcutStore(defaults: defaults).current == .default)
    }

    @Test func missingLegacyValueUsesDefault() {
        #expect(GlobalShortcutStore(defaults: isolatedDefaults()).current == .default)
    }

    @Test func savedShortcutIsLoadedOnNextLaunch() {
        let defaults = isolatedDefaults()
        let shortcut = GlobalShortcut(keyCode: 96, modifiers: [.fn])
        GlobalShortcutStore(defaults: defaults).save(shortcut)
        #expect(GlobalShortcutStore(defaults: defaults).current == shortcut)
    }

    @Test func formatterOrdersModifiers() {
        let all = GlobalShortcut(keyCode: 40, modifiers: [.command, .shift, .option, .control, .fn])
        #expect(ShortcutFormatter.string(all) == "🌐︎ ⌃ ⌥ ⇧ ⌘ K")
        #expect(ShortcutFormatter.string(.default) == "⌥ Space")
        #expect(ShortcutFormatter.string(GlobalShortcut(keyCode: 96, modifiers: [.fn])) == "🌐︎ F5")
    }

    @Test func carbonConversionDropsFn() {
        let modifiers: ShortcutModifiers = [.fn, .option, .command]
        let roundTripped = ShortcutModifiers(carbonFlags: modifiers.carbonFlags)
        #expect(roundTripped == [.option, .command])
    }

    @Test func cgFlagsIgnoreSecondaryFn() {
        let modifiers = ShortcutModifiers(cgFlags: [.maskSecondaryFn, .maskShift])
        #expect(modifiers == [.shift])
    }

    @Test func validationRules() {
        #expect(GlobalShortcut(keyCode: 49, modifiers: []).isValid == false)
        #expect(GlobalShortcut(keyCode: 58, modifiers: [.command]).isValid == false)
        #expect(GlobalShortcut(keyCode: 179, modifiers: [.fn]).isValid == false)
        #expect(GlobalShortcut(keyCode: 96, modifiers: [.fn]).requiresEventTap)
        #expect(GlobalShortcut.default.requiresEventTap == false)
    }
}
