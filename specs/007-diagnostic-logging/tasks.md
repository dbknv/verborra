# Tasks: Diagnostic Logging

**Input**: Design documents from `/specs/007-diagnostic-logging/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Included — the Constitution requires business logic coverage with unit tests (XCTest / Swift Testing).

**Organization**: Tasks are grouped by User Story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can be executed in parallel (different files, no dependencies)
- **[Story]**: Which User Story the task belongs to (US1, US2, ...)

## Phase 1: Setup

**Purpose**: Create directory structure and base models

- [X] T001 Create Verborra/Services/Logging/ directory and add to Xcode project
- [X] T002 [P] Create LogLevel enum (OFF/ERROR/INFO/DEBUG) with Comparable and Codable in Verborra/Models/LogLevel.swift
- [X] T003 [P] Create LogCategory enum (audio, bluetooth, engine, tap, stream, api, permissions, userAction, lifecycle, settings, system) in Verborra/Models/LogCategory.swift
- [X] T004 [P] Create LogEntry struct (Codable) with fields timestamp, level, category, sessionId, message, metadata, error in Verborra/Models/LogEntry.swift
- [X] T005 Create ErrorContext struct (Codable) with fields description, method, parameters, errorCode, state, breadcrumbs in Verborra/Models/LogEntry.swift
- [X] T006 Create AppState struct (Codable) with fields activeDevice, recordingStatus, recordingDuration, currentOperation in Verborra/Models/LogEntry.swift
- [X] T007 Create Breadcrumb struct (Codable) with fields timestamp, label, category, metadata in Verborra/Models/LogEntry.swift

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core of the logging system — MUST be completed before any User Story starts

**CRITICAL**: All User Stories depend on this phase

- [X] T008 Create SensitiveMasker with methods maskAPIKey(_:), maskTranscription(_:), describeAudioBuffer(sampleCount:format:) in Verborra/Services/Logging/SensitiveMasker.swift
- [X] T009 Create RingBuffer<T> generic struct (capacity: 20, append, drain) in Verborra/Services/Logging/FlowTracker.swift
- [X] T010 Create FlowTracker class with NSLock, methods beginFlow() -> UUID, addBreadcrumb(_:to:), endFlow(_:) -> [Breadcrumb] in Verborra/Services/Logging/FlowTracker.swift
- [X] T011 Create JSONLFileWriter class with DispatchQueue (serial, qos: .utility), FileHandle append mode, methods write(entry:), flush(), startPeriodicFlush() in Verborra/Services/Logging/JSONLFileWriter.swift
- [X] T012 Create LogFileManager class with methods currentLogFileURL(), rotateIfNeeded(), cleanupOldLogs(retentionHours:), logsDirectoryURL() in Verborra/Services/Logging/LogFileManager.swift. Rotation: every hour OR 50 MB. Cleanup: files older than retentionHours (from AppSettings, default 24). Directory: ~/Library/Application Support/Verborra/Logs/. Name: verborra-yyyy-MM-ddTHH.jsonl
- [X] T013 Create DiagnosticLogger class — facade with os.Logger + JSONLFileWriter. Static factory: logger(for: LogCategory). Methods: info(_:metadata:), debug(_:metadata:), error(_:context:). Check current LogLevel from AppSettings. Subsystem: "dev.apeek.verborra" in Verborra/Services/Logging/DiagnosticLogger.swift
- [X] T014 Add logLevel property (LogLevel, default: .info) and logRetentionHours property (Int, default: 24) to AppSettings via @AppStorage in Verborra/Models/AppSettings.swift
- [X] T015 Add sessionId property (UUID, generated on init) to DiagnosticLogger as static let in Verborra/Services/Logging/DiagnosticLogger.swift
- [X] T016 Initialize DiagnosticLogger and LogFileManager at application launch in applicationDidFinishLaunching, add lifecycle log "Application launched" in Verborra/VerborraApp.swift
- [X] T017 Add lifecycle log "Application will terminate" in applicationWillTerminate with final flush in Verborra/VerborraApp.swift
- [X] T064 Add lifecycle log "Application did become active" and "Application did resign active" (background transition / return) in Verborra/VerborraApp.swift. Category: lifecycle

### Tests for Phase 2

- [X] T018 [P] Unit test SensitiveMasker: maskAPIKey masks correctly (sk-...XXXX), short keys → ***, maskTranscription returns length in VerborraTests/Logging/SensitiveMaskerTests.swift
- [X] T019 [P] Unit test RingBuffer: append fills, drain returns in insertion order, overflow correctly evicts old elements in VerborraTests/Logging/RingBufferTests.swift
- [X] T020 [P] Unit test FlowTracker: beginFlow creates flow, addBreadcrumb adds, endFlow drains and removes flow, thread-safety in VerborraTests/Logging/FlowTrackerTests.swift
- [X] T021 [P] Unit test LogEntry: JSON encoding (Codable), all fields present, ISO 8601 timestamp format in VerborraTests/Logging/LogEntryTests.swift
- [X] T022 [P] Unit test DiagnosticLogger: static filtering — info/debug/error respect fixed LogLevel; OFF disables everything; ERROR is written at INFO level; correct routing to both sinks in VerborraTests/Logging/DiagnosticLoggerTests.swift
- [X] T023 [P] Unit test LogFileManager: rotateIfNeeded creates new file on hour change, cleanupOldLogs deletes old files in VerborraTests/Logging/LogFileManagerTests.swift

**Checkpoint**: Logging core ready — DiagnosticLogger.logger(for:) can be called from any service

---

## Phase 3: User Story 1 — Diagnosing audio device problems (Priority: P1) MVP

**Goal**: All audio subsystem events (devices, engine, tap, streams, Bluetooth) are logged with correct categories and levels

**Independent Test**: Connect/disconnect a Bluetooth device → check log in Console.app and JSONL

### Implementation

- [X] T024 [US1] Add logging to AudioCaptureService.startRecording: INFO — recording start (deviceID, maxDuration); DEBUG — audio format parameters; ERROR — mic permission errors in Verborra/Services/AudioCaptureService.swift
- [X] T025 [US1] Add logging to AudioCaptureService.prepareAndStartEngine: INFO — engine creation/start; DEBUG — engine configuration (graph, nodes, device format); ERROR — startup errors in Verborra/Services/AudioCaptureService.swift
- [X] T026 [US1] Add tap logging: INFO — tap install/remove; DEBUG — tap format (sample rate, channels, buffer size); tap errors. Category: tap in Verborra/Services/AudioCaptureService.swift
- [X] T027 [US1] Add device selection logging: INFO — name, ID, type, result; DEBUG — all available devices, stream parameters, driver/firmware version (if available). Category: audio in Verborra/Services/AudioCaptureService.swift
- [X] T028 [US1] Add Bluetooth event logging: INFO — detection, connection, disconnection, profile change (A2DP ↔ HFP/SCO), connection quality on profile change; ERROR — connection loss. Category: bluetooth in Verborra/Services/AudioCaptureService.swift
- [X] T065 [US1] Implement Bluetooth event throttling: 100 ms per-device. Dictionary<DeviceID, DispatchTime> to track the last log event for each device; events more frequent than 100 ms are dropped. In Verborra/Services/Logging/DiagnosticLogger.swift or a separate BluetoothLogThrottle
- [X] T029 [US1] Add audio stream logging: INFO — stream enumeration; DEBUG — each stream format, sample rate change at runtime, format mismatch. Category: stream in Verborra/Services/AudioCaptureService.swift
- [X] T030 [US1] Add stopRecording logging: INFO — recording stop, duration; DEBUG — data size, buffer count; ERROR — stop errors in Verborra/Services/AudioCaptureService.swift

### Tests for US1

- [X] T066 [P] [US1] Unit test BluetoothLogThrottle: events more frequent than 100 ms per-device are dropped; different devices are throttled independently; an event after 100 ms passes through in VerborraTests/Logging/BluetoothLogThrottleTests.swift

**Checkpoint**: US1 complete — all audio events appear in Console.app and JSONL when devices are connected/disconnected

---

## Phase 4: User Story 5 — Retrospective incident analysis (Priority: P2)

**Goal**: Every ERROR message is self-sufficient — contains breadcrumbs (20 steps), state, error code

**Independent Test**: Simulate an error (disconnect Bluetooth during recording) → verify that ERROR contains the full event chain

### Implementation

- [X] T031 [US5] Integrate FlowTracker into RecordingViewModel: beginFlow() on hotkey press, endFlow() on paste completion or error; pass flowId to services in Verborra/ViewModels/RecordingViewModel.swift
- [X] T032 [US5] Add breadcrumb points to AudioCaptureService: engine_created, engine_started, tap_installed, device_selected, recording_started, recording_stopped in Verborra/Services/AudioCaptureService.swift
- [X] T033 [US5] Add breadcrumb points to TranscriptionService: request_sent, response_received in Verborra/Services/TranscriptionService.swift
- [X] T034 [US5] Add breadcrumb points to FormattingService and StreamingFormattingService: request_sent, response_received, stream_chunk in Verborra/Services/FormattingService.swift and Verborra/Services/StreamingFormattingService.swift
- [X] T035 [US5] Add breadcrumb points to PasteService: paste_attempted, paste_completed in Verborra/Services/PasteService.swift
- [X] T036 [US5] Implement AppState snapshot collection in DiagnosticLogger.error(): activeDevice, recordingStatus, recordingDuration, currentOperation from RecordingViewModel in Verborra/Services/Logging/DiagnosticLogger.swift
- [X] T037 [US5] Update all log.error() calls in AudioCaptureService: include ErrorContext with method, parameters, errorCode; when flowId is present — drain breadcrumbs in Verborra/Services/AudioCaptureService.swift

### Tests for US5

- [X] T038 [P] [US5] Unit test: ERROR message contains breadcrumbs when there is an active flow; breadcrumbs = [] when no flow in VerborraTests/Logging/ErrorContextTests.swift

**Checkpoint**: US5 complete — ERROR messages contain full action chain and state

---

## Phase 5: User Story 2 — Debugging API requests (Priority: P2)

**Goal**: All API requests (Whisper, Chat Completions) are logged with URL, status, time; in DEBUG — full payload

**Independent Test**: Record and transcribe audio → check all API interaction stages in the log

### Implementation

- [X] T039 [P] [US2] Add logging to TranscriptionService: INFO — URL, HTTP method, payload size, status, execution time; DEBUG — headers (API key masked), request parameters, response body (first 500 characters); ERROR — HTTP 4xx/5xx with response body. Category: api in Verborra/Services/TranscriptionService.swift
- [X] T040 [P] [US2] Add logging to FormattingService: INFO — URL, method, size, status, time; DEBUG — headers (API key masked), request body (prompt and text — first 500 characters), response body (first 500 characters). Category: api in Verborra/Services/FormattingService.swift
- [X] T041 [P] [US2] Add logging to StreamingFormattingService: INFO — URL, method, model, status, time; DEBUG — headers (API key masked), system prompt and user text (first 500 characters), accumulated response (first 500 characters). Category: api in Verborra/Services/StreamingFormattingService.swift
- [X] T042 [US2] Add logging to ProcessingRouter: INFO — selected processing route (STT/LLM), result; ERROR — routing errors. Category: api in Verborra/Services/ProcessingRouter.swift

**Checkpoint**: US2 complete — all API calls are visible in the log with full metadata

---

## Phase 6: User Story 3 — Diagnosing permissions (Priority: P2)

**Goal**: Permission requests/checks (microphone, Accessibility) are logged with the result

**Independent Test**: Revoke microphone permission → try to record → check the log

### Implementation

- [X] T043 [P] [US3] Add logging to PermissionManager: INFO — microphone request (granted/denied result), Accessibility check (result), status change; ERROR — access denied with context. Category: permissions in Verborra/Services/PermissionManager.swift

**Checkpoint**: US3 complete — all permission events recorded in the log

---

## Phase 7: User Story 4 — Tracking user actions (Priority: P3)

**Goal**: User actions (hotkey, settings, prompts) are logged for reproducing scenarios

**Independent Test**: Perform a typical scenario (hotkey → recording → settings) → check the trace

### Implementation

- [X] T044 [P] [US4] Add logging to HotkeyService: INFO — hotkey triggered, recording state before/after. Category: userAction in Verborra/Services/HotkeyService.swift
- [X] T045 [P] [US4] Add logging to RecordingViewModel: INFO — recording start/end, prompt selection, language change; DEBUG — intermediate states. Category: userAction in Verborra/ViewModels/RecordingViewModel.swift
- [X] T046 [P] [US4] Add logging to SettingsViewModel: INFO — settings changes (old → new value, except API key); DEBUG — all changes. Mask API key. Category: settings in Verborra/ViewModels/SettingsViewModel.swift
- [X] T047 [P] [US4] Add logging to PasteService: INFO — text paste (method, result); ERROR — paste errors. Category: system in Verborra/Services/PasteService.swift
- [X] T048 [P] [US4] Add logging to TargetAppTracker: INFO — target application tracking (name, bundleId). Category: system in Verborra/Services/TargetAppTracker.swift

**Checkpoint**: US4 complete — full user action trace

---

## Phase 8: User Story 6 — Managing logging and log files (Priority: P3)

**Goal**: The user can change the level in settings, open the logs directory; files are rotated and cleaned up

**Independent Test**: Switch the level in settings → verify level change without restart; verify rotation/cleanup

### Implementation

- [X] T049 [US6] Add "Logging" section to AdvancedSettingsTab: Picker for LogLevel (OFF/ERROR/INFO/DEBUG), Stepper for log retention period (hours, default: 24, FR-014), "Show logs in Finder" button (NSWorkspace.shared.selectFile) in Verborra/Views/AdvancedSettingsTab.swift
- [X] T050 [US6] Add log level change logging: INFO — old level → new level. Category: settings in Verborra/Views/AdvancedSettingsTab.swift
- [X] T051 [US6] Implement deferred OFF switch during active recording: DiagnosticLogger checks recording state and defers OFF until the current operation completes in Verborra/Services/Logging/DiagnosticLogger.swift
- [X] T052 [US6] Add localized strings for logging UI (settings.advanced.logging, settings.advanced.logLevel, settings.advanced.showLogs) to LocalizationManager in Verborra/Services/LocalizationManager.swift
- [X] T053 [US6] Add disk full handling: on file write error switch to os_log only, attempt cleanup, log a warning in Verborra/Services/Logging/JSONLFileWriter.swift

### Tests for US6

- [X] T054 [P] [US6] Unit test: dynamic switching — changing logLevel in AppSettings at runtime immediately changes filtering (before and after switching) in VerborraTests/Logging/LogLevelFilterTests.swift
- [X] T067 [P] [US6] Unit test: deferred OFF during active recording — switching to OFF is deferred until the current operation completes; after completion OFF is applied; without active recording OFF is applied immediately in VerborraTests/Logging/DeferredOffTests.swift

**Checkpoint**: US6 complete — logging management fully functional

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final verification, integration of remaining services, security

- [X] T055 [P] Add logging to KeychainService: INFO — save/delete operations (no secrets); ERROR — Keychain errors. Category: system in Verborra/Services/KeychainService.swift
- [X] T056 [P] Add logging to PromptsStore: INFO — prompt loading/saving. Category: settings in Verborra/Services/PromptsStore.swift
- [X] T057 [P] Add logging to APIKeyValidationService: INFO — validation result (valid/invalid). Category: api in Verborra/Services/APIKeyValidationService.swift
- [X] T058 [P] Add logging to MarkdownStripper: DEBUG — input/output data (text length, without content). Category: system in Verborra/Services/MarkdownStripper.swift
- [X] T068 [P] Add logging to AutostartService (SMAppService): INFO — autostart enable/disable, registration result. Category: system in Verborra/ViewModels/SettingsViewModel.swift
- [X] T059 [P] Add logging to OnboardingViewModel: INFO — onboarding stages (start, completion, skip). Category: lifecycle in Verborra/ViewModels/OnboardingViewModel.swift
- [X] T060 [P] Add logging to LocalizationManager: INFO — language change (old → new). Category: settings in Verborra/Services/LocalizationManager.swift
- [X] T061 Security audit: grep through all log.info/log.debug calls for API key, audio data, recognized text leaks. Ensure SensitiveMasker is applied everywhere
- [ ] T062 Run quickstart.md scenarios 1-8 and verify correctness of logging
- [ ] T063 Check SC-006: measure logging overhead (< 10 ms on hotkey → recording)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — starts immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all User Stories
- **US1 (Phase 3)**: Depends on Foundational — MVP, starts first
- **US5 (Phase 4)**: Depends on US1 (breadcrumbs are added at points instrumented in US1)
- **US2 (Phase 5)**: Depends on Foundational — in parallel with US3
- **US3 (Phase 6)**: Depends on Foundational — in parallel with US2
- **US4 (Phase 7)**: Depends on Foundational — in parallel with US2/US3
- **US6 (Phase 8)**: Depends on Foundational (UI needs LogLevel in AppSettings)
- **Polish (Phase 9)**: Depends on all User Stories

### User Story Dependencies

- **US1 (P1)**: Foundational → US1 (independent)
- **US5 (P2)**: Foundational → US1 → US5 (depends on US1 for breadcrumb points)
- **US2 (P2)**: Foundational → US2 (independent of other US)
- **US3 (P2)**: Foundational → US3 (independent of other US)
- **US4 (P3)**: Foundational → US4 (independent of other US)
- **US6 (P3)**: Foundational → US6 (independent of other US)

### Within Each User Story

- Models/infrastructure → service integration → tests
- Core implementation → error handling → edge cases

### Parallel Opportunities

- T002-T007: all models in parallel
- T018-T023: all Phase 2 unit tests in parallel
- T039-T041: all API services in parallel (US2)
- T044-T048: all user action services in parallel (US4)
- T055-T060: all remaining services in parallel (Polish)
- US2, US3, US4, US6 can run in parallel (after Foundational)

---

## Parallel Example: Phase 2 (Foundational)

```bash
# In parallel — all models (different files):
T002: LogLevel.swift
T003: LogCategory.swift
T004-T007: LogEntry.swift (single file, but independent structs)

