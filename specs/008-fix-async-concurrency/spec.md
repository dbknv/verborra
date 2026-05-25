# Specification: Swift Concurrency fixes, race conditions and Bluetooth device support

**Feature Branch**: `008-fix-async-concurrency`
**Created**: 2026-03-18
**Updated**: 2026-03-19
**Status**: Draft
**Input**: Swift compiler warnings about concurrency-safety violations in AudioCaptureService, AudioDeviceManager, OnboardingViewModel, RecordingViewModel. Need to support any Bluetooth devices (AirPods, Jabra, Plantronics, etc.) without race conditions. Concurrency issues in the floating recording window (RecordingViewModel, OverlayPanel) and the onboarding window (OnboardingViewModel) — race conditions when updating UI from timers, incorrect isolation of callbacks.

## User scenarios and testing

### US-1 — Recording via any Bluetooth device without errors (Priority: P1)

The user connects a Bluetooth headset (AirPods, Jabra, Plantronics, Sony, etc.), selects it for recording, and records audio. Recording and stopping complete without failures, freezes, or data races — regardless of the manufacturer and model of the Bluetooth device.

**Why this priority**: Bluetooth headsets are the main scenario for professional use (Jabra, Plantronics in office environments) and everyday use (AirPods). Different devices have different audio profile (SCO/HFP) switching latencies, and the code must correctly handle all variations without race conditions.

**Independent test**: Connect a Bluetooth headset from any manufacturer, start recording, stop recording — the audio is correctly saved into WAV format without UI freezes.

**Acceptance scenarios**:

1. **Given** a Bluetooth headset (AirPods/Jabra/Plantronics/other) is connected and selected as the input device, **When** the user starts and stops the recording, **Then** the recording completes successfully and the data is converted without errors
2. **Given** a Bluetooth device is connected, **When** the user records audio for 30 seconds, **Then** the UI displays the sound level and timer smoothly, without dropped frames
3. **Given** recording is in progress via a Bluetooth headset, **When** the device disconnects (loss of connection, leaving the operating range, battery drain), **Then** the user sees a "Device lost" error and can retry with another device
4. **Given** a Bluetooth headset with audio profile switching latency (>500ms), **When** the user starts a recording, **Then** the record button shows a spinner with the text "Connecting to device…" and becomes inactive, the system waits for the device to be ready and starts recording without losing the initial data

---

### US-2 — Compilation without concurrency warnings (Priority: P1)

The developer compiles the project in Xcode, and the code compiles without warnings related to Swift Concurrency (NSLock in an async context, non-Sendable capture, UnsafeMutableRawPointer to CFString).

**Why this priority**: The warnings will become errors in Swift 6 language mode. Fixing them now prevents blocking the migration to Swift 6.

**Independent test**: Build the project in Xcode — the warnings section does not contain the errors listed in the input.

**Acceptance scenarios**:

1. **Given** the project is open in Xcode, **When** a full build (Clean Build) is executed, **Then** there are no `Instance method 'lock' is unavailable from asynchronous contexts` warnings in AudioCaptureService
2. **Given** the project is built, **Then** there are no `Forming 'UnsafeMutableRawPointer' to a variable of type 'CFString'` warnings in AudioDeviceManager
3. **Given** the project is built, **Then** there is no `Capture of 'self' with non-Sendable type` warning in OnboardingViewModel
4. **Given** the project is built, **Then** there are no concurrency warnings in RecordingViewModel

---

### US-3 — No race conditions during parallel operations (Priority: P1)

The system ensures thread safety for any combinations of simultaneous operations: record/stop, device switching, Bluetooth disconnect, UI updates. No combination of calls leads to a data race, crash, or undefined behavior.

**Why this priority**: Race conditions are a critical data safety issue. When using Bluetooth devices the probability of simultaneous events (device disconnect + recording stop, audio callback + buffer reset) is significantly higher than with wired devices.

**Independent test**: Rapidly press start/stop on the recording while simultaneously disconnecting/connecting a Bluetooth device — the application must not crash or freeze.

**Acceptance scenarios**:

1. **Given** recording is in progress, **When** the user simultaneously presses "Stop" and the Bluetooth device disconnects, **Then** the operation completes correctly without a crash, and the user sees either the result or the error
2. **Given** the user rapidly presses "Start" → "Stop" → "Start" (less than 1 second between actions), **Then** each operation completes correctly, without data corruption
3. **Given** audio buffers are being filled from the audio tap callback, **When** stopRecording is called simultaneously from the main thread, **Then** access to the buffers is synchronized, the data is neither lost nor duplicated
4. **Given** CoreAudio sends a device change notification, **When** recording is in progress and the user simultaneously switches the device, **Then** the system processes both events sequentially without conflict

