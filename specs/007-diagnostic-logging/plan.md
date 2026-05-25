# Implementation Plan: Diagnostic Logging

**Branch**: `007-diagnostic-logging` | **Date**: 2026-03-19 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/007-diagnostic-logging/spec.md`

## Summary

Structured logging system for all components of the Verborra application.
Two independent sinks: os.Logger (Apple Unified Logging for Console.app / Xcode)
and JSONL file (for retrospective analysis and transfer to the developer).
Four modes (OFF / ERROR / INFO / DEBUG), asynchronous serial queue for writing,
file rotation by time (1 hour) and size (50 MB), auto-deletion after 24 hours,
per-flow breadcrumb trail (20 steps) for contextual ERROR messages.
Level configured in Advanced Settings without restart.

## Technical Context

**Language/Version**: Swift 5.9+ (Xcode 15+)
**Primary Dependencies**: os.Logger (Unified Logging System), Foundation (FileHandle, DispatchQueue)
**Storage**: JSONL files in ~/Library/Application Support/Verborra/Logs/; UserDefaults for level setting
**Testing**: XCTest / Swift Testing
**Target Platform**: macOS 15 (Sequoia) and newer
**Project Type**: Single macOS app (Xcode project + SPM)
**Performance Goals**: Logging MUST NOT add > 10 ms to hotkey reaction time (SC-006)
**Constraints**: Asynchronous serial queue — logging call does NOT block the calling thread; real-time audio callback
**Scale/Scope**: ~16 services to instrument, 11 logging categories

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Comment |
|---------|--------|-------------|
| P1: Native macOS experience | PASS | os.Logger — native Apple API; settings in SwiftUI |
| P2: Swift-first | PASS | All code in Swift; no external dependencies |
| P3: Minimalism | PASS | One section added in Advanced Settings; does not affect main UI |
| P4: Security | PASS | API keys are masked; audio contents are not logged; `.private` in os_log |
| P5: Code quality | PASS | Protocol-based architecture; unit tests for logic (Constitution) |
| P6: Logging | PASS | This feature implements Principle 6 in full |

**Gate Result**: ALL PASS — no violations, Complexity Tracking not required.

## Project Structure

### Documentation (this feature)

```text
specs/007-diagnostic-logging/
├── plan.md              # This file
├── research.md          # Phase 0: architectural decisions
├── data-model.md        # Phase 1: data model
├── quickstart.md        # Phase 1: quick verification scenarios
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
Verborra/
├── Models/
│   ├── LogLevel.swift           # Enum OFF/ERROR/INFO/DEBUG
│   ├── LogCategory.swift        # Enum of categories (audio, api, ...)
│   └── LogEntry.swift           # Codable struct for JSONL
├── Services/
│   ├── Logging/
│   │   ├── DiagnosticLogger.swift    # Facade: os.Logger + JSONLFileWriter
│   │   ├── JSONLFileWriter.swift     # Async serial queue, FileHandle, flush
│   │   ├── LogFileManager.swift      # Rotation, cleanup, directory management
│   │   ├── FlowTracker.swift         # Per-flow breadcrumb ring buffer
│   │   └── SensitiveMasker.swift     # API key and PII masking
│   ├── AudioCaptureService.swift     # + audio event logging
│   ├── TranscriptionService.swift    # + API request logging
│   ├── FormattingService.swift       # + API request logging
│   ├── StreamingFormattingService.swift # + logging
│   ├── PermissionManager.swift       # + permissions logging
│   ├── HotkeyService.swift           # + hotkey logging
│   ├── PasteService.swift            # + system call logging
│   ├── TargetAppTracker.swift        # + logging
│   ├── PromptsStore.swift            # + action logging
│   ├── KeychainService.swift         # + logging (no secrets)
│   └── ...
├── ViewModels/
│   ├── RecordingViewModel.swift      # + flow lifecycle logging
│   ├── SettingsViewModel.swift       # + settings change logging
│   └── ...
├── Views/
│   └── AdvancedSettingsTab.swift      # + UI for log level and Finder link
└── VerborraApp.swift                  # + LoggingService initialization at launch
```

**Structure Decision**: New logging files are placed in `Verborra/Services/Logging/`
(subdirectory inside the existing Services structure). Models — in `Verborra/Models/`.
No changes to the project structure; instrumentation — by adding calls
to existing services.

## Architectural decisions

### 1. Dual-Sink facade (DiagnosticLogger)

```
DiagnosticLogger (per-category)
    ├── os.Logger (subsystem: "dev.apeek.verborra", category: "audio" / "api" / ...)
    └── JSONLFileWriter (shared singleton)
            └── DispatchQueue (serial, qos: .utility)
                 ├── FileHandle (append mode)
                 └── DispatchSourceTimer (flush every 5 sec)
