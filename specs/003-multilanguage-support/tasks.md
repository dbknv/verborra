# Tasks: Interface Multilanguage Support

**Input**: Artifacts from `specs/003-multilanguage-support/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can be executed in parallel (different files, no dependencies)
- **[Story]**: Which user story the task belongs to (US1, US2, US3, US4, US5, US6, US7)
- Exact file paths in descriptions

---

## Phase 1: Setup

**Goal**: Build the localization infrastructure

- [X] T001 Create LocalizationManager with the LocalizationManagerProtocol protocol in Verborra/Services/LocalizationManager.swift — implement: singleton (@Observable), loading .lproj bundles via Bundle(path:), methods string(_:) and string(_:args:), fallback to en.lproj, method detectSystemLanguage() via Locale.preferredLanguages
- [X] T002 Add uiLanguage property to Verborra/Models/AppSettings.swift — @AppStorage("uiLanguage"), getter with OS language detection on first launch, setter that updates LocalizationManager.shared.currentLanguage
- [X] T003 Create the String Catalog Verborra/Localizable.xcstrings with the base language English (en) — add all localization keys with prefix-based grouping (onboarding., settings., recording., result., error., common., menu., model.) and English values for all ~129 strings
- [X] T004 [P] Create InfoPlist.xcstrings in Verborra/ for system strings (CFBundleDisplayName, CFBundleName)
- [X] T005 Add LocalizationManager.shared to the SwiftUI environment in Verborra/VerborraApp.swift — pass via .environment() to MenuBarExtra and Settings

**Checkpoint**: Localization infrastructure is ready, string extraction can begin

---

## Phase 2: User Story 3 — Translate all texts into English (Priority: P1) — MVP

**Goal**: All hardcoded Russian strings are extracted into the localization system, English is the base language

**Independent test**: Set the language to en, go through all screens — there are no Russian strings

### String extraction from Models

- [X] T006 [P] [US3] Localize RecordingError.errorDescription in Verborra/Models/RecordingState.swift — replace all Russian strings with calls to LocalizationManager.shared.string() with keys error.micNotAvailable, error.micPermissionDenied, error.apiKeyNotConfigured, error.networkUnavailable, error.transcriptionFailed, error.formattingFailed, error.silenceDetected, error.recordingTooLong, error.fileSizeLimit, error.accessibilityNotGranted, error.pasteTargetUnavailable
- [X] T007 [P] [US3] Localize STTModel.infoDescription in Verborra/Models/STTModel.swift — replace Russian descriptions with keys model.stt.gpt4oMiniTranscribe.info, model.stt.gpt4oTranscribe.info, model.stt.whisper1.info
- [X] T008 [P] [US3] Localize LLMModel.infoDescription in Verborra/Models/LLMModel.swift — replace Russian descriptions with keys model.llm.*.info for all 8 models
- [X] T009 [P] [US3] Localize MaxRecordingDuration.displayName in Verborra/Models/MaxRecordingDuration.swift — keys common.duration.1min, common.duration.5min, common.duration.10min, common.duration.20min

### String extraction from Views — Onboarding

- [X] T010 [P] [US3] Localize WelcomeStep in Verborra/Views/Onboarding/WelcomeStep.swift — title, description (onboarding.welcome.*)
- [X] T011 [P] [US3] Localize PermissionsStep in Verborra/Views/Onboarding/PermissionsStep.swift — title, permission descriptions, buttons (onboarding.permissions.*)
- [X] T012 [P] [US3] Localize MicrophoneTestStep in Verborra/Views/Onboarding/MicrophoneTestStep.swift — title, instructions, status (onboarding.micTest.*)
- [X] T013 [P] [US3] Localize CompletionStep in Verborra/Views/Onboarding/CompletionStep.swift — title, description, API-key button, hint (onboarding.completion.*)
- [X] T014 [P] [US3] Localize OnboardingWindow (navigation) in Verborra/Views/Onboarding/OnboardingWindow.swift — buttons "Back", "Next", "Start", "Finish" (onboarding.nav.*)

### String extraction from Views — Overlay

- [X] T015 [P] [US3] Localize RecordingView in Verborra/Views/RecordingView.swift — all states: idle hint, recording hint, processing text, error buttons (recording.*)
- [X] T016 [P] [US3] Localize ResultView in Verborra/Views/ResultView.swift — title "Result", buttons "Paste", "Copy", "Copied", Escape hint (result.*)

### String extraction from Views — Settings

- [X] T017 [P] [US3] Localize SettingsTab.title enum in Verborra/Views/SettingsView.swift — keys settings.tab.general, settings.tab.prompts, settings.tab.hotkeys, settings.tab.llm, settings.tab.about, settings.tab.advanced
- [X] T018 [P] [US3] Localize GeneralSettingsTab in Verborra/Views/SettingsView.swift — sections "Recording", "Permissions", "System", all labels and buttons (settings.general.*)
- [X] T019 [P] [US3] Localize PromptsSettingsTab in Verborra/Views/SettingsView.swift — buttons "Default", "Save", labels "Name", "System prompt", "Voice", "Text", "Select a prompt" (settings.prompts.*)
- [X] T020 [P] [US3] Localize AboutSettingsTab in Verborra/Views/SettingsView.swift — "Version", "Voice text input for macOS", "License: MIT", links (settings.about.*)
- [X] T021 [P] [US3] Localize LLMSettingsTab in Verborra/Views/LLMSettingsTab.swift — sections "OpenAI API", "Speech recognition model", "Text processing model", buttons and validation statuses (settings.llm.*)
- [X] T022 [P] [US3] Localize HotkeysSettingsTab in Verborra/Views/HotkeysSettingsTab.swift — sections "Trigger overlay", "Start/stop recording", "Reset" buttons, hints, conflict warning (settings.hotkeys.*)
- [X] T023 [P] [US3] Localize AdvancedSettingsTab in Verborra/Views/AdvancedSettingsTab.swift — "Onboarding" section, "Reset onboarding" button, restart warning (settings.advanced.*)
- [X] T024 [P] [US3] Localize RecordingHotkeyRecorderView in Verborra/Views/HotkeysSettingsTab.swift — string "Press a key..." (settings.hotkeys.pressKey)

### String extraction from Menu Bar and ViewModel

- [X] T025 [P] [US3] Localize MenuBarView in Verborra/VerborraApp.swift — "Settings...", "Quit" (menu.settings, menu.quit)
- [X] T026 [P] [US3] Localize the model error string in Verborra/ViewModels/RecordingViewModel.swift — "Model ... is not supported by the server" (error.modelNotSupported)
- [X] T026a [P] [US3] Localize PasteService in Verborra/Services/PasteService.swift — replace hardcoded Russian error strings with calls to LocalizationManager.shared.string() using keys error.paste.*

### Russian translations

- [X] T027 [US3] Add Russian localization (ru) to Verborra/Localizable.xcstrings — all ~129 keys with the original Russian values from the current code

**Checkpoint**: US3 completed — all strings extracted, English as base, Russian as a translation. The application works in en and ru.

---

## Phase 3: User Story 1 — Automatic interface language detection (Priority: P1)

**Goal**: At first launch, the language is detected from the OS, with fallback to English

**Independent test**: Change the macOS language → launch the application → the interface is in the OS language

- [X] T028 [US1] Implement the automatic language detection logic at first launch in Verborra/Services/LocalizationManager.swift — in detectSystemLanguage() match Locale.preferredLanguages against SupportedLanguage, return .en if there is no match. At first launch (uiLanguage is empty), call detectSystemLanguage() and save the result
- [X] T029 [US1] Add a LocalizationManager.detectSystemLanguage() test in VerborraTests/LocalizationManagerTests.swift — tests: supported OS language (ru) → .ru, unsupported language (zh-Hans, es) → fallback .en, missing/corrupted .lproj bundle → fallback to en

**Checkpoint**: US1 completed — the language is detected automatically at first launch

---

## Phase 4: User Story 2 — Manual interface language selection (Priority: P1)

**Goal**: The user can change the language in the settings, switching is instant

**Independent test**: Open settings → "Language" section → select another → UI updates

- [X] T030 [US2] Add a "Language" section at the very top of GeneralSettingsTab in Verborra/Views/SettingsView.swift — section label via localized key settings.general.language, Picker with UILanguage only (en, ru) — a subset of SupportedLanguage, displayName in the native language (English label for English; Russian shown in its native script), bound to appSettings.uiLanguage, section before the "Recording" section
- [X] T031 [US2] Add a test for saving and restoring uiLanguage in VerborraTests/LocalizationManagerTests.swift — tests: a language change is saved to UserDefaults, reload restores the selected language, language change updates currentBundle

**Checkpoint**: US2 completed — the user can change the language, the setting is preserved

---

## Phase 5: Previously completed tasks

- [X] T032 [US4] Verify and ensure that uiLanguage is independent of voice/text language — in Verborra/ViewModels/RecordingViewModel.swift ensure that changeVoiceLanguage/changeTextLanguage do not affect uiLanguage; in Verborra/Models/AppSettings.swift the uiLanguage setter does not affect prompts and the content of SystemPrompt does not change when uiLanguage changes. Add tests in VerborraTests/LocalizationManagerTests.swift: uiLanguage change does not change voice/text language, uiLanguage change does not change the SystemPrompt text
- [X] T033 Validate translation completeness — verify that the String Catalog has no empty values for en and ru, all keys are filled. Verify correct display of long strings on all screens — wrapping and truncation without clipping content
- [X] T034 Run quickstart.md validation — go through all scenarios from quickstart.md, check every screen in every language (en, ru)
- [X] T035 [US3] Bring all localization texts to informational style in Verborra/Localizable.xcstrings — remove word abbreviations (Max. -> Maximum, sec -> seconds, Def. -> Default), replace Anglicisms with native Russian equivalents (use the native Russian phrase for "shortcut" instead of a transliteration of "hotkey"; use the native phrase for "recording window" instead of a transliteration of "overlay"), replace jargon in English localization (hotkey -> shortcut, overlay -> recording window, Max. -> Maximum). Spell out abbreviations on first mention
- [X] T036 Fix Observation tracking in computed properties of Verborra/Models/AppSettings.swift — add access(keyPath:) in getter and withMutation(keyPath:) in setter for maxRecordingDuration, selectedAudioDeviceIDOrNil, selectedSTTModel, selectedLLMModel, uiLanguage, apiKey. Without this, SwiftUI does not receive notifications about changes to computed properties bound to @ObservationIgnored raw values
- [X] T037 [US3] Shorten the API-key error text in Verborra/Localizable.xcstrings — remove the instruction "Set it in Settings" (and its Russian equivalent), leave only the essence: "OpenAI API key is not configured" (and its Russian equivalent)
- [X] T038 Change the recording window positioning in Verborra/Views/OverlayPanel.swift — reduce the offset from the bottom edge of the screen from 10% to 5% (positionOnScreen)

---

## Phase 6: Foundational — Models and system prompt registry

**Goal**: Build system-prompt infrastructure and migrate the data model

**WARNING CRITICAL**: US5 and US6 cannot begin until this phase is complete

- [X] T039 [P] Create SystemPromptDefinition and SystemPromptRegistry in Verborra/Models/SystemPromptDefinition.swift — struct SystemPromptDefinition with fields id: String, translations: [SupportedLanguage: (name: String, content: String)], methods name(for:) and content(for:) with fallback to .en. Enum SystemPromptRegistry with static let all: [SystemPromptDefinition] and static func definition(for systemId:). Add extension SystemPromptDefinition with static let simpleVoiceToText with translations into all 10 supported languages (en, ru, es, fr, de, pt, zh, ja, ko, it)
- [X] T040 Update the SystemPrompt model in Verborra/Models/SystemPrompt.swift — add fields isSystem: Bool (default false) and systemId: String? (default nil). Remove fields voiceLanguage and textLanguage. Implement custom init(from decoder:) for backward compatibility: read voiceLanguage/textLanguage from the old JSON (if present) without storing them in properties, decode isSystem with fallback false, systemId with fallback nil. In encode(to:) — do not write voiceLanguage/textLanguage. Update init() — add parameters isSystem and systemId, remove voiceLanguage and textLanguage. Update makeDefault() — create a system prompt with isSystem: true, systemId: "simple-voice-to-text", name and content from SystemPromptRegistry by the current uiLanguage
- [X] T041 Add globalVoiceLanguage and globalTextLanguage to Verborra/Models/AppSettings.swift — two @AppStorage("globalVoiceLanguage") and @AppStorage("globalTextLanguage") with raw value String. Computed properties globalVoiceLanguage/globalTextLanguage: SupportedLanguage with fallback .ru on empty/invalid value. Use the access(keyPath:)/withMutation(keyPath:) pattern for Observation tracking (like in uiLanguage)

**Checkpoint**: Models updated, registry created — migration and UI work can begin

---

## Phase 7: User Story 5 — Localized system prompt "Simple Voice To Text" (Priority: P1)

**Goal**: System prompt with translations into 10 languages, automatic update on language change

**Independent test**: Switch the interface language → name and content of the system prompt have updated

### Migration and storage

- [X] T042 [US5] Implement migration v1→v2 in Verborra/Services/PromptsStore.swift — in init() after load() add a check for UserDefaults("promptsDataVersion") < 2. During migration: (1) find the default prompt (isDefault == true), move voiceLanguage to UserDefaults("globalVoiceLanguage") and textLanguage to UserDefaults("globalTextLanguage"); (2) find the "Standard" prompt (by name) or the first prompt, replace with a system prompt: isSystem = true, systemId = "simple-voice-to-text", name/content from SystemPromptRegistry by the current uiLanguage, preserve the original isDefault; (3) set UserDefaults("promptsDataVersion") = 2; (4) save(). If prompts.json cannot be read — create a system prompt from scratch. For reading voiceLanguage/textLanguage from the old JSON use a helper MigrationPrompt struct with both field formats
- [X] T043 [US5] Add the updateSystemPrompts(for:) method to Verborra/Services/PromptsStore.swift — for each prompt with isSystem == true, find a SystemPromptDefinition by systemId, update name and content for the passed language, call save()
- [X] T044 [US5] Add the ensureSystemPrompts() method to Verborra/Services/PromptsStore.swift — verify that all prompts from SystemPromptRegistry.all are present in prompts (by systemId). If any is missing — create it with isDefault = false. Call in init() after migration. This ensures new system prompts are added when the application is updated (FR-023)
- [X] T045 [US5] Integrate system prompt updates on language change — in Verborra/Models/AppSettings.swift in the uiLanguage setter, after updating LocalizationManager, raise a notification (NotificationCenter or callback). In Verborra/VerborraApp.swift (or AppController) subscribe to uiLanguage changes and call promptsStore.updateSystemPrompts(for: newLanguage)

### Modification protection in PromptsStore

- [X] T046 [US5] Protect system prompts in PromptsStore in Verborra/Services/PromptsStore.swift — in deletePrompt(_:) add a guard: if prompt.isSystem → return (do not delete). In updatePrompt(_:) add a guard: if prompt.isSystem → return (do not update via user input). In makeDefault() create a system prompt when the list is empty. Ensure that on deletion of all user prompts the system one remains and becomes the default

### Dynamic content resolution by text language

- [X] T069 [US5] Add the contentForLanguage(_:) method to Verborra/Models/SystemPrompt.swift — for system prompts (isSystem == true, systemId != nil) returns the content from SystemPromptRegistry by the passed language. For user prompts returns the stored content without modification
- [X] T070 [US5] Update RecordingViewModel in Verborra/ViewModels/RecordingViewModel.swift — replace all 6 calls of selectedPrompt.content with selectedPrompt.contentForLanguage(selectedTextLanguage) when sending to the LLM (in stopRecording, retranscribeAndReformat, reprocessResult)
- [X] T071 [US5] Update SettingsViewModel in Verborra/ViewModels/SettingsViewModel.swift — subscribe to the uiLanguageDidChange notification and update editingPromptName/editingPromptContent via refreshSelectedPrompt() with DispatchQueue.main.async to guarantee ordering after PromptsStore.updateSystemPrompts

**Checkpoint**: US5 completed — the system prompt is localized into all 10 languages, updates in the settings on UI language change, and resolves by text language when processing text

---

## Phase 8: User Story 6 — Protection of system prompts in the UI (Priority: P1)

**Goal**: System prompts are visually distinct from user prompts, fields are blocked

**Independent test**: Select a system prompt → all fields disabled, delete button blocked, lock icon

- [X] T047 [P] [US6] Update the prompts list in PromptsSettingsTab in Verborra/Views/SettingsView.swift — in promptsList: next to the name of a system prompt (prompt.isSystem) show Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary). Minus button (delete): add to the disabled condition — viewModel.selectedPrompt?.isSystem == true (system prompts cannot be deleted)
- [X] T048 [P] [US6] Update the prompts editor in PromptsSettingsTab in Verborra/Views/SettingsView.swift — in promptEditor: wrap the name TextField and content TextEditor with .disabled(viewModel.selectedPrompt?.isSystem == true). Hide or block the "Save" button for system prompts
- [X] T049 [US6] Remove voice/text language pickers from PromptsSettingsTab in Verborra/Views/SettingsView.swift — remove the HStack with the Pickers for voice and text language from promptEditor (languages moved to global settings)
- [X] T050 [P] [US6] Add the selectedPrompt property to SettingsViewModel in Verborra/ViewModels/SettingsViewModel.swift — computed property selectedPrompt: SystemPrompt? based on selectedPromptID and promptsStore.prompts. Add an isSystem check in deletePrompt(_:) and saveCurrentPrompt() — operations are ignored for system prompts

**Checkpoint**: US6 completed — system prompts are protected in the UI, user prompts work as before

---

## Phase 9: User Story 4 — Migrate voice/text language to global settings (Priority: P2)

**Goal**: Voice/text language are global settings in the "Models" section, independent of prompts

**Independent test**: Change the interface language → voice/text language have not changed. Switch the prompt → voice/text language have not changed

- [X] T051 [US4] Add a voice/text language section to LLMSettingsTab in Verborra/Views/LLMSettingsTab.swift — new Section with the key settings.llm.languages (or settings.llm.languageSection). Two Pickers: voice language (settings.llm.voiceLanguage) bound to appSettings.globalVoiceLanguage, text language (settings.llm.textLanguage) bound to appSettings.globalTextLanguage. ForEach over SupportedLanguage.allCases with displayName. Place the section after the model selectors
- [X] T052 [US4] Update RecordingViewModel in Verborra/ViewModels/RecordingViewModel.swift — in init(): replace the initialization of selectedVoiceLanguage and selectedTextLanguage from defaultPrompt.voiceLanguage/textLanguage with settings.globalVoiceLanguage/settings.globalTextLanguage. In showOverlay(): similarly replace the initialization from the prompt with the global settings. In changePrompt(_:): remove the lines selectedVoiceLanguage = prompt.voiceLanguage and selectedTextLanguage = prompt.textLanguage (a prompt change must not change languages — FR-010c)
- [X] T053 [US4] Update LanguageSelectorView in Verborra/Views/Components/LanguageSelectorView.swift — if the component accepts a prompt to initialize the languages, replace with initialization from AppSettings (via Environment). Per-session behavior is preserved — language changes in the overlay are not saved globally
- [X] T054 [US4] Add localization keys for the languages section to Verborra/Localizable.xcstrings — add keys: settings.llm.languages / settings.llm.languageSection (section title), settings.llm.voiceLanguage (label for voice), settings.llm.textLanguage (label for text). English and Russian values

**Checkpoint**: US4 completed — voice/text language are global, independent of prompts and interface language

---

## Phase 10: User Story 7 — Correct display of the prompts window (Priority: P2)

**Goal**: All components of the "Prompts" tab are displayed correctly without clipping

**Independent test**: Add 10+ prompts with long names → the list scrolls, the layout does not break

- [X] T055 [US7] Verify and fix the layout of PromptsSettingsTab in Verborra/Views/SettingsView.swift — ensure that: the prompts list (promptsList) has a ScrollView or List with scrolling at 10+ items; long prompt names are truncated with .lineLimit(1).truncationMode(.tail); HSplitView minimum sizes are correct (minWidth for the list and the editor); at the minimum window size (minWidth: 820, minHeight: 620) all components are visible and functional; TextEditor for prompt content has a sufficient minimum height

**Checkpoint**: US7 completed — the prompts window displays correctly with any number of prompts

---

## Phase 11: Finalization

**Goal**: Cross-functional checks and validation

- [X] T056 Update PromptsStore unit tests in VerborraTests/ — add tests: migration v1→v2 (voiceLanguage/textLanguage moved into UserDefaults), replacement of "Standard" with a system prompt, protection against deletion/editing of system prompts, ensureSystemPrompts() adds missing ones, updateSystemPrompts(for:) updates name/content. WARNING Update test T032: for system prompts (isSystem == true) the content MUST change on uiLanguage change, for user prompts — MUST NOT
- [X] T057 [P] Update SystemPrompt Codable unit tests in VerborraTests/ — add tests: decoding the old format (with voiceLanguage/textLanguage) → isSystem = false; decoding the new format (with isSystem/systemId); encode of the new format does not contain voiceLanguage/textLanguage
- [X] T058 [P] Add SystemPromptRegistry tests in VerborraTests/ — tests: all interface languages (en, ru) have translations for simpleVoiceToText; fallback to English for a non-existent language; definition(for:) finds by id; definition(for:) returns nil for a non-existent id
- [X] T059 Validate completeness — verify that all new localization keys (settings.llm.languages, settings.llm.voiceLanguage, settings.llm.textLanguage) are added to Localizable.xcstrings with en and ru translations. Go through all screens in both languages, verify system prompt display, language switching, edit protection
- [X] T060 Run quickstart.md validation — go through all scenarios from the updated quickstart.md: migration, system prompt, protection, global voice/text language

---

## Phase 12: Bugfix — Audio capture reliability

**Goal**: Fix error -10868 (kAudioUnitErr_FormatNotSupported) and false microphone permission check failures

- [X] T061 Add the entitlement com.apple.security.device.audio-input to Verborra/Verborra.entitlements — without it, AVCaptureDevice.authorizationStatus(for: .audio) does not return .authorized on macOS with Hardened Runtime
- [X] T062 Refactor AudioCaptureService.startRecording in Verborra/Services/AudioCaptureService.swift — signature from throws → async throws; permission check before touching the engine; recreate AVAudioEngine() on every start instead of engine.reset(); move setInputDevice into prepareAndStartEngine; extract the tap callback into installRecordingTap(on:)
- [X] T063 Add retry with fallback to the system device in prepareAndStartEngine in Verborra/Services/AudioCaptureService.swift — on engine.start() error, recreate engine without setInputDevice (default device); check channelCount > 0 in addition to sampleRate > 0
- [X] T064 Update startRecording calls to async in Verborra/ViewModels/RecordingViewModel.swift and Verborra/ViewModels/OnboardingViewModel.swift — wrap in Task { @MainActor in try await ... }
- [X] T065 Add AVFAudio error mapping to RecordingViewModel.mapError in Verborra/ViewModels/RecordingViewModel.swift — map errors from the com.apple.coreaudio.avfaudio domain to .microphoneNotAvailable instead of .transcriptionFailed
- [X] T066 Update MockAudioCaptureService in VerborraTests/ViewModels/RecordingViewModelTests.swift — change startRecording signature from throws → async throws

**Checkpoint**: Recording works reliably when audio devices are changed/disconnected, microphone permission is detected correctly

---

## Phase 13: Bugfix — Settings window layout

**Goal**: Fix content overflowing the settings window edges in the "Prompts" tab

- [X] T067 Increase the minimum settings window width in Verborra/Views/SettingsView.swift — minWidth from 820 to 980px
- [X] T068 Fix the PromptsSettingsTab layout in Verborra/Views/SettingsView.swift — add frame(maxWidth: .infinity, maxHeight: .infinity) on HSplitView; add frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) on the promptEditor VStack and the frame container; add maxWidth/maxHeight on TextEditor for proper space filling

**Checkpoint**: All components of the "Prompts" tab are displayed within the settings window

---

## Dependencies and Execution Order

### Dependencies between phases

- **Phases 1-5**: Completed (T001-T038)
- **Phase 6 (Foundational — models)**: No dependencies on unfinished tasks — starts immediately. BLOCKS US5, US6, US4
- **Phase 7 (US5 — system prompt)**: Depends on Phase 6 (T039-T041). BLOCKS US6
- **Phase 8 (US6 — UI protection)**: Depends on Phase 7 (prompts with isSystem must exist)
- **Phase 9 (US4 — global languages)**: Depends on Phase 6 (T041 — globalVoiceLanguage/globalTextLanguage in AppSettings)
- **Phase 10 (US7 — layout)**: Depends on Phase 8 (the prompts UI has changed)
- **Phase 11 (Finalization)**: Depends on completion of all US

### Dependencies between User Stories

- **US5 (P1)**: Depends on Phase 6 (models) — BLOCKS US6
- **US6 (P1)**: Depends on US5 (system prompts must exist)
- **US4 (P2)**: Depends on Phase 6 — can run in parallel with US5/US6
- **US7 (P2)**: Depends on US6 (final prompts UI)

### Parallel opportunities

- T039 and T041 — parallel (different files: SystemPromptDefinition.swift and AppSettings.swift)
- T047, T048, T050 — parallel within US6 (different sections of SettingsView and SettingsViewModel)
- US4 (Phase 9) can run in parallel with US5 (Phase 7) after Phase 6
- T056, T057, T058 — all tests parallel

---

## Parallel example: Phase 6 (Foundational)

```bash
# Parallel tasks:
T039: SystemPromptDefinition.swift (new file)
T041: AppSettings.swift (adding global languages)

