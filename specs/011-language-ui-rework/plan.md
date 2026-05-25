# Implementation Plan: Language Selection UI Rework

**Branch**: `011-language-ui-rework` | **Date**: 2026-03-22 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/011-language-ui-rework/spec.md`

## Summary

Refactoring of language UI elements in the macOS application Verborra: removing the Voice Language selector from the recording floating window, renaming fields ("Your Language" / "Response Language"), adding tooltip popovers, localizing language names into the interface language (ru/en), displaying the current Global Shortcut on the Start-Stop button with spaces between modifiers, displaying the current language in the button title, fixing the width of the settings sidebar. Pure UI changes — the data model, API, and storage are not affected.

## Technical Context

**Language/Version**: Swift 5.9+
**Primary Dependencies**: SwiftUI, AppKit (NSPanel), KeyboardShortcuts (sindresorhus)
**Storage**: UserDefaults / @AppStorage (unchanged)
**Testing**: XCTest / Swift Testing
**Target Platform**: macOS 15+ (Sequoia)
**Project Type**: Native desktop application (single project)
**Performance Constraints**: UI MUST update instantly when the interface language is changed
**Scale**: 7 files, ~12 change points

## Constitution Check

*GATE: Check before Phase 0. Re-check after Phase 1.*

| Principle | Status | Comment |
|-----------|--------|---------|
| 1. Native macOS experience | ✅ PASS | SwiftUI, NSPanel — unchanged. Tooltips via standard macOS popover. Sidebar width — standard NavigationSplitView parameter |
| 2. Swift-first development | ✅ PASS | All changes are in Swift. MVVM + @Observable. No new dependencies |
| 3. Minimalism and simplicity | ✅ PASS | UI simplification: removing a redundant selector, more understandable names |
| 4. Security and privacy | ✅ PASS | No impact — no work with audio, keys, or network |
| 5. Code quality | ✅ PASS | Unit tests for `localizedDisplayName` are required |
| 6. Logging | ✅ PASS | Existing logging of user actions covers the changes |

**Result**: All 6 principles passed. No violations.

## Project Structure

### Documentation (this feature)

```text
specs/011-language-ui-rework/
├── spec.md              # Specification
├── plan.md              # This file
├── research.md          # Research (Phase 0)
├── quickstart.md        # Quick start (Phase 1)
├── checklists/
│   └── requirements.md  # Specification quality checklist
└── tasks.md             # Tasks (created by /speckit.tasks)
```

### Source Code (affected files)

```text
Verborra/
├── Models/
│   └── SupportedLanguage.swift        # localizedDisplayName(for:) — ALREADY IMPLEMENTED
├── Views/
│   ├── ControlBarView.swift           # Language button with current value, Start-Stop with shortcut
│   ├── LLMSettingsTab.swift           # Tooltips (?), localizedDisplayName in Picker — ALREADY IMPLEMENTED
│   ├── SettingsView.swift             # Settings sidebar width
│   └── Components/
│       └── ControlBarButtonLabel.swift # Common button component
├── ViewModels/
│   └── RecordingViewModel.swift       # Hotkeys — ALREADY IMPLEMENTED
└── Localizable.xcstrings              # Strings — ALREADY IMPLEMENTED
```

**Structure Decision**: Native macOS application (single Xcode project). All changes in existing files.

## Detailed Change Plan

### Blocks A–D: Previously Implemented (T001–T014)

Blocks A (localizedDisplayName), B (floating window), C (settings + tooltips), D (shortcut formatting) are **already implemented**. See tasks.md T001–T014 [X].

### Block E: Current language in the button title (ControlBarView.swift)

**Goal**: The "Response Language" button in the floating window shows the currently selected language.

**Changes in ControlBarView.swift**:
1. In the title of the Text Language menu: instead of `l10n.string("settings.llm.textLanguage")` (static label), use `viewModel.selectedTextLanguage.localizedDisplayName(for: LocalizationManager.shared.currentLanguage)` (current value)
2. When switching via the "2" hotkey or selecting from the dropdown menu — the title updates automatically via @Bindable

**Dependencies**: Block A (localizedDisplayName) — already implemented.

### Block F: Settings sidebar width (SettingsView.swift)

**Goal**: Set the minimum and initial width of the left sidebar to 220 pixels.

**Changes in SettingsView.swift**:
1. Add `.navigationSplitViewColumnWidth(min: 220, ideal: 220)` (or an equivalent modifier) to the sidebar

**Dependencies**: None. Independent change.

## Implementation Order

```
Block E (language button) — 1 change in ControlBarView.swift
Block F (sidebar width) — 1 change in SettingsView.swift
```

Blocks E and F are fully independent and can be performed in parallel.

## Constitution Check (post-design)

| Principle | Status | Comment |
|-----------|--------|---------|
| 1. Native macOS experience | ✅ PASS | NavigationSplitView column width — standard macOS pattern |
| 2. Swift-first development | ✅ PASS | Swift only |
| 3. Minimalism and simplicity | ✅ PASS | Improved feedback (current language on the button) |
| 4. Security and privacy | ✅ PASS | Not affected |
| 5. Code quality | ✅ PASS | Minimal changes |
| 6. Logging | ✅ PASS | Existing coverage is sufficient |

**Post-design result**: All 6 principles passed.