---

### US-4 — Stable recording when switching devices (Priority: P2)

The user switches the audio device during recording (for example, from the built-in microphone to a Jabra and back). The switch happens correctly — a new recording starts on the selected device without a data race.

**Why this priority**: Device switching activates the code paths with the most concurrency issues (simultaneous buffer access, engine reset). Especially critical for Bluetooth devices with long initialization times.

**Independent test**: Start recording on the built-in microphone, switch to a Bluetooth headset via the UI — the recording continues on the new device.

**Acceptance scenarios**:

1. **Given** recording is in progress on the built-in microphone, **When** the user switches the device to a Bluetooth headset, **Then** the current recording is reset (data is discarded without confirmation and notification), the timer is reset, and a new recording starts on the Bluetooth device
2. **Given** recording is in progress via a Bluetooth headset, **When** the user switches to "System default device", **Then** the current recording is reset (data is discarded), the timer is reset, and a new recording starts on the system device without freezing
3. **Given** the user switches the device during recording, **When** the new Bluetooth device requires time to initialize, **Then** the system correctly waits for readiness and starts the recording or reports an error

---

### US-5 — Device monitoring and handling of CoreAudio events without race conditions (Priority: P2)

The system tracks audio device connect/disconnect events and changes to the system default device. All CoreAudio callbacks are handled in a thread-safe way, without conflicts with the main recording operations.

**Why this priority**: CoreAudio listeners are invoked on arbitrary threads. Without synchronization, simultaneous updates of the device list and reads from the UI/recording code lead to a race condition.

**Independent test**: Connect and disconnect multiple Bluetooth devices in quick succession — the device list updates correctly, the UI does not freeze.

**Acceptance scenarios**:

1. **Given** the application is running, **When** a Bluetooth device connects/disconnects, **Then** the device list updates in the UI without delay and without a crash
2. **Given** recording is in progress on one device, **When** another Bluetooth device connects/disconnects, **Then** the recording is not interrupted and the device list updates correctly
3. **Given** multiple Bluetooth devices connect simultaneously, **Then** all devices appear in the list, and the order in which events are processed does not cause data loss

---

### US-6 — Thread-safe floating recording window (Priority: P1)

The user records audio via the floating window (OverlayPanel). During recording, the countdown timer, the audio level indicator, and the button states update smoothly and without a race condition — even with simultaneous events (device disconnect, recording error, device switch).

**Why this priority**: The floating recording window is the main UI for recording. RecordingViewModel contains multiple timers (durationTimer, levelTimer, inputDurationTimer, inputLevelTimer) that access AudioCaptureService properties from a Timer callback through nested `Task { @MainActor in }`. This creates a race condition when reading `audioLevel` (the service writes from the audio thread, the timer reads from the main thread), as well as redundant context switches (the Timer is already on the main thread → Task @MainActor).

**Independent test**: Start recording via the floating window, observe the timer and audio level indicator — updates are smooth, with rapid start/stop/start there are no freezes or incorrect values.

**Acceptance scenarios**:

1. **Given** recording is in progress via the floating window, **When** the timer and the level indicator update every 50-100ms, **Then** updates happen on the main thread without redundant Task wrapping (removed `Task { @MainActor in }` from Timer callbacks), and the audioLevel and duration values are consistent
2. **Given** recording is in progress, **When** AudioCaptureService updates audioLevel from the audio tap callback, **Then** RecordingViewModel reads the value through a thread-safe mechanism (actor or lock-free), not directly from a property
3. **Given** recording is in progress in the floating window, **When** a device error occurs (onDeviceError callback), **Then** the callback is handled on the main thread, the timers are stopped correctly, the UI transitions to the error state without a crash
4. **Given** the user rapidly presses start/stop in the floating window (less than 300ms between presses), **Then** all timers are correctly created and destroyed without leaks or duplicate firing

---

### US-7 — Thread-safe microphone test in onboarding (Priority: P1)

The user goes through onboarding and tests the microphone. The sound level indicator updates smoothly, and in case of a device error the UI correctly displays an error — without race conditions and crashes.

