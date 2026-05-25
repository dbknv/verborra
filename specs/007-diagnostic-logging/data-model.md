# Data Model: Diagnostic Logging

**Feature**: 007-diagnostic-logging
**Date**: 2026-03-19

## Entities

### LogLevel

Application logging mode. Determines which messages are recorded.

```swift
enum LogLevel: Int, Codable, CaseIterable, Comparable {
    case off = 0
    case error = 1
    case info = 2
    case debug = 3

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

**Storage**: `@AppStorage("logLevel")` as Int (rawValue).
**Default value**: `.info` (rawValue = 2).

**Inclusion hierarchy**:
- OFF → nothing
- ERROR → only error
- INFO → error + info
- DEBUG → error + info + debug

### LogCategory

Module category for filtering in Console.app and JSONL.

```swift
enum LogCategory: String, Codable, CaseIterable {
    case audio        // AudioCaptureService — devices, selection
    case bluetooth    // AudioCaptureService — Bluetooth-specific events
    case engine       // AudioCaptureService — AVAudioEngine lifecycle
    case tap          // AudioCaptureService — input node tap
    case stream       // AudioCaptureService — audio streams, formats
    case api          // TranscriptionService, FormattingService
    case permissions  // PermissionManager
    case userAction   // RecordingViewModel, HotkeyService
    case lifecycle    // VerborraApp (AppDelegate)
    case settings     // SettingsViewModel, AppSettings
    case system       // PasteService, TargetAppTracker
}
```

**Mapping to os.Logger**: `os.Logger(subsystem: "dev.apeek.verborra", category: rawValue)`

### LogEntry

A single log record. Serialized to JSONL.

```swift
struct LogEntry: Codable {
    let timestamp: String        // ISO 8601: "2026-03-19T14:30:05.123+03:00"
    let level: String            // "ERROR", "INFO", "DEBUG"
    let category: String         // LogCategory.rawValue
    let sessionId: String        // UUID string, identical for the whole run
    let message: String          // Message text
    let metadata: [String: String]?  // Optional key-value pairs
    let error: ErrorContext?     // Only for ERROR messages
}
```

**Size**: ~200-500 bytes (INFO), ~1-5 KB (ERROR with breadcrumbs), ~0.5-2 KB (DEBUG with payload).

### ErrorContext

Error context for self-sufficient diagnostics (only in ERROR messages).

```swift
struct ErrorContext: Codable {
    let description: String            // What broke
    let method: String                 // Method name
    let parameters: [String: String]?  // Call parameters (masked)
    let errorCode: String?             // Error code or exception type
    let state: AppState?               // State at the moment of error
    let breadcrumbs: [Breadcrumb]      // Last 20 actions in the flow
}
```

### AppState

Snapshot of the application state at the moment of the error.

```swift
struct AppState: Codable {
    let activeDevice: String?        // Name of current audio device
    let recordingStatus: String      // "idle", "recording", "processing"
    let recordingDuration: Double?   // Seconds (if recording)
    let currentOperation: String?    // "transcription", "formatting", "paste"
}
```

### Breadcrumb

One step in the action chain (a ring buffer element).

```swift
struct Breadcrumb: Codable {
    let timestamp: String            // ISO 8601 with ms
    let label: String                // Short description: "engine_started", "tap_installed"
    let category: String             // LogCategory
    let metadata: [String: String]?  // Optional context
}
```

**Maximum**: 20 breadcrumbs per flow (RingBuffer capacity).

### SessionID

Unique application run identifier.

- **Format**: UUID v4 (string, 36 characters)
- **Generation**: once on `applicationDidFinishLaunching`
- **Storage**: in-memory (not persisted between runs)
- **Usage**: included in every LogEntry.sessionId

## Relationships between entities

```
AppSettings
  └── logLevel: LogLevel (persisted)

DiagnosticLogger (per category)
  ├── category: LogCategory
  ├── os.Logger (subsystem + category)
  └── → JSONLFileWriter (shared)

JSONLFileWriter
  ├── → LogEntry (serializes to JSONL)
  └── → LogFileManager (rotation, cleanup)

FlowTracker
  ├── flowId: UUID → RingBuffer<Breadcrumb>
  └── → ErrorContext.breadcrumbs (on drain)

LogEntry
  ├── level → LogLevel
  ├── category → LogCategory
  ├── sessionId → SessionID
  └── error → ErrorContext? (only for ERROR)

ErrorContext
  ├── state → AppState (snapshot)
  └── breadcrumbs → [Breadcrumb] (from FlowTracker)
```

## JSONL format (examples)

### INFO message

```json
{"timestamp":"2026-03-19T14:30:05.123+03:00","level":"INFO","category":"audio","sessionId":"a1b2c3d4-e5f6-7890-abcd-ef1234567890","message":"Device selected","metadata":{"deviceName":"MacBook Pro Microphone","deviceId":"BuiltInMicrophoneDevice","type":"builtin"}}
```

### ERROR message

```json
{"timestamp":"2026-03-19T14:30:07.456+03:00","level":"ERROR","category":"engine","sessionId":"a1b2c3d4-e5f6-7890-abcd-ef1234567890","message":"Audio engine failed to start","error":{"description":"Engine start failed: device busy","method":"prepareAndStartEngine","parameters":{"deviceID":"AirPods-XXXX"},"errorCode":"AVAudioEngineError.cannotStart","state":{"activeDevice":"AirPods Pro","recordingStatus":"recording","recordingDuration":12.5,"currentOperation":"recording"},"breadcrumbs":[{"timestamp":"2026-03-19T14:29:55.100+03:00","label":"hotkey_triggered","category":"userAction"},{"timestamp":"2026-03-19T14:29:55.200+03:00","label":"device_selected","category":"audio","metadata":{"device":"AirPods Pro"}},{"timestamp":"2026-03-19T14:29:55.300+03:00","label":"engine_created","category":"engine"},{"timestamp":"2026-03-19T14:30:07.450+03:00","label":"engine_start_attempted","category":"engine"}]}}
```

### DEBUG message

```json
{"timestamp":"2026-03-19T14:30:05.200+03:00","level":"DEBUG","category":"tap","sessionId":"a1b2c3d4-e5f6-7890-abcd-ef1234567890","message":"Tap installed on input node","metadata":{"sampleRate":"16000","channels":"1","bufferSize":"4096","format":"f32"}}
```
