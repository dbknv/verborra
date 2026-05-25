# Implementation Plan: Interface Multilanguage Support

**Branch**: `003-multilanguage-support` | **Date**: 2026-03-09 | **Specification**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/003-multilanguage-support/spec.md`

## Summary

Implementation of full interface multilanguage support in the Verborra application (English/Russian) with a custom localization manager for instant switching without restart. Includes: extracting remaining hardcoded strings into the localization system, creating a localized system prompt "Simple Voice To Text" (en, ru) with protection against editing/deletion, and migrating voice/text language from per-prompt to global settings in the "Models" section.

## Technical Context

**Language/Version**: Swift 5.9+
**Main Dependencies**: SwiftUI, AVFoundation, Security (Keychain), KeyboardShortcuts (sindresorhus), swift-markdown (swiftlang)
**Storage**: UserDefaults (@AppStorage), JSON in Application Support (`prompts.json`), macOS Keychain (API key)
**Testing**: XCTest / Swift Testing
**Target Platform**: macOS 24+ (Sequoia)
**Project Type**: macOS desktop (menu bar app)
**Constraints**: UI language switch < 100ms (instant)
**Scale**: ~30 Swift files, 6 settings tabs, 4 onboarding screens, recording window, ~131 localization strings

## Constitution Check

*GATE: Must pass before Phase 0. Re-check after Phase 1.*

| Principle | Status | Comment |
|-----------|--------|---------|
| P1: Native macOS experience | OK | SwiftUI + NSPanel, String Catalogs (.xcstrings) — standard Apple mechanism |
| P2: Swift-first | OK | All code in Swift, SPM for dependencies, no new dependencies |
| P3: Minimalism | OK | Minimal UI changes — one "Language" section in settings. UserDefaults for storage |
| P4: Security | OK | Does not touch audio/API keys. System prompts hardcoded in code |
| P5: Code quality | OK | Existing unit tests are adapted. New logic is covered by tests |

**Result**: All principles are observed. No violations.

## Project Structure

### Documentation (this feature)

```text
specs/003-multilanguage-support/
├── plan.md              # This file
├── research.md          # Phase 0: research (8 decisions)
├── data-model.md        # Phase 1: data model (changes to SystemPrompt, AppSettings, new entities)
├── quickstart.md        # Phase 1: developer guide
└── tasks.md             # Phase 2: tasks (created by /speckit.tasks)
```

### Source Code (repository root)

```text
Verborra/
├── Models/
│   ├── SystemPrompt.swift           # Prompt model — add isSystem/systemId, remove voiceLanguage/textLanguage
│   ├── AppSettings.swift            # Settings — add global voiceLanguage/textLanguage
│   ├── SystemPromptDefinition.swift # NEW — registry of system prompts with translations (all 10 languages: en, ru, es, fr, de, pt, zh, ja, ko, it)
│   ├── SupportedLanguage.swift      # Unchanged
│   ├── RecordingError.swift         # Errors — switch to localization keys
│   └── MaxRecordingDuration.swift   # Durations — switch to localization keys
├── Services/
│   ├── LocalizationManager.swift    # No significant changes (already implemented)
│   ├── PromptsStore.swift           # Migration v1→v2, protection of system prompts, update on language change
│   └── PasteService.swift           # Remove hardcoded Russian strings
├── ViewModels/
│   ├── RecordingViewModel.swift     # Initialize languages from AppSettings instead of prompt
│   ├── SettingsViewModel.swift      # Protect system prompts from editing/deletion
│   └── OnboardingViewModel.swift    # Unchanged
├── Views/
│   ├── SettingsView.swift           # PromptsSettingsTab: remove voice/text, protect system prompts
│   ├── LLMSettingsTab.swift         # Add voice/text language section
│   ├── RecordingView.swift          # Verify localization
│   ├── OverlayContentView.swift     # Verify localization
│   ├── HotkeysSettingsTab.swift     # Verify localization
│   ├── AdvancedSettingsTab.swift     # Verify localization
│   ├── Components/
│   │   ├── LanguageSelectorView.swift   # Initialize from AppSettings instead of prompt
│   │   └── PromptSelectorView.swift     # Unchanged
│   └── Onboarding/                  # Verify localization completeness
├── Localizable.xcstrings            # Add missing keys
└── InfoPlist.xcstrings              # Verify
```

**Structural decision**: Existing macOS project structure. One new file (`SystemPromptDefinition.swift`). All other changes are in existing files. Localization via Apple String Catalogs (.xcstrings), already set up.

## Key Architectural Decisions

### R1: System prompts with a translation registry

`SystemPrompt` gets an `isSystem: Bool` flag and `systemId: String?`. System prompts:
- Are identified by `systemId` (e.g. `"simple-voice-to-text"`)
- Their name and content in the UI are computed from `SystemPromptRegistry` by the current interface language
- When sent to the LLM, the content is resolved by the text language via `contentForLanguage(_:)`
- Are protected from editing and deletion
- Translations into all 10 supported languages (en, ru, es, fr, de, pt, zh, ja, ko, it) are stored in a Swift dictionary (hardcoded)

Details: [research.md](research.md) — R2, R3

### R2: Global voice/text language

Two new `@AppStorage` entries in `AppSettings`: `globalVoiceLanguage` and `globalTextLanguage`. Moved from per-prompt to the "Models" (LLM) tab. RecordingViewModel initializes per-session languages from global settings.

Details: [research.md](research.md) — R5

### R3: Data migration v1 → v2

When loading `PromptsStore`:
1. Move `voiceLanguage`/`textLanguage` from the default prompt to `AppSettings`
2. Replace "Standard" with the system prompt `simple-voice-to-text`
3. Versioning via `UserDefaults("promptsDataVersion")`

Details: [research.md](research.md) — R4

### R4: Updating system prompts on language change

When `uiLanguage` changes → `PromptsStore.updateSystemPrompts(for:)` updates `name`/`content` of all system prompts from the registry. `SettingsViewModel` updates `editingPromptName`/`editingPromptContent` via `refreshSelectedPrompt()` on the `uiLanguageDidChange` notification.

### R8: Dynamic resolution of prompt content by text language

`SystemPrompt.contentForLanguage(_:)` — for system prompts returns the content from `SystemPromptRegistry` by the passed language; for user prompts returns the stored `content`. `RecordingViewModel` uses `selectedPrompt.contentForLanguage(selectedTextLanguage)` when sending to the LLM instead of the static `selectedPrompt.content`.

### R5: Protection of system prompts in the UI

In the list: `lock.fill` icon. In the editor: `.disabled(true)` on all fields. Delete button: `.disabled`. "Default" button: available.

Details: [research.md](research.md) — R6

### R6: Settings window layout (bugfix)

**Problem**: The content of the "Prompts" tab extends beyond the settings window edges. HSplitView and promptEditor VStack have no maxWidth/maxHeight constraints; TextEditor expands uncontrollably.

**Solution**:
- Minimum window width increased from 820px to 980px
- HSplitView: added `.frame(maxWidth: .infinity, maxHeight: .infinity)`
- promptEditor: added `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)` on the VStack
- TextEditor: added `maxWidth: .infinity, maxHeight: .infinity` to fill the available space

**Affected files**: `SettingsView.swift`

### R7: Reliability of audio capture (bugfix)

**Problem**: AVAudioEngine throws error -10868 (`kAudioUnitErr_FormatNotSupported`) on `engine.start()`. Causes: (1) `engine.reset()` leaves inputNode in an invalid state after the audio device is changed; (2) the missing entitlement `com.apple.security.device.audio-input` leads to false rejections from `AVCaptureDevice.authorizationStatus`.

**Solution**:
- `engine` from `let` → `var`, recreate `AVAudioEngine()` on every recording start
- `startRecording` from `throws` → `async throws` to support `await AVCaptureDevice.requestAccess`
- Retry logic: on `engine.start()` error — recreate engine without `setInputDevice` (fallback to system device)
- Check `channelCount > 0` in addition to `sampleRate > 0`
- Tap callback extracted into `installRecordingTap(on:)` for reuse on retry
- Mapping errors from the `com.apple.coreaudio.avfaudio` domain → `.microphoneNotAvailable`
- Added entitlement `com.apple.security.device.audio-input`

**Affected files**: `AudioCaptureService.swift`, `Verborra.entitlements`, `RecordingViewModel.swift`, `OnboardingViewModel.swift`

## Complexity Tracking

> No constitution violations detected. Table is not filled in.

## Constitution Re-check (after Phase 1)

| Principle | Status | Comment |
|-----------|--------|---------|
| P1: Native macOS experience | OK | String Catalogs (.xcstrings) — standard Apple mechanism |
| P2: Swift-first | OK | All changes in Swift, one new file, no new dependencies |
| P3: Minimalism | OK | UserDefaults for settings, hardcoded dictionaries for prompts |
| P4: Security | OK | System prompts hardcoded, do not touch secrets |
| P5: Code quality | OK | Migration is versioned, custom Codable, tests updated |