**Why this priority**: OnboardingViewModel contains an onDeviceError callback that is invoked from an arbitrary CoreAudio thread and directly mutates @Published/@Observable properties (levelTimer, audioLevel, micTestError) without a main-thread isolation guarantee. Also Timer + DispatchQueue.main.async inside a Task @MainActor creates redundant nesting.

**Independent test**: Launch onboarding, start the microphone test, disconnect the Bluetooth device during the test — the level indicator resets, the error is displayed, the UI does not freeze.

**Acceptance scenarios**:

1. **Given** the user has started the microphone test in onboarding, **When** the level indicator updates from the timer, **Then** reading audioLevel from AudioCaptureService happens through a thread-safe mechanism, without a nested DispatchQueue.main.async inside Task @MainActor
2. **Given** the microphone test is in progress, **When** the Bluetooth device disconnects and onDeviceError is invoked, **Then** the callback runs on the main thread (or via an actor), the timer stops, audioLevel resets to 0, and an error message is displayed
3. **Given** the user starts and stops the microphone test several times in a row, **Then** the level timer is correctly created and destroyed on every cycle without leaks

---

### US-8 — Diagnostic logging of asynchronous operations and concurrency events (Priority: P2)

The developer investigates a concurrency bug or a Bluetooth device issue. They open the JSONL log and see the full timeline of asynchronous operations: start/end of recording, device switches, CoreAudio callback events, ring buffer operations, debounce events — with precise timestamps, sessionId and error context. All new asynchronous code paths are covered by logging through the existing DiagnosticLogger infrastructure (007-diagnostic-logging).

**Why this priority**: Concurrency bugs are hard to reproduce. Without logging of asynchronous operations it is impossible to establish the sequence of events that led to a race condition or crash. Logging is the primary tool for postmortem analysis of concurrency incidents.

**Independent test**: Perform a recording with a Bluetooth device switch, open the JSONL log — all events are recorded with categories, timestamps, and sessionId; on error the full breadcrumb chain (up to 20 steps) is recorded.

**Acceptance scenarios**:

1. **Given** DiagnosticLogger is set to INFO level, **When** the user starts and stops a recording, **Then** the log records the events: `startRecording` (with device name), `stopRecording` (with duration), the conversion result — all with category `audio` and a single `sessionId`
2. **Given** the logging level is DEBUG, **When** the audio tap callback writes buffers into the SPSC ring buffer, **Then** the following is logged: number of written/read buffers, ring buffer overflows (`_droppedBuffers`), calls to `updateLevelsFromAtomic()` — with category `tap`
3. **Given** a Bluetooth device disconnects during recording, **When** the system processes the `onDeviceLost` callback, **Then** the ERROR log entry contains: breadcrumb (last 20 actions), current state (device, recording status, duration), category `bluetooth`
4. **Given** the user switches the device during recording, **When** the debounce fires for `onDefaultInputChanged`, **Then** the log records: the original event, the debounce delay, the final switch with old→new device — with category `audio`
5. **Given** the logging level is INFO, **When** CoreAudio invokes a property listener callback, **Then** dispatch events to @MainActor are logged with category `engine` and the time from receiving the callback to the start of processing on the main thread

---

### Edge cases

- What happens if `stopRecording()` is called immediately after `startRecording()` (before the buffers fill up)?
- How does the system handle a simultaneous call to `resetRecording()` from different threads?
- What happens when reading CoreAudio properties for a device that was disconnected between the UID and the name requests?
- A Bluetooth device switches the audio profile (A2DP → HFP) during recording → the system automatically restarts the recording with the new sample rate (FR-014): the engine is recreated, the buffers are reset, the timer is reset. If the restart fails — error "Audio device changed format"
- A Bluetooth device "flaps" (rapid connect/disconnect) → debounce at the device monitoring level: 1 sec for `onDeviceLost` (a single "Device lost" notification per flap series), 500ms for `onDefaultInputChanged` (FR-015). Semantics: latest-wins. If the device reconnects within the debounce window (reconnect within <1 sec), the pending `onDeviceLost` notification MUST be cancelled — the user does not see a false notification
- What happens if the currently recording device is disconnected and the system default device is changed at the same time?
- A Bluetooth device reports itself as available but does not deliver audio data (zero buffers) → silence timeout (10 seconds), auto-stop of the recording with the notification "Device is not transmitting audio"
- What happens if RecordingViewModel is deallocated (the window is closed) during an active recording? → the timers must be invalidated, recording stopped
- What happens when durationTimer and levelTimer fire simultaneously and one of them triggers stopRecording? → the second timer must not read stale state
- OnboardingViewModel: the user closes the onboarding window during a microphone test → the timer and recording must be stopped, resources released
- RecordingViewModel: onDeviceError is invoked during the processing of the stopRecording result → operations must not conflict
- Switching the device during recording to an unavailable device (for example, both Bluetooth devices have disconnected) → startRecording throws an error, the UI shows an error message, the record button returns to the initial state

