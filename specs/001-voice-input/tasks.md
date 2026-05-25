# Tasks: Voice Text Input

**Input**: Design artifacts from `/specs/001-voice-input/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Unit tests are included for services and ViewModels (the plan provides for XCTest, Constitution Principle 5).

**Organization**: Tasks are grouped by user stories for independent implementation and testing of each story.

**Update 2026-03-05**: Tasks are synchronized with the updated plan.md. Status of all tasks has been verified against the actual state of the codebase (28 source files, 7 test files).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can be executed in parallel (different files, no dependencies)
- **[Story]**: Which user story the task belongs to (US1, US2, US3)
- Exact file paths are specified

## Path Conventions

- **Source code**: `Verborra/` — application root
- **Tests**: `VerborraTests/` — tests root
- Structure according to plan.md

---

## Phase 1: Setup (Project Initialization)

**Goal**: Create the project structure, configure dependencies and configuration

- [X] T001 ✅ VERIFIED Create Xcode project Verborra (macOS App, SwiftUI, Swift) with target macOS 14.0+ in Package.swift
- [X] T002 ✅ VERIFIED Configure Info.plist: LSUIElement=YES, NSMicrophoneUsageDescription in Verborra/Info.plist
- [X] T003 ✅ VERIFIED [P] Configure entitlements: app-sandbox, audio-input, network.client in Verborra/Verborra.entitlements
- [X] T004 ✅ VERIFIED [P] Add SPM dependencies: swift-markdown (>=0.4.0), KeyboardShortcuts (>=2.0.0) in Package.swift
- [X] T005 ✅ VERIFIED Create directory structure: Models/, Services/, Views/, Views/Components/, ViewModels/, Resources/ in Verborra/

**Checkpoint**: The project builds, dependencies are resolved, the application launches empty in the Menu Bar.

---

## Phase 2: Foundational (Base Components)

**Goal**: Data models, service protocols, and infrastructure — BLOCK all user stories

**⚠️ CRITICAL**: Work on user stories cannot begin until this phase is completed

- [X] T006 ✅ VERIFIED [P] Create RecordingState enum (idle, recording, processing, result, error) and RecordingError enum in Verborra/Models/RecordingState.swift
- [X] T007 ✅ VERIFIED [P] Create TranscriptionResult struct (rawText, formattedText, voiceLanguage, textLanguage, timestamp, audioDuration, audioData) in Verborra/Models/TranscriptionResult.swift
- [X] T008 ✅ VERIFIED [P] Create SystemPrompt struct (id: UUID, name, content, isDefault, voiceLanguage, textLanguage) Codable + Identifiable + Equatable in Verborra/Models/SystemPrompt.swift
- [X] T009 ✅ VERIFIED [P] Create STTModel enum (gpt4oMiniTranscribe default, gpt4oTranscribe, whisper1) with rawValue String, Codable, CaseIterable in Verborra/Models/STTModel.swift
- [X] T010 ✅ VERIFIED [P] Create LLMModel enum (gpt41Nano default, gpt4oMini, gpt41Mini, gpt5Nano) with rawValue String, Codable, CaseIterable in Verborra/Models/LLMModel.swift
- [X] T011 ✅ VERIFIED [P] Create SupportedLanguage enum (en, ru, es, fr, de, pt, zh, ja, ko, it) with displayName for each language in Verborra/Models/SupportedLanguage.swift
- [X] T012 ✅ VERIFIED [P] Create MaxRecordingDuration enum (oneMinute=60, fiveMinutes=300, tenMinutes=600, twentyMinutes=1200) with displayName in Verborra/Models/MaxRecordingDuration.swift
- [X] T013 ✅ VERIFIED Implement AppSettings @Observable: launchAtLogin, autoRecord, maxRecordingDuration, selectedAudioDeviceID, selectedSTTModel, selectedLLMModel; persistence via @AppStorage / UserDefaults in Verborra/Models/AppSettings.swift
- [X] T014 ✅ VERIFIED [P] Implement KeychainService (save/retrieve/delete via Security framework, kSecClassGenericPassword, kSecAttrAccessibleAfterFirstUnlock, without kSecUseDataProtectionKeychain) with KeychainServiceProtocol in Verborra/Services/KeychainService.swift
- [X] T014a [P] Add keychain-access-groups entitlement ($(AppIdentifierPrefix)com.apeek.Verborra) to prevent Keychain password prompt in sandbox environment (FR-011c) in Verborra/Verborra.entitlements
- [X] T015 ✅ VERIFIED [P] Implement PromptsStore @Observable (prompts: [SystemPrompt], defaultPrompt, add/update/delete/setDefault, save/load to ~/Library/Application Support/Verborra/prompts.json, creation of "Standard" prompt on first launch) in Verborra/Services/PromptsStore.swift
- [X] T016 ✅ VERIFIED [P] Implement APIKeyValidationService (GET /v1/models, timeout 10s, true on 200, false on 401, throw on network error) with APIKeyValidationServiceProtocol in Verborra/Services/APIKeyValidationService.swift
- [X] T017 ✅ VERIFIED Implement VerborraApp: MenuBarExtra (.menu style), Settings scene, PromptsStore in @Environment, loading prompts on startup, LSUIElement in Verborra/VerborraApp.swift
- [X] T018 ✅ VERIFIED Integrate AppSettings with KeychainService for reading/writing API key in Verborra/Models/AppSettings.swift

**Checkpoint**: All models, Keychain service, PromptsStore, APIKeyValidationService, and the application skeleton are ready. The application launches in the Menu Bar.

---

## Phase 3: User Story 1 — Voice Recording and Recognition (Priority: P1) 🎯 MVP

**Goal**: The user presses the global hotkey, an overlay appears with prompt and language selectors, records voice, and receives formatted text

**Independent test**: Invoke the hotkey, record voice, confirm that the recognized and formatted text appeared in the overlay

### User Story 1 Implementation

- [X] T019 ✅ VERIFIED [US1] Implement AudioCaptureService: AVAudioEngine with tap on input node, conversion to WAV (PCM Int16, 16 kHz, mono) in-memory, support for audio device selection (deviceID: String?), configurable duration limit (MaxRecordingDuration), 25 MB size limit, auto-stop callback, availableInputDevices() method, fallback to system device when selected one is unavailable in Verborra/Services/AudioCaptureService.swift
- [X] T020 ✅ VERIFIED [US1] Implement TranscriptionService: multipart/form-data POST to /v1/audio/transcriptions, parameter model: STTModel, response_format: "json" for compatibility with all models, passing language from voice language settings, retry with exponential backoff (max 3 attempts on 429/500+), timeout 60s in Verborra/Services/TranscriptionService.swift
- [X] T021 ✅ VERIFIED [P] [US1] Implement FormattingService: JSON POST to /v1/chat/completions, parameter model: LLMModel, textLanguage: String, forming the system prompt as "{content}\n\nResponse language: {textLanguage}", temperature: 0.2, max_completion_tokens: 4000, retry, timeout 30s in Verborra/Services/FormattingService.swift
- [X] T022 ✅ VERIFIED [US1] Implement HotkeyService: KeyboardShortcuts.Name for Option+Space, async/await onKeyDown, toggle behavior (re-press closes overlay without insertion, FR-002a) in Verborra/Services/HotkeyService.swift
- [X] T023 ✅ VERIFIED [US1] Implement OverlayPanel: NSPanel subclass, styleMask=[.nonactivatingPanel, .borderless, .fullSizeContentView], level=.floating, becomesKeyOnlyIfNeeded=true, hidesOnDeactivate=false, collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary], compact size during recording (FR-004a), auto-expand on result (FR-004b), remembering PID of target application in Verborra/Views/OverlayPanel.swift
- [X] T024 ✅ VERIFIED [US1] Implement RecordingViewModel @Observable: state machine (RecordingState), selectedPrompt/selectedVoiceLanguage/selectedTextLanguage (per-session from PromptsStore), methods showOverlay/startRecording/stopRecording/resetRecording/changePrompt/changeVoiceLanguage/changeTextLanguage/pasteResult/copyResult/dismissOverlay, re-AI-processing on prompt change in .result state, passing STTModel/LLMModel from AppSettings to services in Verborra/ViewModels/RecordingViewModel.swift
- [X] T025 ✅ VERIFIED [P] [US1] Create PromptSelectorView (Picker/Menu for selecting prompt from PromptsStore, visible at all overlay stages: recording, processing, result, auto-update of languages on prompt change) in Verborra/Views/Components/PromptSelectorView.swift
- [X] T026 ✅ VERIFIED [P] [US1] Create LanguageSelectorView (two Pickers: voice language and text language from SupportedLanguage, default values from selected prompt, auto-update on prompt change, FR-012b/FR-012c/FR-012d) in Verborra/Views/Components/LanguageSelectorView.swift
- [X] T027 ✅ VERIFIED [P] [US1] Create AudioWaveformView (real-time volume level visualization, large indicator in compact overlay mode, binding to audioLevel from RecordingViewModel) in Verborra/Views/Components/AudioWaveformView.swift
- [X] T028 ✅ VERIFIED [US1] Implement RecordingView: large visual recording indicator (AudioWaveformView), hint with max recording duration (FR-004a), warning 30 sec before limit (FR-018d), "Start recording"/"Stop" buttons, integration with PromptSelectorView and LanguageSelectorView in Verborra/Views/RecordingView.swift
- [X] T029 ✅ VERIFIED [US1] Implement OverlayContentView: integration of PromptSelectorView and LanguageSelectorView at all stages, switching between RecordingView and ResultView by RecordingState, keyboard shortcuts (Space start/stop, Delete reset, Escape close, global hotkey toggle) in Verborra/Views/OverlayContentView.swift
- [X] T030 ✅ VERIFIED [US1] Implement error handling in overlay: microphone unavailable/permission not granted (FR-016a), API key not configured, network unavailable, API error with "Retry" button (FR-005c, audio is preserved until overlay closes), silence (FR: empty result), 25 MB limit exceeded (FR-018c) in Verborra/ViewModels/RecordingViewModel.swift

**Checkpoint**: Full cycle hotkey → recording (with prompt and language selection) → transcription (configurable STT model) → AI formatting (configurable LLM model) → result display in overlay. Prompt change after result → re-processing. Errors are handled.

---

## Phase 4: User Story 2 — Text Editing and Insertion (Priority: P2)

**Goal**: The user edits the result in the WYSIWYG Markdown editor, inserts into the target field or copies to clipboard

**Independent test**: After receiving the recognized text, edit it, press "Insert" and confirm that the text appeared in the target field

### User Story 2 Implementation

- [X] T031 ✅ VERIFIED [US2] Implement ResultView with NSTextView (NSViewRepresentable) WYSIWYG Markdown editor: parsing via swift-markdown, applying NSAttributedString styles (headings, lists, bold, italic, code) on every text change via NSTextStorageDelegate, "Insert" and "Copy" buttons, copy confirmation in Verborra/Views/ResultView.swift
- [X] T032 ✅ VERIFIED [US2] Implement PasteService: NSPasteboard snapshot → write plain text → CGEvent.postToPid Cmd+V → 200ms delay → restore clipboard (with changeCount check); fallback: notification when target application is unavailable; copyToClipboard for Markdown source; with PasteServiceProtocol in Verborra/Services/PasteService.swift
- [X] T033 ✅ VERIFIED [US2] Integrate ResultView with RecordingViewModel: "Insert" button → pasteResult() → hide overlay, return focus, insert plain text; "Copy" button → copyResult() → Markdown source to clipboard; prompt change in ResultView → re-AI-processing in Verborra/Views/ResultView.swift
- [X] T034 ✅ VERIFIED [US2] Implement Accessibility permission handling: check on insertion attempt, if not granted — text remains in clipboard, show message suggesting to go to System Settings (FR-014a) in Verborra/Services/PasteService.swift
- [X] T035 ✅ VERIFIED [US2] Implement overlay close on Escape at any stage without text insertion (FR: US2 scenario 4), toggle-close via global hotkey (FR-002a) in Verborra/Views/OverlayPanel.swift

**Checkpoint**: Full cycle recording → result → editing in WYSIWYG → insertion/copying works. Markdown is displayed visually. Prompt change after result initiates re-processing.

---

## Phase 5: User Story 3 — Application Settings (Priority: P3)

**Goal**: The user configures the hotkey, API key, audio device, recording duration, auto-record, auto-launch, manages prompts and models through a settings window in macOS Ventura+ style

**Independent test**: Open settings, switch between tabs, change the hotkey, confirm that the new hotkey works

### User Story 3 Implementation

- [X] T036 ✅ VERIFIED [US3] Implement SettingsViewModel: API key validation via APIKeyValidationService (test request on save, displaying result), prompt management via PromptsStore (CRUD, default assignment), STT/LLM model management, audio device selection, auto-launch management via SMAppService in Verborra/ViewModels/SettingsViewModel.swift
- [X] T037 ✅ VERIFIED [P] [US3] Create HotkeyRecorder (wrapper for KeyboardShortcuts.Recorder for SwiftUI) in Verborra/Views/Components/HotkeyRecorder.swift
- [X] T038 ✅ VERIFIED [US3] Implement SettingsView in macOS Ventura+ style (System Settings): sidebar with tabs and icons (General gear, System Prompts text.bubble, About info.circle), auto-adjustment of window size to tab content, on re-invocation of "Settings" — bringing the existing window to the front (FR-019a) in Verborra/Views/SettingsView.swift
- [X] T039 ✅ VERIFIED [US3] Implement "General" tab: global hotkey (HotkeyRecorder), OpenAI API key (SecureField + Command+V + validation with result indicator, FR-011a/FR-011b), audio device selection (Picker from AudioCaptureService.availableInputDevices()), max recording duration (Picker from MaxRecordingDuration), auto-record (Toggle), auto-launch (Toggle + SMAppService), Accessibility (FR-010a) and Microphone (FR-010b) check buttons with status memorization in Verborra/Views/SettingsView.swift
- [X] T040 ✅ VERIFIED [US3] Implement "System Prompts" tab: list of prompts (add/edit/delete), Markdown content editor, default assignment, per-prompt language settings (voiceLanguage, textLanguage from SupportedLanguage, FR-012/FR-012a), global STT (FR-023a) and LLM (FR-023b) model selectors with tooltip icons (?) and popover reference about models and prices (FR-023d) in Verborra/Views/SettingsView.swift
- [X] T041 ✅ VERIFIED [P] [US3] Implement "About" tab: application version, license, links to documentation and support in Verborra/Views/SettingsView.swift
- [X] T042 ✅ VERIFIED [US3] Integrate SettingsView with Settings scene in VerborraApp: opening via Menu Bar → "Settings", @Environment(\.openSettings), temporary application activation when opening settings (FR-019), return to background mode on close in Verborra/VerborraApp.swift
- [X] T043 ✅ VERIFIED [US3] Implement auto-launch at login via SMAppService.mainApp (register/unregister), synchronization with launchAtLogin in AppSettings in Verborra/ViewModels/SettingsViewModel.swift
- [X] T044 ✅ VERIFIED [US3] Add warning when API key is missing: on attempt to record without API key, show message suggesting to go to settings in Verborra/ViewModels/RecordingViewModel.swift

**Checkpoint**: All settings work: 3 tabs in Ventura+ style, hotkey, API key with validation, audio device, recording duration, auto-record, auto-launch, prompts (CRUD + languages), STT/LLM models with popover reference. Changes are applied immediately.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Goal**: Tests, final polish, optimization

### Service Unit Tests

- [ ] T045 [P] Write unit tests for AudioCaptureService (mock AVAudioEngine, verification of WAV format 44-byte RIFF header + PCM Int16 16 kHz mono, duration and 25 MB size limits, audio device fallback, audioLevel updating) in VerborraTests/Services/AudioCaptureServiceTests.swift
- [X] T046 ✅ VERIFIED [P] Write unit tests for TranscriptionService (mock URLSession, verification of multipart/form-data, model STTModel parameter, response_format: "json", retry on 429/500, timeout 60s) in VerborraTests/Services/TranscriptionServiceTests.swift
- [X] T047 ✅ VERIFIED [P] Write unit tests for FormattingService (mock URLSession, verification of JSON request, model LLMModel parameters, textLanguage, temperature 0.2, timeout 30s) in VerborraTests/Services/FormattingServiceTests.swift
- [X] T048 ✅ VERIFIED [P] Write unit tests for KeychainService (mock Security framework, save/retrieve/delete, kSecAttrAccessibleAfterFirstUnlock) in VerborraTests/Services/KeychainServiceTests.swift
- [X] T049 ✅ VERIFIED [P] Write unit tests for PromptsStore (CRUD, JSON persistence, default prompt on first launch, deletion of default → reassignment) in VerborraTests/Services/PromptsStoreTests.swift
- [X] T050 ✅ VERIFIED [P] Write unit tests for APIKeyValidationService (mock URLSession, HTTP 200 → true, 401 → false, network error → throw) in VerborraTests/Services/APIKeyValidationServiceTests.swift

### ViewModel Unit Tests

- [X] T051 ✅ VERIFIED [P] Write unit tests for RecordingViewModel (mock all services, state machine transition verification, prompt change → re-AI-processing, language change, error handling) in VerborraTests/ViewModels/RecordingViewModelTests.swift
- [X] T052 ✅ VERIFIED [P] Write unit tests for SettingsViewModel (mock AppSettings, KeychainService, APIKeyValidationService, PromptsStore, SMAppService, API key validation, prompt management) in VerborraTests/ViewModels/SettingsViewModelTests.swift

### Finalization

- [ ] T053 Add Assets.xcassets: Menu Bar icon (template image 18x18), overlay colors in Verborra/Resources/Assets.xcassets
- [ ] T054 Performance optimization: verify overlay < 300 ms (SC-001), consumption < 50 MB RAM in idle (SC-006), sound level indicator 60 fps (SC-002)
- [ ] T055 Run validation per quickstart.md: full cycle build → run → API key configuration → recording → result → editing → insertion into target field

---

## Dependencies and Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: ✅ Completed (T001–T005)
- **Foundational (Phase 2)**: ✅ Completed (T006–T018)
- **US1 (Phase 3)**: ✅ Completed (T019–T030)
- **US2 (Phase 4)**: ✅ Completed (T031–T035)
- **US3 (Phase 5)**: ✅ Completed (T036–T044)
- **Polish (Phase 6)**: ⏳ In progress — 4 tasks remaining (T045, T053, T054, T055)

### User Story Dependencies

- **US1 (P1)**: Starts after Phase 2 — no dependencies on other stories
- **US2 (P2)**: Depends on US1 — uses RecordingViewModel, OverlayPanel, TranscriptionResult
- **US3 (P3)**: Can partially run in parallel with US1 (T036–T041), but T044 depends on RecordingViewModel (US1)

### Within Each Story

- Services before ViewModel
- ViewModel before Views
- Base views before integration tasks
- Error handling at the end of the phase

### Parallel Opportunities (remaining tasks)

- T045 and T053 — in parallel (different files: tests vs resources)
- T054 — after T045, T053 (full project needed)
- T055 — final task (after all others)

---

## Implementation Strategy

### Current Status

1. ✅ Phase 1: Setup — completed
2. ✅ Phase 2: Foundational — completed
3. ✅ Phase 3: User Story 1 (MVP) — completed
4. ✅ Phase 4: User Story 2 — completed
5. ✅ Phase 5: User Story 3 — completed
6. ⏳ Phase 6: Polish — 4 tasks remaining

### Remaining Work

| ID | Description | Priority |
|---|---|---|
| T045 | AudioCaptureService unit tests | Medium |
| T053 | Assets.xcassets (Menu Bar icon, colors) | High |
| T054 | Performance verification (300 ms, 50 MB, 60 fps) | Medium |
| T055 | Full validation per quickstart.md | High |

### Recommended Order

1. T053 + T045 — in parallel (resources + tests)
2. T054 — performance verification
3. T055 — final validation

---

## Summary

| Metric | Value |
|---|---|
| Total tasks | 55 |
| Completed | 51 (93%) |
| Remaining | 4 (7%) |
| US1 tasks | 12 (T019–T030) ✅ |
| US2 tasks | 5 (T031–T035) ✅ |
| US3 tasks | 9 (T036–T044) ✅ |
| Parallel opportunities | T045 ∥ T053 |

---

## Notes

- [P] = different files, no dependencies — can be parallel
- [USx] = binding to a specific user story
- [X] = task completed (code exists in the repository)
- Each story is independently complete and testable
- Commit after each task or logical group
