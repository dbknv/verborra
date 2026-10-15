import Carbon.HIToolbox
import Testing
@testable import Verborra

// MARK: - ShortcutValidatorTests (spec 015, T069)

struct ShortcutValidatorTests {

    private func validator(
        symbolic: [ShortcutValidator.SymbolicHotKey] = [],
        trialSucceeds: Bool = true
    ) -> ShortcutValidator {
        ShortcutValidator(symbolicHotKeys: { symbolic }, trialRegister: { _ in trialSucceeds })
    }

    private func shortcut(_ keyCode: Int, _ modifiers: ShortcutModifiers) -> GlobalShortcut {
        GlobalShortcut(keyCode: UInt16(keyCode), modifiers: modifiers)
    }

    @Test func modifierRequired() {
        #expect(validator().validate(shortcut(kVK_ANSI_K, [])) == .rejected(.modifierRequired))
    }

    @Test func overlayNumberAndEscKeys() {
        let v = validator()
        #expect(v.validate(shortcut(kVK_ANSI_1, [.shift])) == .rejected(.conflictsWithOverlay))
        #expect(v.validate(shortcut(kVK_ANSI_2, [.fn])) == .rejected(.conflictsWithOverlay))
        #expect(v.validate(shortcut(kVK_Escape, [.shift])) == .rejected(.conflictsWithOverlay))
        #expect(v.validate(shortcut(kVK_ANSI_3, [.fn, .shift])) == .rejected(.conflictsWithOverlay))
    }

    @Test func overlayCopyPasteAndClose() {
        let v = validator()
        #expect(v.validate(shortcut(kVK_ANSI_C, [.option])) == .rejected(.conflictsWithOverlay))
        #expect(v.validate(shortcut(kVK_ANSI_V, [.option, .shift])) == .rejected(.conflictsWithOverlay))
        #expect(v.validate(shortcut(kVK_ANSI_W, [.command])) == .rejected(.conflictsWithOverlay))
    }

    @Test func appMenuShortcuts() {
        let v = validator()
        #expect(v.validate(shortcut(kVK_ANSI_Q, [.command])) == .rejected(.reservedByApp))
        #expect(v.validate(shortcut(kVK_ANSI_Comma, [.command])) == .rejected(.reservedByApp))
    }

    @Test func systemShortcut() {
        let v = validator(symbolic: [(UInt16(kVK_UpArrow), [.control])])
        #expect(v.validate(shortcut(kVK_UpArrow, [.control])) == .rejected(.reservedBySystem))
        // Fn is ignored for the comparison
        #expect(v.validate(shortcut(kVK_UpArrow, [.fn, .control])) == .rejected(.reservedBySystem))
    }

    @Test func inUseByAnotherApp() {
        #expect(validator(trialSucceeds: false).validate(shortcut(kVK_ANSI_K, [.command, .shift])) == .rejected(.inUseByAnotherApp))
    }

    @Test func fnShortcutSkipsTrialRegister() {
        #expect(validator(trialSucceeds: false).validate(shortcut(kVK_Space, [.fn])) == .ok)
    }

    @Test func optionSpaceIsOK() {
        #expect(validator().validate(shortcut(kVK_Space, [.option])) == .ok)
    }

    @Test func currentShortcutSkipsTrialRegister() {
        // Our own registration would make the trial fail for the current shortcut
        #expect(validator(trialSucceeds: false).validate(.default, current: .default) == .ok)
    }
}