## Requirements

### Functional requirements

- **FR-001**: The system MUST use `@MainActor` isolation as the primary synchronization mechanism for all operations on shared state (AudioCaptureService, RecordingViewModel, OnboardingViewModel isolated via @MainActor, all mutations serialized on the main thread). Note: a custom Actor was rejected due to incompatibility with @Observable and SwiftUI (see research.md R-001)
- **FR-002**: The system MUST provide thread-safe access to audio buffers from any thread (audio tap callback, main thread, async context). For the real-time audio callback a lock-free ring buffer is used (capacity 256); the main thread periodically (every 50-100ms via `updateLevelsFromAtomic()`) drains buffers from the ring buffer into an accumulating array `accumulatedBuffers: [AVAudioPCMBuffer]`. At stopRecording the accumulating array + the remainder from the ring buffer is used. On ring buffer overflow (write into a full buffer) the buffer MUST be dropped and the `_droppedBuffers` counter incremented for diagnostics — overflow is unlikely with drain every 50-100ms, but it MUST be observable. This ensures thread safety without data loss during long recordings. Note: at the maximum recording length of 5 min (SC-002) at 48kHz / 4096 buffer — ~3500 buffers × ~16KB ≈ 56MB, which is acceptable for a macOS desktop; maxDuration limits the growth
- **FR-003**: The system MUST correctly pass string device identifiers into the CoreAudio API without violating the rules for working with pointers
- **FR-004**: All ViewModels and services MUST correctly capture references in @Sendable closures without warnings about non-Sendable types. Non-Sendable closures MUST be replaced with `@Sendable @MainActor` closures: `onDeviceError` and `onAutoStop` in AudioCaptureService (used by RecordingViewModel and OnboardingViewModel); `onDeviceLost` and `onDefaultInputChanged` in AudioDeviceManager (used only by RecordingViewModel). Alternatives (AsyncStream, delegate via actor) were rejected: AsyncStream complicates lifecycle management (an explicit finish is required), delegate via actor is incompatible with @Observable (see research.md R-001)
- **FR-005**: All project files MUST compile without Swift Concurrency warnings
- **FR-006**: All fixes MUST preserve the existing recording, stopping, and audio conversion behavior without regressions
- **FR-007**: Access to audio buffers from the audio tap callback and from async functions MUST be atomic — a partial read/write situation is impossible. *Note: FR-002 defines the mechanism (SPSC ring buffer), FR-007 defines the guarantee (atomicity of access)*
- **FR-008**: The system MUST support recording from any Bluetooth device recognized by macOS as an audio input (AirPods, Jabra, Plantronics, Sony, Bose, etc.)
- **FR-009**: The system MUST correctly handle Bluetooth device initialization latency when starting a recording (devices with slow profile switching). When the 5-second timeout is exceeded — error "Device is not responding", and the record button returns to the initial state
- **FR-010**: start/stop/reset recording operations MUST be serialized via `@MainActor` isolation — simultaneous execution of two recording operations is impossible. A repeated `startRecording` or `resetRecording` call while a previous one is executing is silently ignored (ignore duplicate, `guard ... else { return }`). Exception: `stopRecording` when there is no active recording MUST throw `RecordingError.notRecording` — the caller depends on the returned `Data`, a silent return of empty data would lead to a conversion error. Serialization of different operations is provided by `@MainActor` — async methods (startRecording, stopRecording) have suspension points, and the next call will start execution only after the current awaited method completes
- **FR-011**: CoreAudio callbacks (device list change, default input change) MUST be processed in a thread-safe manner and must not conflict with recording operations
- **FR-012**: When a Bluetooth device disconnects during recording, the system MUST correctly finish the recording and notify the user within 2 seconds
- **FR-013**: If the connected device does not transmit audio data for 10 seconds (all samples in buffers == 0, which indicates a non-working device rather than a quiet room), the system MUST automatically stop the recording and notify the user with the message "Device is not transmitting audio"
- **FR-014**: When the audio format of the device changes during recording (Bluetooth profile switch, AirPods A2DP→HFP) the system MUST automatically restart the recording with the new format: stop the engine, reset all buffers, recreate the engine with the device's current sample rate, start recording again. The recording timer is reset. If the restart failed — notify the user with the error "Audio device changed format" via `onDeviceError(.formatChanged)`
- **FR-029**: The system MUST obtain the actual sample rate of the audio device through the CoreAudio API (`kAudioDevicePropertyNominalSampleRate`) rather than rely on `inputNode.outputFormat(forBus: 0)`, which may return a stale value. The tap format MUST explicitly match the device's hardware sample rate to prevent the -10868 error (format mismatch)
- **FR-030**: The system MUST install a CoreAudio property listener (`AudioObjectPropertyListenerBlock`) on `kAudioDevicePropertyNominalSampleRate` of the active recording device to detect format changes (AirPods mode switching, Bluetooth profile switching). The listener MUST be removed when the recording stops or the device changes
- **FR-031**: When the user switches the audio device through the UI (the microphone menu or hotkey "1") during an active recording, the system MUST automatically restart the recording on the new device: reset the current recording (`resetRecording`), start a new recording on the selected device (`startRecording`). The timer is reset. The user sees the timer reset as the switch indicator
- **FR-015**: On rapid Bluetooth device connect/disconnect ("flapping") the system MUST apply debounce (1 second for `onDeviceLost`, 500ms for `onDefaultInputChanged`) and generate a single notification per flap series. Semantics: latest-wins — in a series of events the last value (last UID) is used. The debounce for `onDefaultInputChanged` is shorter because the user expects a fast reaction to a device switch
- **FR-016**: RecordingViewModel MUST update audioLevel and duration from timers through the thread-safe `updateLevelsFromAtomic()` method of AudioCaptureService (reading atomic values written from the audio thread), not via direct property access from the Timer callback
- **FR-017**: RecordingViewModel MUST NOT use nested `Task { @MainActor in }` inside Timer callbacks that are already executed on the main thread — the redundant context switch must be eliminated
- **FR-018**: All AudioCaptureService callbacks (onDeviceError, onAutoStop) MUST be invoked on the main thread or via @MainActor isolation so that the ViewModel can safely update UI properties
- **FR-019**: OnboardingViewModel MUST update audioLevel through a thread-safe mechanism without a nested DispatchQueue.main.async inside Task @MainActor
- **FR-020**: When the floating recording window or the onboarding window closes, all timers MUST be invalidated, the active recording stopped, resources released — without leaks and dangling callbacks
- **FR-021**: See FR-004 (merged)