```

- Each service gets its own `DiagnosticLogger` instance with a unique category.
- `DiagnosticLogger` checks the current `LogLevel` (from `AppSettings`) before dispatching.
- Logging call does NOT block — data is passed to the serial queue asynchronously.
- `os_log` is called on the calling thread (internally async — FR-022 requirement satisfied natively), JSONL — through queue.

### 2. Levels and filtering

```
OFF    → nothing is written (both sinks disabled)
ERROR  → only errors + breadcrumb context
INFO   → errors + key lifecycle events
DEBUG  → everything (including API payload — first 500 characters, audio parameters, intermediate states)
```

The level is stored in `AppSettings` via `@AppStorage("logLevel")`.
The change takes effect immediately (checked on every logging call).
Exception: OFF during active recording is deferred until the current operation completes.

### 3. JSONL files and rotation

- Directory: `~/Library/Application Support/Verborra/Logs/`
- File name: `verborra-yyyy-MM-dd'T'HH.jsonl` (hourly granularity)
- Rotation: every hour OR at 50 MB (whichever comes first)
- Cleanup: files older than 24 hours are deleted at startup + every hour
- Flush: immediate on ERROR; periodic (every 5 sec) for INFO/DEBUG
- Disk full: switch to os_log only, attempt cleanup

### 4. Per-flow breadcrumb trail

- `FlowTracker` stores `RingBuffer<Breadcrumb>(capacity: 20)` by flow UUID.
- Flow begins on the initiating action (hotkey press → recording start → API → paste).
- On ERROR: breadcrumbs are drained and included in the JSONL record.
- Thread-safety: NSLock (low contention).

### 5. Sensitive data masking

- `os_log`: `\(value, privacy: .private)` for API keys
- JSONL: `SensitiveMasker` — API key masking before serialization:
  - API key → `sk-...XXXX` (last 4 characters)
  - Recognized text → logged in DEBUG (first 500 characters)
  - API request/response payload → logged in DEBUG (first 500 characters)
  - Audio buffer → never logged (only metadata: samples, format)

### 6. Logging categories

| Category | Subsystem | Service(s) |
|----------|-----------|-----------|
| audio | dev.apeek.verborra | AudioCaptureService |
| bluetooth | dev.apeek.verborra | AudioCaptureService (device events) |
| engine | dev.apeek.verborra | AudioCaptureService (AVAudioEngine) |
| tap | dev.apeek.verborra | AudioCaptureService (input tap) |
| stream | dev.apeek.verborra | AudioCaptureService (audio streams) |
| api | dev.apeek.verborra | TranscriptionService, FormattingService, StreamingFormattingService, ProcessingRouter |
| permissions | dev.apeek.verborra | PermissionManager |
| userAction | dev.apeek.verborra | RecordingViewModel, SettingsViewModel, HotkeyService |
| lifecycle | dev.apeek.verborra | VerborraApp (AppDelegate) |
| settings | dev.apeek.verborra | SettingsViewModel, AppSettings |
| system | dev.apeek.verborra | PasteService, TargetAppTracker, AutostartService |

### 7. Integration with existing code

Integration pattern — minimally invasive:

```swift
// In an existing service — one line is added at the beginning of the method:
func startRecording(deviceID: String?, maxDuration: MaxRecordingDuration) async throws {
    log.info("startRecording", metadata: ["deviceID": deviceID ?? "default", "maxDuration": "\(maxDuration)"])
    // ... existing code unchanged ...
}
```

Services receive `DiagnosticLogger` as a property (not through DI constructor,
to minimize changes in signatures). Each service creates
its own logger via a factory method:

```swift
private let log = DiagnosticLogger.logger(for: .audio)
```
