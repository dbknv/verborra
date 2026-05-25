# Quick Start: Language Selection UI Rework

## Overview

Feature 011 — refactoring of language UI elements: simplifying the floating window (removing Voice Language), renaming fields, adding tooltips, localizing language names into the interface language, displaying the Global Shortcut on the button.

## Key Changes

### 1. SupportedLanguage — Localized Names
Add a method/property to get the language name in the interface language:
- `localizedDisplayName(for uiLanguage: SupportedLanguage) -> String`
- Mapping of 10 languages × 2 (ru, en)

### 2. Floating Window (ControlBarView)
- Remove the Voice Language menu (lines 147-165)
- Update the Text Language menu: new name "Response Language" (localized), "2" hotkey
- Use `localizedDisplayName` for list items
- Start-Stop button: dynamic display of the Global Shortcut with separators

### 3. Settings (LLMSettingsTab)
- Update labels via `Localizable.xcstrings`
- Add tooltip icons (?) with popover
- Use `localizedDisplayName` in Picker

### 4. Hotkeys (RecordingViewModel)
- keyCode 19 ("2" key) → `cycleTextLanguage()` (was: cycleVoiceLanguage)
- Remove keyCode 20 ("3" key) handling

## Files to Modify

```
Verborra/Models/SupportedLanguage.swift          — localizedDisplayName
Verborra/Views/ControlBarView.swift               — floating window UI
Verborra/Views/LLMSettingsTab.swift               — settings UI
Verborra/ViewModels/RecordingViewModel.swift      — hotkeys
Verborra/Localizable.xcstrings                    — localization strings
Verborra/Views/Components/ControlBarButtonLabel.swift — shortcut separators (if extracted)
```

## What NOT to Change

- `AppSettings.swift` — `@AppStorage` keys remain the same
- `GeneralSettingsTab.swift` — Interface Language picker is not affected
- `HotkeyService.swift` — global shortcut logic is not changing
- `LocalizationManager.swift` — unchanged