### Logging requirements

*All requirements below use the existing DiagnosticLogger infrastructure from 007-diagnostic-logging: dual-sink (os.Logger + JSONL), categories, levels (OFF/ERROR/INFO/DEBUG), sessionId, FlowTracker breadcrumbs, SensitiveMasker.*

- **FR-022**: All recording operations (startRecording, stopRecording, resetRecording) MUST be logged at the INFO level with category `audio`: operation start (with device name and type — Bluetooth/built-in), operation completion (with duration and result — success/error), rejection of a duplicate call (ignore duplicate). On a successful start — INFO log "Recording on device" with the device name and sample rate. On fallback to the default device — INFO log "Recording on device (fallback to default)" with the names of the original and the default devices. At the DEBUG level — parameters: audio format, sample rate, buffer size
- **FR-023**: SPSC ring buffer statistics MUST be logged at the DEBUG level with category `tap` **only on drain on the main thread** (`updateLevelsFromAtomic()`): number of read buffers, cumulative number of written buffers, number of lost buffers (`_droppedBuffers`). An overflow event MUST be logged at the ERROR level on drain (not from the audio callback). From the real-time audio tap callback DiagnosticLogger calls are FORBIDDEN — only the increment of atomic counters (write count, dropped count) that are read on drain
- **FR-024**: All Bluetooth device events MUST be logged with category `bluetooth`: device connect/disconnect (INFO), debounce events with the source event and final state (DEBUG), audio profile switch (INFO), device initialization timeout (ERROR with context: device name, waiting time)
- **FR-025**: CoreAudio callbacks (property listeners) MUST be logged at the INFO level with category `engine`: event type, source thread (thread name/id), dispatch time to @MainActor (from receiving the callback to the start of processing). At the DEBUG level — full context: property address, device UID, scope
- **FR-026**: All errors in asynchronous operations MUST be logged at the ERROR level with full ErrorContext context (007-diagnostic-logging FR-010): error description, breadcrumb trail (last 20 actions via FlowTracker), current application state (AppState: active device, recording status, duration, current operation), method name and parameters, error code/type
- **FR-027**: The debounce mechanism (FR-015) MUST be logged at the DEBUG level with category `audio`: reception of the source event, cancellation of a pending event on a new event (latest-wins), debounce timer firing with the final value. Cancelling `onDeviceLost` on reconnect MUST be logged at the INFO level (important for "flapping" diagnostics)
- **FR-028**: Logging of asynchronous operations MUST NOT block the audio tap callback and MUST NOT violate the SC-006 performance constraint (< 10ms on hotkey press). For logging from the real-time audio callback the asynchronous DiagnosticLogger queue (serial DispatchQueue, qos: .utility) MUST be used