# Sequential — dependencies:
T008 (SensitiveMasker) → T013 (DiagnosticLogger uses SensitiveMasker)
T009-T010 (FlowTracker) → T013 (DiagnosticLogger uses FlowTracker)
T011 (JSONLFileWriter) → T013 (DiagnosticLogger uses JSONLFileWriter)
T012 (LogFileManager) → T011 (JSONLFileWriter uses LogFileManager)
T014 (AppSettings.logLevel) → T013 (DiagnosticLogger reads logLevel)
T013 (DiagnosticLogger) → T016-T017 (initialization in VerborraApp)

# In parallel — all tests:
T018-T023: each test file is independent
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete Phase 1: Setup (T001-T007)
2. Complete Phase 2: Foundational (T008-T023)
3. Complete Phase 3: US1 — audio instrumentation (T024-T030)
4. **STOP and VALIDATE**: connect a Bluetooth device, verify logs
5. Audio subsystem logging works — MVP is ready

### Incremental Delivery

1. Setup + Foundational → logging core ready
2. + US1 → audio diagnostics (MVP!)
3. + US5 → self-sufficient ERROR messages with breadcrumbs
4. + US2 → API diagnostics
5. + US3 → permissions diagnostics
6. + US4 → user action trace
7. + US6 → management UI + rotation/cleanup
8. + Polish → full integration of all services

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label ties the task to a specific User Story
- Each User Story is independently testable after completion
- Commit after each task or logical group
- Stop at any checkpoint for validation
