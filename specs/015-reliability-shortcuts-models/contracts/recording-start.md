# Contract: Recording Start, Retry and Cancel (US2)

**Requirements**: FR-007…FR-013a, FR-048…FR-057 (microphone switch) | **Research**: R5–R11, R31 | **Model**: [data-model.md §3](../data-model.md#3-recording-start-us2)

## Threading rules (non-negotiable)

1. Any call to `AVAudioEngine`, `AVAudioInputNode`, `AudioUnitSetProperty` or `AudioObjectGetPropertyData` made **during start or stop** runs on the `AudioEngineHost` serial queue, never on the main thread. The device enumeration in `AudioDeviceManager`/`CoreAudioDeviceProvider` is out of scope.
2. The host never reads or writes `@MainActor` state. It only receives value parameters and returns value results.
3. `installTap`, `prepare`, `start`, `stop` and `removeTap` are each wrapped in `VBRTryCatch`.
4. Cancelling never blocks on the host queue.

## Host interface

```swift
protocol AudioEngineHosting: AnyObject, Sendable {
    /// Runs on the host queue. Throws AudioSetupError. Calls `onBuffer` from the real-time tap thread.
    func start(deviceID: AudioDeviceID?, generation: UInt64,
               onBuffer: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)
        async throws -> (timings: AudioSetupTimings, nodeFormat: AVAudioFormat, resolvedDevice: AudioDeviceID)
    /// Fire-and-forget teardown for `generation` (or the current one). Never awaited by cancel paths.
    func teardown(generation: UInt64?)
    /// Synchronous on host queue; used by stopRecording after capture completed.
    func stop() async
}

enum AudioSetupError: Error {
    case deviceUnavailable(step: String)
    case formatMismatch(node: Double, hardware: Double)   // still mismatched after one re-create
    case objcException(step: String, name: String, reason: String)
    case engineStartFailed(step: String, underlying: String)
    case timeout(step: String)                            // raised by the facade, not the host
    case cancelled
}
```

## Host start sequence

| # | Step | Timed as | Notes |
|---|---|---|---|
| 1 | `AVAudioEngine()` and access `inputNode` | `engineCreate` | |
| 2 | Set the device (`kAudioOutputUnitProperty_CurrentDevice`) if `deviceID != nil`; check the result `OSStatus` | `setDevice` | non-zero → `deviceUnavailable` |
| 3 | Read `inputNode.outputFormat(forBus:0)` and the device's nominal sample rate | `readFormats` | channelCount 0 or rate 0 → `deviceUnavailable` |
| 3a | If the node rate ≠ the hardware rate: drop the engine, repeat steps 1–3 **once** | adds `recreatedForStaleNode=true` | still ≠ → `formatMismatch` |
| 4 | `installTap(onBus:0, bufferSize:4096, format: nil)` | `installTap` | ObjC-guarded |
| 5 | `prepare()` | `prepare` | ObjC-guarded |
| 6 | `try start()` | `start` | ObjC-guarded |

## Facade: `AudioCaptureService.startRecording` (one attempt per call)

```swift
func startRecording(deviceID: String?, maxDuration: MaxRecordingDuration,
                    awaitBluetoothSwitch: Bool, attempt: Int,
                    setupTimeout: Duration, firstBufferTimeout: Duration,
                    bluetoothTimeout: Duration) async throws
func cancelStart()   // non-blocking
```

Each call makes **one** attempt: an optional Bluetooth stabilization (only when `awaitBluetoothSwitch`, which the view model sets for attempt 1 only), then the host start raced against `setupTimeout`, then a wait for the first buffer up to `firstBufferTimeout`. If the engine is running without buffers when that wait expires, the attempt counts as **success** (same as today). The Bluetooth trigger is raced against `bluetoothTimeout`, not `setupTimeout`. The host is reused unless a call on it timed out (`hostIsStuck`); a teardown queued by `resetRecording` or `cancelStart` therefore runs before the next start on the same serial queue, so stopping one microphone and starting another never overlap (FR-050). The call resolves the device's display name before starting, so every log line names the microphone. It never retries and never changes the device.

## Retry orchestration and budget (`RecordingViewModel`)

| Phase | Budget | On expiry or failure |
|---|---|---|
| Bluetooth mode switch (Bluetooth devices only, inside attempt 1) | existing 5 s stabilization timeout; shows "Switching…" | continues with the current rate (unchanged) |
| Attempt 1: `setupTimeout` / `firstBufferTimeout` | 1.8 s / 0.6 s | → `.starting(2)` |
| Attempt 2: same device | `setupTimeout = min(2.4 s, remaining of 5.0 s)`, `firstBufferTimeout = 0.6 s` capped by what remains | → `.error(.recordingStartFailed)` |

The 5.0 s overall budget is measured from the hotkey press, or for Bluetooth devices from the end of the mode switch (spec FR-007). From then until `.recording` or `.error` takes ≤ 5.0 s. For `.initial` starts `bluetoothTimeout` is 5 s.

## Microphone switch (`StartKind.switching`, R31)

| Step | Rule |
|---|---|
| Trigger | `switchAudioDevice` while `.recording`, or while `.error(.recordingStartFailed)` with `lastStartKind == .switching` |
| Before starting | `stopTimers()`, `audioCaptureService.resetRecording()` (audio so far is discarded), restore A2DP on the previous device if it was Bluetooth |
| Budget | one 5.0 s budget from the switch request, **including** Bluetooth preparation and trigger (`bluetoothTimeout = remaining`) (FR-049) |
| Attempts | same as `.initial`: attempt 1 → attempt 2 on the same device → `.error(.recordingStartFailed(reason, deviceName:))` |
| During the switch | `.starting(attempt:)`; UI "Switching to <name>…"; keys 1–3 and menus disabled; Cancel, Esc, ⌘W, close and the hotkey cancel it (FR-051, FR-052, FR-054, FR-056) |
| Cancel | the usual `cancelStart`, plus `restoreA2DP` on the target if it is Bluetooth and was prepared (FR-055) |
| Failure | Bluetooth target: restore A2DP. `lastStartKind = .switching`, so picking another microphone starts a new switch (FR-053) |
| Log | E16 `Microphone switch` once per switch (FR-057) |

## View model contract

| Event | State before | Result |
|---|---|---|
| Hotkey / Start button | `.idle` | `.starting(1)`, `startTask` created, HangContext stage `starting.1` |
| Attempt 1 fails | `.starting(1)` | ERROR logged; `.starting(2)` |
| Attempt 2 fails | `.starting(2)` | `.error(.recordingStartFailed(reason))`; Retry visible |
| Success | `.starting(n)` | `.recording(0, max)`; timers start |
| Hotkey / Esc / window close | `.starting(n)` | `cancelStart()`: cancel `startTask`, `teardown(generation)`, cancel BT preparation, then `.idle` **synchronously** (≤ 1 s, designed for under 50 ms). INFO `Recording start cancelled` (`attempt`, `elapsedMs`) |
| Retry / hotkey | `.error(.recordingStartFailed)` | `.starting(1)` (same device) |
| Pick another microphone | `.recording` | capture reset, `.starting(1)` with `startKind = .switching(to:)` |
| Pick another microphone | `.error(.recordingStartFailed)` after a switch | `.starting(1)` with `startKind = .switching(to:)` |
| 1 / 2 / 3, menus | `.starting(n)` | ignored, menus disabled (FR-052) |
| Late result from a cancelled or old generation | any | torn down on the host queue; no state change |

**Removed behaviour**: the fallback to the system default device (`AudioCaptureService.swift:687-748`) and `onDeviceFallback`. `selectedAudioDeviceID` is never changed by the start path.

**UI**: in `.starting`, `RecordingView` shows a small spinner with "Starting microphone…", or "Switching to <name>…" for a switch. The Start/Stop button reads "Cancel", with the global shortcut hint.

## Process-level exception policy

- **All builds**: `NSSetUncaughtExceptionHandler` writes ERROR (`name`, `reason`, first 20 `callStackSymbols`), then calls `JSONLFileWriter.shared.flushSync()`.
- **DEBUG builds only** (`#if DEBUG`): `UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])` runs before any UI.
- **Release builds** keep AppKit's default exception handling. Audio exceptions are contained by `VBRTryCatch`, and a stall caused by anything else is reported by the watchdog (research R11).