## Success criteria

### Measurable outcomes

- **SC-001**: The project compiles without Swift Concurrency warnings in all project files
- **SC-002** `[manual test]`: Recording via any Bluetooth device (AirPods, Jabra, Plantronics) up to 5 minutes long completes successfully — at least 10 consecutive recordings on each available Bluetooth device without a single failure
- **SC-003**: Switching the device during recording does not cause UI freezes or data loss
- **SC-004**: 100 cycles of rapid start/stop recording (interval <500ms) do not cause a crash or data corruption
- **SC-005**: A simultaneous Bluetooth device disconnect and recording stop do not result in a crash in 100% of cases
- **SC-006**: On Bluetooth device disconnect the user sees the error message within 2 seconds
- **SC-007**: All existing recording, transcription, and formatting functionality works without regressions after the fixes
- **SC-008** `[manual test]`: The floating recording window displays the timer and the audio level indicator smoothly (updates every 50-100ms) without dropped frames on any Bluetooth devices
- **SC-009**: The microphone test in onboarding correctly handles a device disconnect — the UI shows an error, the level indicator resets, without a crash
- **SC-010**: Rapidly opening/closing the floating recording window during an active recording does not cause timer leaks or dangling callbacks
- **SC-011**: At the INFO level a single recording (start→stop) generates at least 4 entries in the JSONL log: recording start, recording end, conversion result, at least one device event — all with correct `sessionId`, `timestamp`, `category`
- **SC-012**: On a Bluetooth device error during recording, the ERROR entry in the log contains the breadcrumb trail (up to 20 steps), the AppState snapshot, and is sufficient for diagnostics without access to the user's machine
- **SC-013**: Logging from the audio tap callback does not increase hotkey-press latency above 10ms (the 007-diagnostic-logging SC-006 constraint)

## Clarifications

### Session 2026-03-18

- Q: How does the system handle a Bluetooth device that is connected but does not transmit audio data? → A: Silence timeout (10 sec), auto-stop of the recording with the notification "Device is not transmitting audio"
- Q: What happens when the Bluetooth profile switches (A2DP → HFP) during recording? → A: Stop the recording with the error "Audio device changed format", the user restarts manually
- Q: How does the system handle Bluetooth device "flapping" (rapid connect/disconnect)? → A: Debounce (1 sec) at the monitoring level, a single "Device lost" notification per flap series
- Q: Which synchronization mechanism should be used for thread-safe access to recording state and audio buffers? → A: `@MainActor` isolation — AudioCaptureService is isolated via @MainActor, all mutations serialized on the main thread (custom Actor rejected due to incompatibility with @Observable, see research.md R-001)
- Q: What happens to already-recorded audio data when the device is switched during recording? → A: The data is discarded without confirmation and notification — the buffers are cleared, the timer is reset, the recording starts again on the new device
- Q: What is displayed in the UI while waiting for the Bluetooth device to be ready at recording start? → A: The record button shows a spinner with the text "Connecting to device…", the button is inactive
- Q: How does the system handle a repeated call of a recording operation while the previous one is still running? → A: startRecording/resetRecording — the repeated call is silently ignored (ignore duplicate). stopRecording — throws RecordingError.notRecording, because the caller expects Data
- Q: Is a confirmation or notification needed when switching the device during recording? → A: No — the data is silently discarded, the timer is reset, the recording starts again; the user sees the timer reset as the indicator
- Q: How to synchronize access to audio buffers from the real-time audio callback (installTap), where locks are forbidden? → A: A lock-free SPSC ring buffer for the audio callback → the main thread reads from the ring buffer via `updateLevelsFromAtomic()`
- Q: What happens when another operation (for example, start) is invoked during the execution of the current one (for example, stop)? → A: A queue — the new operation waits for the current one to finish via @MainActor serialization
- Q: What counts as a "zero buffer" for the silence timeout (FR-013)? → A: Literally all samples == 0 — an indicator of a non-working device, not a quiet room
- Q: What does the system do if the Bluetooth device is not ready after 5 seconds? → A: 5-sec timeout → error "Device is not responding", the record button returns to the initial state

