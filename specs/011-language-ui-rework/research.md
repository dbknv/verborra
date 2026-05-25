# Research: Language Selection UI Rework

**Branch**: `011-language-ui-rework` | **Date**: 2026-03-21

## Decision 1: Localization of Language Names

**Decision**: Add a computed property `localizedDisplayName(for:)` to `SupportedLanguage`, which returns the language name in the interface language (ru/en), instead of the current `displayName`, which displays the name in the original language.

**Rationale**: The current `displayName` is hardcoded (English, native Russian spelling, Español, etc.). Localization requires a mapping of 10 languages × 2 interface languages = 20 strings. The easiest approach is to add a dictionary directly in the enum, rather than using `Localizable.xcstrings`, because this is an internal data mapping, not a UI string.

**Alternatives**:
- Use `Locale.current.localizedString(forLanguageCode:)` — rejected: Apple does not always return correct localizations for all languages, depends on the system locale rather than our UI language
- Add strings to `Localizable.xcstrings` — rejected: creates 10 extra keys, complicates maintenance when adding languages

## Decision 2: Renaming Fields Voice Language → "Your Language", Text Language → "Response Language"

**Decision**: Update the existing localization keys `settings.llm.voiceLanguage` and `settings.llm.textLanguage` in `Localizable.xcstrings` with the new values. Add new keys for tooltips.

**Rationale**: Minimal change — only string values are updated, the keys remain the same for `@AppStorage` backward compatibility.

**Alternatives**:
- Create new keys with new names — rejected: would require updating all usage sites without benefit

## Decision 3: Tooltips in Settings

**Decision**: Use the SwiftUI `.popover` or `.help()` modifier with a `questionmark.circle` icon next to each Picker. Add 4 new localization keys (2 tooltips × 2 languages).

**Rationale**: macOS HIG recommends using `.help()` or inline help text to explain settings. Popover with a question-mark icon is a standard macOS pattern.

**Alternatives**:
- Use `Section` footer text — rejected: footer is less noticeable, not tied to a specific field
- Use `.tooltip()` — rejected: tooltip is too small for extended text

## Decision 4: Displaying Global Shortcut on the Start-Stop Button

**Decision**: Get the current shortcut from `KeyboardShortcuts.getShortcut(for: .toggleOverlay)` and format the modifiers as symbolic icons (⌥, ⌘, ⇧, ⌃) with a "+" separator. Use the `KeyboardShortcuts.Shortcut` API to obtain the symbolic representation.

**Rationale**: The KeyboardShortcuts library (sindresorhus) provides an API to obtain the currently assigned shortcut. The `.description` property or manual mapping of modifiers will provide the required format.

**Alternatives**:
- Listen for `NSNotification` from KeyboardShortcuts — may be needed for reactive updates, but for the initial load `getShortcut(for:)` is sufficient

## Decision 5: Removing Voice Language from the Floating Window

**Decision**: Remove the Voice Language menu code block (lines 147-165 in `ControlBarView.swift`). Reassign the "2" hotkey to `cycleTextLanguage()` in `RecordingViewModel.handleKeyDown()` (change keyCode 19 → cycleTextLanguage, remove keyCode 20 handling).

**Rationale**: Direct code removal and reassignment is the simplest approach. Voice Language continues to be used from global settings (selectedVoiceLanguage is initialized in showOverlay).

**Alternatives**: None — the only reasonable approach

## Affected Files

| File | Type of Change |
|------|----------------|
| `Verborra/Models/SupportedLanguage.swift` | Add `localizedDisplayName(for:)` |
| `Verborra/Views/ControlBarView.swift` | Remove Voice Language menu, update Text Language menu (name, hotkey), update Start-Stop button |
| `Verborra/Views/LLMSettingsTab.swift` | Add tooltip icons, use `localizedDisplayName` |
| `Verborra/ViewModels/RecordingViewModel.swift` | Reassign "2" hotkey to cycleTextLanguage, remove "3" handling |
| `Verborra/Localizable.xcstrings` | Update labels, add tooltip strings |
| `Verborra/Views/Components/ControlBarButtonLabel.swift` | Shortcut formatting (spaces between modifiers, no "+") |