# Sequentially after T039:
T040: SystemPrompt.swift (depends on SystemPromptRegistry)
```

## Parallel example: Phases 7 + 9

```bash
# After Phase 6 is complete, in parallel:
# Stream A — US5:
T042: PromptsStore migration
T043: updateSystemPrompts
T044: ensureSystemPrompts
T045: Language change integration
T046: PromptsStore protection

# Stream B — US4:
T051: LLMSettingsTab + voice/text pickers
T052: RecordingViewModel
T053: LanguageSelectorView
T054: Localization keys
```

---

## Implementation Strategy

### MVP (minimum for demonstration)

1. Phases 1-5: Base en/ru localization (T001-T038)
2. Phase 6: Models and registry (T039-T041)
3. Phase 7: US5 — system prompt (T042-T046)
4. **STOP and VALIDATE**: The system prompt works, migration is correct

### Incremental delivery

1. Setup + US3 + US1 + US2 → en/ru work
2. + Foundational + US5 → system prompt "Simple Voice To Text" with localization
3. + US6 → system prompt protection in the UI
4. + US4 → global voice/text language in the "Models" section
5. + US7 → correct layout of the prompts window
6. Finalization → tests, full validation

---

## Notes

- [P] tasks = different files, no dependencies
- T039-T041 (Foundational) — critical path, blocks all new US
- Migration (T042) must handle both JSON formats (v1 with voiceLanguage/textLanguage and v2 with isSystem/systemId)
- The "Standard" system prompt is ALWAYS replaced by "Simple Voice To Text" regardless of user modifications
- System prompt translations are stored in Swift code (hardcoded), not in .xcstrings — all 10 languages (en, ru, es, fr, de, pt, zh, ja, ko, it)
- When sending to the LLM, system prompt content is resolved by text language via contentForLanguage(), not by UI language
- Voice/text language in the recording overlay are per-session and not saved globally
- Technical terms (API, OpenAI, LLM, STT, Accessibility) are NOT translated
- In technical documentation and class names "overlay" is used (OverlayPanel, OverlayContentView). In user-facing strings in Localizable.xcstrings the native Russian phrase for "recording window" is used (FR-016)