### Session 2026-03-19

- Q: How to log SPSC ring buffer operations from the real-time audio tap callback without priority inversion? → A: From the real-time callback DiagnosticLogger calls are forbidden. Only the increment of atomic counters (write count, dropped count). Logging of aggregated statistics — on drain on the main thread (`updateLevelsFromAtomic()`)
- Q: Why does `inputNode.outputFormat(forBus: 0)` return the wrong sample rate? → A: After `setInputDevice` the input node may return a stale format (for example, 44100 Hz), while the actual hardware runs at 48000 Hz. Solution: an explicit `kAudioDevicePropertyNominalSampleRate` request via the CoreAudio API (FR-029)
- Q: What happens when the Bluetooth profile switches (A2DP → HFP) during recording? → A: Instead of stopping with an error — automatic recording restart: a CoreAudio listener on `kAudioDevicePropertyNominalSampleRate` detects the change, `handleDeviceFormatChange()` resets the buffers and recreates the engine with the new sample rate (FR-014 updated)
- Q: How should the device switch via the UI work during recording? → A: `switchAudioDevice(to:)` in RecordingViewModel calls `resetRecording()` + `startRecording()` with the new device. The timer is reset (FR-031)
- Q: How often to log ring buffer drains? → A: Every 50th drain cycle (instead of every ~100ms) — prevents log spam while preserving diagnostic value (FR-023 refined)

## Assumptions

- The application compiles with Swift 5.9+ (Xcode 15+)
- The warnings are preparation for Swift 6 strict concurrency — we fix them in advance
- Bluetooth devices require a full AVAudioEngine recreation for every recording (existing behavior R-010 is preserved)
- Timer callbacks in the ViewModels are invoked on the main thread
- macOS correctly enumerates connected Bluetooth devices through the CoreAudio API — the application does not bypass system restrictions
- Bluetooth device initialization latency does not exceed 5 seconds (typical value for SCO/HFP profiles)

## Dependencies

- AVFoundation (AVAudioEngine, AVCaptureDevice)
- CoreAudio (AudioObjectPropertyListenerBlock, AudioDeviceID)
- Swift Concurrency (async/await, @Sendable, actor isolation)
- 007-diagnostic-logging: DiagnosticLogger, FlowTracker, ErrorContext, LogCategory, SensitiveMasker — the existing logging infrastructure

## Scope and constraints

**In scope**:
- Fix all Swift Concurrency compiler warnings
- Eliminate all race conditions in audio capture and device management code
- Ensure thread safety when working with any Bluetooth devices
- Correct interaction with CFString in the CoreAudio API
- Serialize recording operations (start/stop/reset)
- Thread-safe handling of CoreAudio callbacks
- Fix concurrency issues in RecordingViewModel (the floating recording window): eliminate race conditions in timers, safe access to audioLevel, correct callback handling
- Fix concurrency issues in OnboardingViewModel (the onboarding window): safe microphone test, correct handling of onDeviceError from arbitrary threads
- Replace non-Sendable closures with @Sendable or async patterns in all ViewModels and services
- Diagnostic logging of all new asynchronous operations through the existing DiagnosticLogger infrastructure (007-diagnostic-logging): recording operations, SPSC ring buffer, Bluetooth events, CoreAudio callbacks, debounce mechanism, errors with full ErrorContext

**Out of scope**:
- Full migration to Swift 6 strict concurrency mode
- Adding new recording functionality
- Support for USB audio interfaces with non-standard drivers
- Bluetooth profile management (A2DP/HFP/SCO) at the application level
- Creating or modifying the logging infrastructure (DiagnosticLogger, JSONLFileWriter, LogFileManager, FlowTracker) — used as-is from 007-diagnostic-logging
- Adding new logging categories — existing categories from 007 are used
