# Contract: Diagnostic Events (cross-cutting)

**Requirements**: FR-057, FR-004, FR-010, FR-011, FR-012, FR-022, FR-029, FR-038, FR-040, SC-005 | **Research**: R10–R13, R23, R24

New `LogCategory` cases: `.hotkey`, `.loginItem`, `.watchdog` (constitution P6, one category per new service). All events go through the existing `DiagnosticLogger` (os.Logger plus JSONL, spec 007). They follow the existing masking rules: no keystrokes, transcripts or keys.

## New logger API

```swift
/// WARN severity: written when the active mode is ERROR, INFO or DEBUG (never in OFF).
/// os.Logger level: .error. Does NOT consult appStateProvider, so it's safe from any thread.
func warn(_ message: String, metadata: [String: String]? = nil)
```

JSONL: `"level": "WARN"`. The user-selectable modes stay OFF/ERROR/INFO/DEBUG.

**Thread-safe filtering**: `shouldLog` reads only a lock-protected `LogFilterSnapshot(level, isRecordingActive)`, which the main thread updates when the log level or the recording state changes. It never calls `logLevelProvider`, `isRecordingActiveProvider` or `appStateProvider`, so any log call is safe from the watchdog, event-tap and audio threads. `error(...)` adds the app state only when called on the main thread.

## Event catalog

| # | Message | Level | Category | When | Metadata / ErrorContext parameters |
|---|---|---|---|---|---|
| E1 | `Audio setup timings` | INFO | `.engine` | after every start attempt (success or failure) | `attempt`, `generation`, `outcome` (`ok`/`failed`/`timeout`/`cancelled`), `deviceName`, `deviceID`, `engineCreateMs`, `setDeviceMs`, `readFormatsMs`, `installTapMs`, `prepareMs`, `startMs`, `firstBufferMs`, `nodeSampleRate`, `hwSampleRate`, `channels`, `recreatedForStaleNode` |
| E2 | `Audio setup failed` | ERROR | `.engine` | every failed attempt | `method`, `step`, `attempt`, `deviceName`, `deviceID`, `nodeSampleRate`, `hwSampleRate`, `reason`; `errorCode` ∈ `timeout`, `formatMismatch`, `objcException:<name>`, `engineStartFailed`, `deviceUnavailable` |
| E3 | `Recording start failed after retry` | ERROR | `.audio` | `.starting(2)` → `.error` | `deviceName`, `deviceID`, `totalMs`, `reason` |
| E4 | `Recording start cancelled` | INFO | `.userAction` | hotkey/Esc/close during `.starting` | `attempt`, `elapsedMs`, `trigger` (`hotkey`/`esc`/`close`) |
| E5 | `Main thread unresponsive` | **WARN** | `.watchdog` | stall > 2.0 s (once per stall) | `stage`, `stageAgeMs`, `deviceName`, `deviceID`, `stallMs` |
| E6 | `Main thread recovered` | INFO | `.watchdog` | after E5, when the pong returns | `stage`, `stallMs` |
| E7 | `Uncaught exception` | ERROR | `.lifecycle` | `NSSetUncaughtExceptionHandler` (any thread) | `name`, `reason`, `thread` (`main`/`background`), `callStack` (first 20 frames, joined) |
| E8 | `Launch at login changed` / `Login item …` | INFO / ERROR | `.loginItem` | see [login-item.md](./login-item.md) | `old`, `new`, `statusBefore`, `statusAfter`, `error` |
| E9 | `Global shortcut changed` / `rejected` / `registration failed` | INFO / INFO / ERROR | `.hotkey` | see [global-shortcut.md](./global-shortcut.md) | `old`, `new`, `candidate`, `reason`, `mechanism` |
| E10 | `Event tap re-enabled` | INFO | `.hotkey` | tap disabled by timeout or user input | `reason` |
| E11 | `Prompt changed` | INFO | `.userAction` | menu or key 3 | `from`, `to`, `source` |
| E12 | `Hotkey triggered` | INFO | `.userAction` | existing event, extended | + `mechanism` (`carbon`/`eventTap`), `state` |
| E13 | `Recording ready` | INFO | `.audio` | `.starting` → `.recording` | `hotkeyToReadyMs` (start request to `.recording`, excluding any Bluetooth mode switch), `btSwitchMs` (0 if none), `attempts`, `deviceName`, `deviceID` |
| E14 | `Model selection migrated` | INFO | `.lifecycle` | launch, once per migrated key (US7) | `kind` (`stt`/`llm`), `old`, `new`, `reason` (`removed`/`inheritedDefault`); see [model-selection.md](./model-selection.md) |
| E15 | `Chat Completions API error` / `Streaming API error` / transcription error with `modelUnavailable` | ERROR | `.api` | OpenAI says the model isn't available (FR-040) | `method`, `model`, `status`, `message`; `errorCode` = OpenAI `error.code` or HTTP status; see [openai-requests.md](./openai-requests.md) |
| E16 | `Microphone switch` | INFO (ERROR when `outcome=failed`, with `errorCode: microphoneSwitchFailed`) | `.audio` | once per switch, when it ends | `from`, `to` (display names), `outcome` (`ok`/`failed`/`cancelled`), `durationMs`, `attempts`, `trigger` when cancelled (`hotkey`/`esc`/`close`/`button`); when failed also `reason` and `deviceID` (constitution P6) |

## Constraints

- E5 and E6 are produced on the watchdog thread from the `HangContext` snapshot only. They never call `appStateProvider` or any `@MainActor` API.
- E7 and E10 can be written off the main thread; they rely on the thread-safe filtering above.
- Shortcut values in E9 (`old`, `new`, `candidate`) are settings the user deliberately entered in Settings (constitution P6 requires old → new), not captured keystrokes. The event tap (E10, E12) never logs key codes or characters of the events it sees (constitution P4).
- E13 is the evidence for constitution Principle 3 (hotkey to ready ≤ 300 ms on the normal path).
- E1 and E2 are written by `AudioCaptureService` on main after the host returns. If the host never returns (stalled), the facade's timeout path writes E2 with `step` set to the last step the host reported starting. The host publishes `currentStep` via an atomic for this purpose.
- E7 must `flushSync()` before returning, because the process is about to crash.
- The volume of E1 is one line per recording start, which is acceptable at INFO.

## Verification query (used by quickstart)

```bash
cat ~/Library/Application\ Support/Verborra/Logs/*.jsonl \
  | jq -c 'select(.level=="WARN" or .level=="ERROR" or .message=="Audio setup timings")'
```
