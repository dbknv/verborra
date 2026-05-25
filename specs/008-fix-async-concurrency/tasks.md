# Tasks: Swift Concurrency and race condition fixes

**Input**: Project documents from `specs/008-fix-async-concurrency/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/protocols.md

**Tests**: Includes tests for SPSCRingBuffer (critical new component) and final build verification.

**Organization**: Tasks are grouped by user scenarios for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can be executed in parallel (different files, no dependencies)
- **[Story]**: Which user scenario the task belongs to (US1, US5, US6, US7)
- Exact file paths are stated in the descriptions

## Mapping plan.md → tasks.md

| Plan step | Task ID | Description |
|-----------|---------|-------------|
| 1 | T001 | swift-atomics |
| 2 | T002 | SPSCRingBuffer |
| 3 | T003 | Ring buffer tests |
| 4 | T004 | AudioCaptureServiceProtocol |
| 5 | T005 | AudioDeviceManagerProtocol |
| 6, 7 | T006 | @MainActor AudioCaptureService + replace NSLock/Array with ring buffer |
| 8 | T007 | Atomic properties (audioLevel, duration, isRecording, zeroBuffers) |
| 9 | T008 | nonisolated handleAudioBuffer |
| →9 | T009 | installRecordingTap (closure refactoring, extracted from step 9) |
| 10 | T010, T010a | startRecording guard + RecordingError.notRecording |
| 11 | T011 | stopRecording (ring buffer + accumulatedBuffers) |
| 12 | T012 | resetRecording |
| 13 | T013 | updateLevelsFromAtomic |
| 14 | T013a | Silent device detection |
| 15 | T013b | Device error detection |
| →15 | T014 | triggerAutoStop cleanup (extracted from step 15) |
| FR-009 | T015 | Bluetooth timeout (new task per FR-009) |
| 16 | T050 | @MainActor AudioDeviceManager |
| 17 | T016, T017 | CFString fix |
| 18 | T018 | Callback types |
| 19 | T018a, T018b | Debounce |
| 20 | T019 | @MainActor RecordingViewModel |
| 20a | T051 | Bluetooth UI state |
| 21 | T020 | durationTimer fix |
| 22 | T021 | levelTimer fix |
| 23 | T022 | inputDurationTimer fix |
| 24 | T023 | inputLevelTimer fix |
| 25 | T024, T024a | Callback subscriptions + device switch |
| 26 | T025 | Timer lifecycle |
| 27 | T026 | @MainActor OnboardingViewModel |
| 28 | T027 | DispatchQueue fix |
| 29 | T028 | onDeviceError callback |
| 30 | T029, T029a | Timer lifecycle onboarding + View cleanup |
| 31 | T030, T031 | Mocks |
| 32 | T032-T032g | Tests |
| 33 | T033 | Final build |
| FR-022 | T034 | Logging of recording operations |
| FR-023 | T035 | Logging of the SPSC ring buffer |
| FR-024 | T036 | Logging of Bluetooth events |
| FR-025 | T037 | Logging of CoreAudio callbacks |
| FR-026 | T038 | Logging of errors with ErrorContext |
| FR-027 | T039 | Logging of the debounce mechanism |
| FR-029 | T041 | Query the actual sample rate via the CoreAudio API |
| FR-030 | T042 | CoreAudio listener on the device's sample rate |
| FR-014 (upd) | T043 | Auto-restart of recording on format change |
| FR-031 | T044 | switchAudioDevice(to:) in RecordingViewModel |
| FR-031 | T045 | Update ControlBarView to call switchAudioDevice |
| FR-023 (upd) | T046 | Throttling of drain logs (every 50th cycle) |
| FR-022 (upd) | T047 | INFO log "Recording on device" with the device name |

## Path conventions

- **Source code**: `Verborra/` at the repository root
- **Tests**: `VerborraTests/` at the repository root
- **Dependencies**: `Package.swift` at the repository root

---

## Phase 1: Setup (Common infrastructure)

**Goal**: Add the swift-atomics dependency and create the lock-free ring buffer

- [X] T001 Add the `swift-atomics` dependency (apple/swift-atomics, from: "1.2.0") to Package.swift — add `.package(url:)` to dependencies and `"Atomics"` into the target dependencies for Verborra
- [X] T002 Create SPSCRingBuffer in Verborra/Services/SPSCRingBuffer.swift — generic lock-free SPSC ring buffer with `ManagedAtomic<Int>` for writeIndex/readIndex, methods `write(_:)`, `read()`, `readAll()`, `reset()`, `count`, `isEmpty`; mark as `@unchecked Sendable`; capacity = 256 for audio buffers. See research.md R-002 for the implementation. Register the file in Verborra.xcodeproj
- [X] T003 Create SPSCRingBuffer tests in VerborraTests/Services/SPSCRingBufferTests.swift — tests: write/read single element, write/readAll multiple, buffer full (write returns false), buffer empty (read returns nil), reset clears indices, sequential write-read cycle (256 elements), concurrent producer-consumer test using DispatchQueue. Register the file in Verborra.xcodeproj

**Checkpoint**: swift-atomics integrated, SPSCRingBuffer created and tested

---

## Phase 2: Foundation (Blocking prerequisites)

**Goal**: Update the protocols — all subsequent phases depend on these changes

**⚠️ CRITICAL**: Work on user scenarios cannot start until this phase is complete

- [X] T004 [P] Update AudioCaptureServiceProtocol in Verborra/Services/AudioCaptureService.swift — add `enum DeviceErrorReason: Sendable { case disconnected, formatChanged }` (in the same file or in Verborra/Models/). Change closure types: `onAutoStop: (@Sendable @MainActor () -> Void)?`, `onDeviceError: (@Sendable @MainActor (_ deviceName: String?, _ reason: DeviceErrorReason) -> Void)?`. Add `@MainActor` to the protocol. **⚠️ DO NOT add `updateLevelsFromAtomic()` at this step** — the protocol will temporarily be incomplete (no updateLevelsFromAtomic). The method is added to the protocol in T013 after the atomic properties it depends on are implemented. See contracts/protocols.md for the final version of the protocol
- [X] T005 [P] Update AudioDeviceManagerProtocol in Verborra/Services/Protocols.swift — change closure types: `onDeviceLost: (@Sendable @MainActor (_ uid: String, _ name: String) -> Void)?`, `onDefaultInputChanged: (@Sendable @MainActor (_ newUID: String?) -> Void)?`. Add `@MainActor` to the protocol. See contracts/protocols.md

**Checkpoint**: Protocols updated — the implementations need to be brought in line

---

## Phase 3: US-1 / US-3 — Thread-safe AudioCaptureService (Priority: P1) 🎯 MVP

**Goal**: Convert AudioCaptureService into @MainActor @Observable with a lock-free audio tap, eliminating all race conditions and NSLock warnings

**Independent test**: Connect a Bluetooth headset → start a recording → 30 sec → stop → WAV is valid. Rapidly press start/stop 10 times — no crash

### US-1 / US-3 implementation

- [X] T006 [US1] Add `@MainActor` to AudioCaptureService in Verborra/Services/AudioCaptureService.swift — ⚠️ *Combines plan steps 6+7 (high complexity — recommended to do in two passes: first @MainActor + init, then replace storage)*. Add the `@MainActor` annotation to the class declaration. Remove `private let lock = NSLock()`. Replace `private var audioBuffers: [AVAudioPCMBuffer] = []` with `private let ringBuffer = SPSCRingBuffer<AVAudioPCMBuffer>(capacity: 256)` and `private var accumulatedBuffers: [AVAudioPCMBuffer] = []` (accumulating array, filled from the ring buffer every 50-100ms in updateLevelsFromAtomic). Add `private weak var deviceManager: AudioDeviceManagerProtocol?` — injected via init to check device availability during device error detection (T013b). Update init to accept `deviceManager: AudioDeviceManagerProtocol`. Update the closure property types for `onAutoStop` and `onDeviceError` in accordance with the updated protocol (T004)
- [X] T007 [US1] Add atomic properties to AudioCaptureService in Verborra/Services/AudioCaptureService.swift — add `private nonisolated let _atomicAudioLevel = ManagedAtomic<UInt32>(0)`, `private nonisolated let _atomicDuration = ManagedAtomic<UInt64>(0)`, `private nonisolated let _isRecording = ManagedAtomic<Bool>(false)`, `private nonisolated let _consecutiveZeroBuffers = ManagedAtomic<Int>(0)`, `private nonisolated let _droppedBuffers = ManagedAtomic<Int>(0)` (ring buffer overflow diagnostics, FR-002). Add `import Atomics`. The properties are marked `nonisolated` for access from the audio thread
- [X] T008 [US1] Extract nonisolated handleAudioBuffer in AudioCaptureService in Verborra/Services/AudioCaptureService.swift — create `private nonisolated func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime)`. Move from the installTap closure: the `_isRecording.load(ordering: .acquiring)` check (instead of `engine?.isRunning`), RMS calculation of audioLevel, `_atomicAudioLevel.store(level.bitPattern, ordering: .relaxed)`, duration calculation, `_atomicDuration.store(duration.bitPattern, ordering: .relaxed)`, `ringBuffer.write(buffer)` — on `write() == false` (overflow) increment `private nonisolated let _droppedBuffers = ManagedAtomic<Int>(0)` for diagnostics (overflow is unlikely with drain every 50-100ms, but must be observable), counting zero buffers in `_consecutiveZeroBuffers` — a buffer is considered zero if all samples == 0: `buffer.floatChannelData![0]` is checked via `vDSP_maxmgv` (maximum absolute amplitude), a result of 0.0 means a fully empty buffer (a non-working device, not a quiet room — spec.md:197). On a non-zero buffer reset the counter to 0. Remove `DispatchQueue.main.async` for audioLevel and duration. Remove NSLock lock/unlock calls
- [X] T009 [US1] Update installRecordingTap in AudioCaptureService in Verborra/Services/AudioCaptureService.swift — replace the inline closure with a call `self.handleAudioBuffer(buffer, time: time)`. The closure must be `[weak self]` and `nonisolated`. Remove the `engine?.isRunning` check from the closure (moved to handleAudioBuffer). Remove the `DispatchQueue.main.async` block for device error detection — replace it with a check of the atomic flag
- [X] T010 [US1] Update startRecording in AudioCaptureService in Verborra/Services/AudioCaptureService.swift — add a guard check `guard !_isRecording.load(ordering: .acquiring) else { return }` at the beginning of the method to ignore duplicate calls (FR-010). Add `_isRecording.store(true, ordering: .releasing)` after a successful `engine.start()`. Add `ringBuffer.reset()` and `accumulatedBuffers.removeAll()` before the recording starts. Reset `_atomicAudioLevel.store(0, ordering: .relaxed)`, `_atomicDuration.store(0, ordering: .relaxed)`, `_consecutiveZeroBuffers.store(0, ordering: .relaxed)`. Keep maxDuration as a nonisolated property for access from the audio tap
- [X] T010a [US1] Add `RecordingError.notRecording` to Verborra/Models/RecordingState.swift — add the case `notRecording` to the existing `enum RecordingError` (line 15 of the file) and the corresponding `errorDescription` in the `LocalizedError` extension (localization key: `error.notRecording`). The file exists in the project. Used in T011 for the guard check on stopRecording without an active recording (FR-010)
- [X] T011 [US1] Update stopRecording in AudioCaptureService in Verborra/Services/AudioCaptureService.swift — **Depends on T010a**. Add a guard check `guard _isRecording.load(ordering: .acquiring) else { throw RecordingError.notRecording }` at the beginning of the method (FR-010). Set `_isRecording.store(false, ordering: .releasing)` before stopping the engine. Replace `lock.lock(); let buffers = audioBuffers; lock.unlock()` with `let remaining = ringBuffer.readAll(); let buffers = accumulatedBuffers + remaining` — combine the accumulated buffers with the remainder from the ring buffer. Clear `accumulatedBuffers`. The rest of the logic (removeTap, stop engine, nil engine, restoreVolume, convertToWAV) is unchanged
- [X] T012 [US1] Update resetRecording in AudioCaptureService in Verborra/Services/AudioCaptureService.swift — add a guard check `guard _isRecording.load(ordering: .acquiring) else { return }` — if recording is not active, silently return (nothing to reset). Note: resetRecording is a synchronous method (not async), so serialization with async methods (startRecording, stopRecording) works through @MainActor: a synchronous method cannot be called "inside" a suspension point of an async method on the same actor; the guard check protects against a call after the async operation has completed. If recording is active: set `_isRecording.store(false, ordering: .releasing)`, stop the engine, call `ringBuffer.reset()` and `accumulatedBuffers.removeAll()`. Reset atomic audioLevel and duration
- [X] T013 [US1] Add `updateLevelsFromAtomic()` method to AudioCaptureService in Verborra/Services/AudioCaptureService.swift — **Depends on T004 (protocol)**. Create `func updateLevelsFromAtomic()`: (1) reads `_atomicAudioLevel.load(ordering: .relaxed)` → updates `audioLevel = Float(bitPattern: bits)`, similarly for duration; (2) **drains the ring buffer**: reads all available buffers from `ringBuffer.readAll()` and appends them to `private var accumulatedBuffers: [AVAudioPCMBuffer] = []`. This ensures periodic ring buffer drainage (every 50-100ms) and prevents data loss on long recordings (FR-002). **Update AudioCaptureServiceProtocol**: add `func updateLevelsFromAtomic()` to the protocol (T004 does not add this method explicitly — it is added here after the atomic properties are implemented)
- [X] T013a [US1] Add silent device detection to `updateLevelsFromAtomic()` in Verborra/Services/AudioCaptureService.swift — add a `_consecutiveZeroBuffers` check: if silence > 10 sec → call `triggerAutoStop()`. Calculate the threshold dynamically: `silenceThreshold = Int(sampleRate * 10 / Double(bufferSize))` — each call to handleAudioBuffer processes one buffer with a duration of `bufferSize/sampleRate` seconds, so over 10 seconds there will be `sampleRate * 10 / bufferSize` calls. Correct for any sampleRate (8kHz, 16kHz, 44.1kHz, 48kHz) (FR-013)
- [X] T013b [US1] Add device error detection to `updateLevelsFromAtomic()` in Verborra/Services/AudioCaptureService.swift — **Depends on T006 (deviceManager injection) and T005 (@MainActor protocol)**. Note: access to `deviceManager?.devices` is type-safe since AudioDeviceManagerProtocol is already @MainActor after T005 (Phase 2); the T050 implementation (Phase 4) does not block this task. Add the check: if `_isRecording == true` but `engine?.isRunning == false` → determine the cause: check via `self.deviceManager?.devices` whether the current device is in the list. If the device is missing → `onDeviceError(deviceName, .disconnected)` (FR-012: "Device lost"). If the device is still in the list → `onDeviceError(deviceName, .formatChanged)` (FR-014: "Audio device changed format"). A check every 50ms via Timer ensures notification within 2 sec (FR-012)
- [X] T014 [US1] Update triggerAutoStop and device error detection in AudioCaptureService in Verborra/Services/AudioCaptureService.swift — **Depends on T013b**. `triggerAutoStop()` is an existing internal method that stops the engine and invokes the `onAutoStop` callback. Remove the `DispatchQueue.main.async` wrapper (the method is already on @MainActor). Remove device error detection from the audio tap callback (moved to updateLevelsFromAtomic T013b). Update all `onDeviceError` calls to pass `DeviceErrorReason` (`.disconnected` or `.formatChanged`). Covers FR-012 and FR-014

- [X] T015 [US1] Implement Bluetooth device wait timeout in startRecording in Verborra/Services/AudioCaptureService.swift — after `engine.start()` verify that the device has begun transmitting data (the first non-nil buffer in the ring buffer). If there are no buffers within 5 seconds — throw an error "Device is not responding". Implement via polling: `for _ in 0..<50 { try await Task.sleep(nanoseconds: 100_000_000); if !ringBuffer.isEmpty { break } }` (a check every 100ms, 50 iterations = 5 sec). async on @MainActor yields correctly — the UI is not blocked. startRecording throws an error — the ViewModel handles it and returns the UI to the initial state. Matches FR-009

- [X] T041 [US1] Add `deviceNominalSampleRate(for:)` to AudioCaptureService in Verborra/Services/AudioCaptureService.swift — **Depends on T006**. Create `private static func deviceNominalSampleRate(for deviceID: AudioDeviceID) -> Double?`: request `kAudioDevicePropertyNominalSampleRate` via `AudioObjectGetPropertyData`. Use it in `prepareAndStartEngine` instead of `inputNode.outputFormat(forBus: 0).sampleRate` to determine the actual hardware sample rate. Create an explicit `AVAudioFormat` with this sample rate and pass it to `installRecordingTap(on:format:)`. Matches FR-029, decision R-011

- [X] T042 [US1] Add a CoreAudio listener on the device's sample rate to AudioCaptureService in Verborra/Services/AudioCaptureService.swift — **Depends on T041**. Create `installDeviceFormatListener(deviceID:)`: installs an `AudioObjectPropertyListenerBlock` on `kAudioDevicePropertyNominalSampleRate` via `AudioObjectAddPropertyListenerBlock`. The callback invokes `handleDeviceFormatChange()` via `DispatchQueue.main.async`. Create `removeDeviceFormatListener()`: removes the listener via `AudioObjectRemovePropertyListenerBlock`. Store `activeListenerDeviceID: AudioDeviceID?` and `formatListenerBlock: AudioObjectPropertyListenerBlock?`. Call `installDeviceFormatListener` after a successful `engine.start()`, and `removeDeviceFormatListener` in stop/reset/handleDeviceFormatChange. Matches FR-030, decision R-012

- [X] T043 [US1] Implement recording auto-restart on format change in AudioCaptureService in Verborra/Services/AudioCaptureService.swift — **Depends on T042**. Create `handleDeviceFormatChange()`: (1) check `_isRecording` — if not recording, exit; (2) remove the format listener; (3) stop the engine + removeTap; (4) reset all buffers (ringBuffer.reset, accumulatedBuffers.removeAll, all atomic counters); (5) recreate the engine (`engine = AVAudioEngine()`); (6) call `prepareAndStartEngine(deviceID:)` with the current deviceID; (7) on restart error — `_isRecording = false`, `onDeviceError(.formatChanged)`. Matches FR-014 (updated), decision R-013

- [X] T046 [US8] Add drain log throttling to updateLevelsFromAtomic in Verborra/Services/AudioCaptureService.swift — **Depends on T035**. Add `private var drainLogCounter: Int = 0` and `private static let drainLogInterval: Int = 50`. In `updateLevelsFromAtomic()` log the drain only when `drainLogCounter == 1` (first) or `drainLogCounter % drainLogInterval == 0`. Reset the counter on startRecording and handleDeviceFormatChange. Matches FR-023 (throttling), decision R-015

- [X] T047 [US8] Add INFO log "Recording on device" to prepareAndStartEngine in Verborra/Services/AudioCaptureService.swift — **Depends on T034**. On a successful `engine.start()`: `logAudio.info("Recording on device", metadata: ["deviceName": resolvedName, "sampleRate": ...])`. On fallback to the default device (retry): `logAudio.info("Recording on device (fallback to default)", metadata: ["deviceName": defaultName, "originalDevice": resolvedName, "sampleRate": ...])`. Matches FR-022 (updated)

**Checkpoint**: AudioCaptureService is thread-safe — recording via Bluetooth works without race conditions, the format always matches the hardware

---

## Phase 4: US-5 — Thread-safe AudioDeviceManager (Priority: P2)

**Goal**: Fix the CFString warning and update callback types in AudioDeviceManager

**Independent test**: Rapidly connect/disconnect several Bluetooth devices — the list updates, the UI does not freeze

### US-5 implementation

- [X] T050 [US5] Add `@MainActor` to AudioDeviceManager in Verborra/Services/AudioDeviceManager.swift — add the `@MainActor` annotation to the class declaration (similar to T006 for AudioCaptureService). Mark CoreAudio listener callbacks (`addDeviceListListener`, `addDefaultInputListener`) as `nonisolated` — they are invoked on `listenerQueue` and forward to the main thread via `DispatchQueue.main.async`. Required for conformance with the @MainActor AudioDeviceManagerProtocol (T005)
- [X] T016 [P] [US5] Fix CFString UnsafeMutableRawPointer in getDeviceUID in Verborra/Services/AudioDeviceManager.swift — replace `var uid: CFString = "" as CFString; var size = UInt32(MemoryLayout<CFString>.size)` with `var name: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)`. Use `name?.takeRetainedValue()` to obtain the String. Add a `status != noErr` check after `AudioObjectGetPropertyData` and return `nil` on error (protection against a race condition when the device is disconnected between UID and name requests — edge case spec.md:131). See research.md R-004
- [X] T017 [P] [US5] Fix CFString UnsafeMutableRawPointer in getDeviceName in Verborra/Services/AudioDeviceManager.swift — a similar fix as in T016 for the getDeviceName function: `var name: Unmanaged<CFString>?` instead of `var name: CFString = "" as CFString`. Add a `status != noErr` check and a graceful return nil (edge case spec.md:131)
- [X] T018 [US5] Update callback types in AudioDeviceManager in Verborra/Services/AudioDeviceManager.swift — change the types of the `onDeviceLost` and `onDefaultInputChanged` properties to `@Sendable @MainActor` according to the updated protocol. Verify that all callback invocations already happen on the main thread via `DispatchQueue.main.async`
- [X] T018a [US5] Implement debounce for Bluetooth "flapping" in Verborra/Services/AudioDeviceManager.swift — on rapid Bluetooth device connect/disconnect (several events within 1 second) generate a single `onDeviceLost` notification per flap series. Implement via `DispatchWorkItem` with a 1-sec delay: on a disconnect event cancel the previous pending work item and create a new one. Store the pending work item and UID in `private var pendingDeviceLostWork: DispatchWorkItem?` and `private var pendingDeviceLostUID: String?`. **Reconnect cancellation**: when a device connect event is received in `addDeviceListListener` — check `pendingDeviceLostUID`: if it matches the UID of the connected device, call `pendingDeviceLostWork?.cancel(); pendingDeviceLostWork = nil; pendingDeviceLostUID = nil` (edge case spec.md:133: "If the device reconnects within the debounce window, the pending notification MUST be cancelled"). In `stopMonitoring()` add `pendingDeviceLostWork?.cancel(); pendingDeviceLostWork = nil`. Matches FR-015, edge case spec.md:133
- [X] T018b [US5] Implement debounce for `onDefaultInputChanged` in Verborra/Services/AudioDeviceManager.swift — when Bluetooth profiles switch (A2DP → HFP), CoreAudio can generate a series of default input change events. Apply a similar debounce (500ms) via `DispatchWorkItem`: cancel the previous pending work item, create a new one with a delay. Store it in `private var pendingDefaultInputWork: DispatchWorkItem?`. In `stopMonitoring()` add `pendingDefaultInputWork?.cancel(); pendingDefaultInputWork = nil`. Shorter than onDeviceLost (500ms vs 1s) because the user expects a fast reaction to a device switch

**Checkpoint**: AudioDeviceManager compiles without CFString and non-Sendable warnings, debounce for Bluetooth flapping works

---

## Phase 5: US-6 — Thread-safe floating recording window (Priority: P1)

**Goal**: Fix concurrency issues in RecordingViewModel — remove redundant Task wrapping, safe access to audioLevel

**Independent test**: Recording via the floating window → timer and level indicator smooth → fast start/stop/start without freezes

### US-6 implementation

- [X] T019 [US6] Add `@MainActor` to RecordingViewModel in Verborra/ViewModels/RecordingViewModel.swift — add the `@MainActor` annotation to the class declaration
- [X] T051 [US1 → US6] *(cross-scenario: US-1 AC4 logic, placed in Phase 5 due to dependency on RecordingViewModel)* Add a Bluetooth-device waiting UI state in RecordingViewModel and OverlayContentView — **Depends on T019 (@MainActor) and T015 (Bluetooth timeout, Phase 3)**. (1) In Verborra/ViewModels/RecordingViewModel.swift: add a `.connecting` state to the RecordingState enum (or an equivalent mechanism). When startRecording is called, set `.connecting`; on receiving the "Device is not responding" error (from T015) return to the initial state and show an error. (2) In Verborra/Views/OverlayContentView.swift: add handling for the `.connecting` state — show a ProgressView (spinner) with the text "Connecting to device…" and disable the record button. Matches US-1 AC4
- [X] T020 [US6] Remove Task { @MainActor in } from the durationTimer callback in Verborra/ViewModels/RecordingViewModel.swift — in the startTimers function: remove the `Task { @MainActor in }` wrapper from the Timer.scheduledTimer callback for durationTimer. The code is already on the main thread — leave the logic directly in the closure: `let duration = Date().timeIntervalSince(start); let remaining = max(0, maxSeconds - duration); self.state = .recording(...)`. See research.md R-006
- [X] T021 [US6] Remove Task { @MainActor in } from the levelTimer callback in Verborra/ViewModels/RecordingViewModel.swift — in the startTimers function: remove the `Task { @MainActor in }` wrapper from the levelTimer callback. Replace direct reading of `self.audioCaptureService.audioLevel` with a call to `self.audioCaptureService.updateLevelsFromAtomic()`, then `self.audioLevel = self.audioCaptureService.audioLevel`
- [X] T022 [US6] Remove Task { @MainActor in } from the inputDurationTimer callback in Verborra/ViewModels/RecordingViewModel.swift — in the startInputTimers function: remove the `Task { @MainActor in }` wrapper, leave the logic directly in the closure
- [X] T023 [US6] Remove Task { @MainActor in } from the inputLevelTimer callback in Verborra/ViewModels/RecordingViewModel.swift — in the startInputTimers function: remove the `Task { @MainActor in }` wrapper, call `updateLevelsFromAtomic()` and read audioLevel directly
- [X] T024 [US6] Update callback subscriptions in RecordingViewModel in Verborra/ViewModels/RecordingViewModel.swift — update the closures for onAutoStop, onDeviceError, onDeviceLost, onDefaultInputChanged in init: bring the types to `@Sendable @MainActor`. onDeviceError now accepts `(_ deviceName: String?, _ reason: DeviceErrorReason)` — use `reason` to show the appropriate message to the user (`.disconnected` → "Device lost", `.formatChanged` → "Audio device changed format"). For stored closures use `[weak self]` — required to prevent a retain cycle
- [X] T024a [US4] Handle device switching during recording in RecordingViewModel in Verborra/ViewModels/RecordingViewModel.swift — **Depends on T015 (Bluetooth timeout)**. In the `onDefaultInputChanged` callback / when the user selects a new device: if recording is in progress, call `resetRecording()` (data is discarded without confirmation), reset the timer, start `startRecording()` on the new device (when it is a Bluetooth device, the timeout logic from T015 is used). Matches US-4 AC1-AC3, spec.md:72-74

- [X] T044 [US4] Add `switchAudioDevice(to:)` to RecordingViewModel in Verborra/ViewModels/RecordingViewModel.swift — **Depends on T024a**. Create `func switchAudioDevice(to deviceID: String)`: (1) guard `deviceID != selectedAudioDeviceID`; (2) update `selectedAudioDeviceID`; (3) if recording is active (`.recording` state): call `audioCaptureService.resetRecording()`, start `audioCaptureService.startRecording(deviceID:maxDuration:)`, reset `recordingStart` and state. Update `cycleMicrophone()` to call `switchAudioDevice(to:)` instead of a direct assignment. Matches FR-031, decision R-014

- [X] T045 [US4] Update ControlBarView to call switchAudioDevice in Verborra/Views/ControlBarView.swift — **Depends on T044**. In the microphone menu (preProcessingButtons) replace `viewModel.selectedAudioDeviceID = device.id` with `viewModel.switchAudioDevice(to: device.id)`. Ensures the actual device switch when selected in the UI. Matches FR-031
- [X] T025 [US6] Add Timer lifecycle management to RecordingViewModel in Verborra/ViewModels/RecordingViewModel.swift and Verborra/Views/OverlayContentView.swift — add a `func cleanup()` method to RecordingViewModel that calls stopTimers(), stopInputTimers(), resetRecording(). In OverlayContentView.swift add `viewModel.cleanup()` inside the existing `.onDisappear` block (line ~97). For Swift 5.9 do not rely on deinit for Timer invalidation

**Checkpoint**: The floating recording window works without race conditions — the timer and sound level update smoothly

---

## Phase 6: US-7 — Thread-safe microphone test in onboarding (Priority: P1)

**Goal**: Fix concurrency issues in OnboardingViewModel — remove the triple dispatch nesting

**Independent test**: Onboarding → microphone test → disconnect Bluetooth → error is displayed → UI does not freeze

### US-7 implementation

- [X] T026 [US7] Add `@MainActor` to OnboardingViewModel in Verborra/ViewModels/OnboardingViewModel.swift — add the `@MainActor` annotation to the class declaration
- [X] T027 [US7] Remove DispatchQueue.main.async from the levelTimer callback in Verborra/ViewModels/OnboardingViewModel.swift — in the startMicTest function: remove the `DispatchQueue.main.async { }` wrapper from the Timer callback. Replace with a direct call: `self.audioCaptureService.updateLevelsFromAtomic(); self.audioLevel = self.audioCaptureService.audioLevel`. The Timer is already on the main thread, no additional dispatch is needed
- [X] T028 [US7] Update onDeviceError callback in OnboardingViewModel in Verborra/ViewModels/OnboardingViewModel.swift — update the closure for onDeviceError in init: bring the type to `@Sendable @MainActor (_ deviceName: String?, _ reason: DeviceErrorReason)`. The callback is guaranteed to be invoked on MainActor (ensured by AudioCaptureService). Remove duplicate dispatch. Use `reason` for the error message in `micTestError`
- [X] T029 [US7] Add Timer lifecycle management to OnboardingViewModel in Verborra/ViewModels/OnboardingViewModel.swift — add a `func cleanup()` method (similar to RecordingViewModel T025) that calls `stopMicTest()` and guarantees that the timer and recording are stopped when the onboarding window closes. `cleanup()` is the single entry point for releasing resources
- [X] T029a [US7] Add a cleanup call to OnboardingView when the window closes — in Verborra/Views/OnboardingView.swift (or in an analogous View containing OnboardingViewModel): add `viewModel.cleanup()` or `viewModel.stopMicTest()` to the `.onDisappear` block. Similar to T025 for OverlayContentView. Ensures FR-020 (releasing resources when the onboarding window closes, edge case spec.md:138)

**Checkpoint**: The microphone test in onboarding is thread-safe — device disconnect is handled correctly

---

## Phase 7: US-8 — Diagnostic logging of asynchronous operations (Priority: P2)

**Goal**: Cover all new asynchronous code paths with logging through the existing DiagnosticLogger infrastructure (007-diagnostic-logging). The developer should be able to reconstruct the full timeline of a concurrency incident from the JSONL log.

**Independent test**: Perform a recording with a Bluetooth device switch → open the JSONL log → all events are recorded with categories, timestamps and sessionId (SC-011, SC-012)

**⚠️ CRITICAL**: From the real-time audio tap callback DiagnosticLogger calls are FORBIDDEN — only atomic counters. Logging of aggregated ring buffer statistics happens on drain on the main thread (FR-023, FR-028).

### US-8 implementation

- [ ] T034 [US8] Add logging of recording operations to AudioCaptureService in Verborra/Services/AudioCaptureService.swift — **Depends on T006-T015 (Phase 3)**. Using `DiagnosticLogger.logger(for: .audio)`: (1) `startRecording` INFO: device name, type (Bluetooth/built-in), parameters (sample rate, buffer size at the DEBUG level); (2) `stopRecording` INFO: duration, result (success/error); (3) `resetRecording` INFO: reset reason; (4) ignored duplicate call (guard return) INFO: "Duplicate startRecording ignored" / "Reset ignored — not recording". All entries with a single `sessionId` via FlowTracker. Matches FR-022, SC-011
- [ ] T035 [US8] Add logging of SPSC ring buffer statistics to updateLevelsFromAtomic in Verborra/Services/AudioCaptureService.swift — **Depends on T013 (updateLevelsFromAtomic)**. Using `DiagnosticLogger.logger(for: .tap)`: (1) on each drain at the DEBUG level: number of buffers read from `ringBuffer.readAll()`, cumulative `_droppedBuffers.load()`, total `accumulatedBuffers.count`; (2) when `_droppedBuffers > 0` at the ERROR level: "Ring buffer overflow: N buffers dropped" (check on drain, not from the audio callback). From the audio tap callback — NO DiagnosticLogger calls (FR-023, FR-028). Matches FR-023, SC-013
- [ ] T036 [P] [US8] Add logging of Bluetooth events to AudioDeviceManager in Verborra/Services/AudioDeviceManager.swift — **Depends on T050, T018a, T018b (Phase 4)**. Using `DiagnosticLogger.logger(for: .bluetooth)`: (1) device connect/disconnect INFO: name, UID, type; (2) debounce events DEBUG: source event, pending cancellation, final firing with UID (latest-wins); (3) cancellation of onDeviceLost on reconnect INFO: "Device reconnected within debounce window, cancelling pending lost notification for {UID}"; (4) device initialization timeout ERROR: device name, waiting time. Matches FR-024, FR-027
- [ ] T037 [P] [US8] Add logging of CoreAudio callbacks to AudioDeviceManager in Verborra/Services/AudioDeviceManager.swift — Using `DiagnosticLogger.logger(for: .engine)`: (1) property listener callback INFO: event type (devices changed / default input changed), time of dispatch to @MainActor (measure `CFAbsoluteTimeGetCurrent()` before `DispatchQueue.main.async` and after the start of processing); (2) at the DEBUG level: property address, device UID, scope. Matches FR-025
- [ ] T038 [US8] Add ErrorContext logging for all errors in Verborra/Services/AudioCaptureService.swift and Verborra/ViewModels/RecordingViewModel.swift — Using `DiagnosticLogger.error(context:)`: (1) in AudioCaptureService: startRecording error (device unavailable, timeout), device error (disconnect, format changed) — with breadcrumb trail via FlowTracker (last 20 actions), AppState snapshot (device, recording status, duration); (2) in RecordingViewModel: error during transcription/formatting — with the context of the current state. Matches FR-026, SC-012
- [ ] T039 [US8] Add logging of the debounce mechanism to AudioDeviceManager in Verborra/Services/AudioDeviceManager.swift — **May be merged with T036** if debounce logging is already added. A separate task in case T036 does not fully cover FR-027. Using `DiagnosticLogger.logger(for: .audio)`: (1) reception of the original `onDefaultInputChanged` event DEBUG; (2) cancelling a pending event on a new event DEBUG: "Debounce: cancelled pending default input change, new UID: {UID}"; (3) debounce timer firing INFO: "Default input changed: {oldUID} → {newUID}" with delay. Matches FR-027
- [ ] T040 [US8] Add FlowTracker breadcrumbs at key points of the recording flow — In AudioCaptureService: add `FlowTracker.shared.addBreadcrumb()` for: startRecording (with deviceName), stopRecording, resetRecording, device error detected, auto stop triggered, updateLevelsFromAtomic drain (only on non-zero drain count). In RecordingViewModel: handleRecordingKey, device switch, timer start/stop. Breadcrumbs are used in ErrorContext to reconstruct the timeline (FR-026). Matches SC-012

**Checkpoint**: All asynchronous operations are covered by logging. The JSONL log contains the full timeline with sessionId and breadcrumbs

---

## Phase 8: Finalization and verification

**Goal**: Update mocks, tests, ensure there are no warnings

- [X] T030 [P] Update MockAudioCaptureService in VerborraTests/Mocks/MockAudioCaptureService.swift — update the closure property types `onAutoStop` to `(@Sendable @MainActor ...)` and `onDeviceError` to `(@Sendable @MainActor (_ deviceName: String?, _ reason: DeviceErrorReason) -> Void)?` according to the updated protocol. Add `@MainActor` to the mock class. Add the `updateLevelsFromAtomic()` method (empty implementation for the mock)
- [X] T031 [P] Update MockAudioDeviceManager in VerborraTests/Mocks/ — update the closure property types `onDeviceLost` and `onDefaultInputChanged` to `(@Sendable @MainActor ...)`. Add `@MainActor` to the mock class
- [X] T032 Update existing tests in VerborraTests/ — adapt tests for @MainActor isolation: wrap test methods in `@MainActor` where required for access to @MainActor-isolated properties. Files to update: VerborraTests/Services/AudioCaptureServiceTests.swift, VerborraTests/Mocks/MockAudioCaptureService.swift (already updated in T030). Add lifecycle tests: (1) call `cleanup()` on RecordingViewModel during an active recording → verify that `isRecording == false`, timers are stopped, resources are released (edge case spec.md:136); (2) call `stopMicTest()` on OnboardingViewModel during a microphone test → verify that the timer is invalidated, audioLevel == 0 (edge case spec.md:138). Ensure all tests pass
- [X] T032a Add a rapid start/stop stress test in VerborraTests/ — tests: (1) 100 cycles of startRecording/stopRecording with interval <500ms — no crash, data corruption or resource leak (SC-004); (2) stopRecording() less than 100ms after startRecording() (before buffers fill) — must return empty data or throw an error, without a crash (edge case spec.md:129); (3) two timers call stopRecording simultaneously — the second one receives RecordingError.notRecording, @MainActor serialization handles it correctly (edge case spec.md:137); (4) several consecutive resetRecording() calls — @MainActor serialization guarantees no race condition, repeated calls are silently ignored (edge case spec.md:130); (5) 50 start/stop cycles with interval <300ms — covers US-6 AC4 (rapid presses in the floating window), timers are correctly created and destroyed without leaks or duplicate firing; (6) 50 cycles of RecordingViewModel creation → startRecording → cleanup() → deallocation (simulating rapid opening/closing of the floating window) — verify the absence of timer leaks and dangling callbacks (SC-010)
- [X] T032b Add an onDeviceError-during-stopRecording test in VerborraTests/ — tests: (1) invoke onDeviceError concurrently with processing the stopRecording result — the operations do not conflict, @MainActor serialization works (edge case spec.md:139); (2) stress test of 50 iterations: invoke stopRecording and onDeviceError in arbitrary order — 100% reliability without crash (SC-005); (3) notification latency test: mock engine.isRunning = false → invoke updateLevelsFromAtomic() → verify that onDeviceError is invoked within one Timer cycle (≤500ms), matches SC-006 (notification within 2 seconds); (4) test of distinguishing error reasons (FR-012 vs FR-014): mock engine.isRunning = false + device missing from devices → verify `reason == .disconnected`; mock engine.isRunning = false + device still in devices → verify `reason == .formatChanged` (edge case spec.md:132)
- [X] T032b2 [US7] Add an SC-009 test for OnboardingViewModel in VerborraTests/ — tests: (1) invoke `onDeviceError(deviceName, .disconnected)` during an active microphone test → verify that `audioLevel == 0`, `micTestError != nil`, the timer is stopped (SC-009); (2) invoke `onDeviceError(deviceName, .formatChanged)` during an active test → verify that `micTestError` contains a message about a format change; (3) start a microphone test → call `cleanup()`/`stopMicTest()` → verify that the timer is invalidated, resources are released (edge case spec.md:138)
- [X] T032c Add a smoke regression test in VerborraTests/ — test: recording → stop → verify that the WAV data is valid (non-empty, valid WAV header). Matches SC-007
- [X] T032d Add a simultaneous device events test in VerborraTests/ — test: invoke `onDeviceLost` and `onDefaultInputChanged` sequentially on @MainActor — both are processed without conflict, state is consistent. Note: @MainActor serialization turns "simultaneous" CoreAudio events into sequential ones — that is exactly what is being tested. Matches edge case spec.md:134
- [X] T032e Add a device switch during recording test in VerborraTests/ — tests: (1) start a recording → invoke `onDefaultInputChanged` → verify that reset+restart happened, the timer reset, a new recording started (SC-003, US-4); (2) start a recording → switch to a mock Bluetooth device with initialization latency (mock startRecording with Task.sleep 3 sec) → verify that the UI shows the connecting state, and after completion — a new recording is active (US-4 AC3, FR-009); (3) start a recording → switch to an unavailable device (mock startRecording throws microphoneNotAvailable) → verify that the UI shows an error, the record button returns to the initial state (edge case spec.md:140)
- [X] T032f [US5] Add Bluetooth flapping debounce tests in VerborraTests/ — tests: (1) invoke `onDeviceLost` 5 times in 500ms → verify that the callback fired once after 1 sec with the last UID (FR-015, latest-wins); (2) invoke `onDefaultInputChanged` 3 times in 300ms → verify that the callback fired once after 500ms with the last newUID (FR-015); (3) invoke `onDeviceLost` → wait 1.5 sec → invoke `onDeviceLost` → verify that the callback fired 2 times (debounce does not coalesce well-separated events); (4) invoke `onDeviceLost` → after 800ms cancel it (reconnect) → verify that the callback did not fire (cancel pending work item)
- [ ] T032g Perform manual Bluetooth recording testing (SC-002, SC-008) — checklist: (1) SC-002: connect a Bluetooth headset (AirPods / Jabra / Plantronics), perform at least 10 consecutive recordings of up to 5 minutes on each available device — all complete successfully without failures; (2) SC-008: during recording via the floating window verify the smoothness of timer and audio level indicator updates (every 50-100ms) — no visible dropped frames on any Bluetooth devices. Record the results in verification/report.md
- [ ] T033 Perform the final build and verify the absence of warnings — run `xcodebuild build` with clean build, verify the absence of: `Instance method 'lock' is unavailable from asynchronous contexts`, `Forming 'UnsafeMutableRawPointer' to a variable of type 'CFString'`, `Capture of 'self' with non-Sendable type`, any other concurrency warnings. Run SwiftLint and address violations in the modified files (constitution, principle 5). Matches US-2 (SC-001)

**Checkpoint**: The project compiles without concurrency warnings, all tests pass

---

## Dependencies and execution order

### Dependencies between phases

- **Phase 1 (Setup)**: No dependencies — can be started immediately
- **Phase 2 (Foundation)**: Depends on Phase 1 — BLOCKS all user scenarios
- **Phase 3 (US-1/US-3)**: Depends on Phase 2 — the core of all changes
- **Phase 4 (US-5)**: Depends on Phase 2 — can run in parallel with Phase 3
- **Phase 5 (US-6)**: Depends on Phase 3 (updateLevelsFromAtomic is needed)
- **Phase 6 (US-7)**: Depends on Phase 3 — can run in parallel with Phase 5
- **Phase 7 (US-8)**: Depends on Phase 3 (AudioCaptureService) and Phase 4 (AudioDeviceManager). Can run in parallel with Phases 5-6
- **Phase 8 (Finalization)**: Depends on the completion of all previous phases

### Dependencies between user scenarios

- **US-1/US-3 (AudioCaptureService)**: The foundation — all other scenarios depend on these changes
- **US-5 (AudioDeviceManager)**: Independent of US-1 at the code level, but logically related
- **US-6 (RecordingViewModel)**: Depends on US-1 (updateLevelsFromAtomic from AudioCaptureService is required)
- **US-7 (OnboardingViewModel)**: Depends on US-1 (updateLevelsFromAtomic from AudioCaptureService is required)
- **US-4 (Device switching)**: T024a in RecordingViewModel — reset + restart on device switch. Depends on US-1 (AudioCaptureService) + US-5 (callbacks)
- **US-8 (Logging)**: Depends on US-1/US-3 (AudioCaptureService) + US-5 (AudioDeviceManager). Parallel with US-6/US-7
- **US-2 (No warnings)**: Cross-cutting — verified in T033 after all tasks are completed

### Within each scenario

- Protocols before implementation
- Atomic properties before nonisolated functions
- Services before ViewModels
- Implementation before tests

### Parallel opportunities

- T004 and T005 (protocols) can run in parallel
- T016 and T017 (CFString fix) can run in parallel
- Phase 4 (US-5) and Phase 3 (US-1) can run in parallel after Phase 2
- Phase 5 (US-6) and Phase 6 (US-7) can run in parallel after Phase 3
- Phase 7 (US-8) can run in parallel with Phases 5-6 (after Phases 3-4)
- T036 and T037 (AudioDeviceManager logging) can run in parallel
- T030 and T031 (mocks) can run in parallel

---

## Parallel example: Phase 3 (US-1/US-3)

```bash
# Sequentially (dependencies within a single file):
T006 → T007 → T008 → T009 → T010 → T011 → T012 → T013 → T014 → T015
T015 → T041 → T042 → T043 (format monitoring chain)
T035 → T046 (drain throttle), T034 → T047 (device name logging)

# Phase 4 may run in parallel:
T050 → T016 + T017 (in parallel, different functions)
T018 → T018a + T018b (after T016/T017)

# Phase 5: T051 depends on T019 + T015, T044 depends on T024a
T019 → T051 → T020...
T024a → T044 → T045
```

---

## Implementation strategy

### MVP (Phases 1-3)

1. Phase 1: Setup (swift-atomics + SPSCRingBuffer)
2. Phase 2: Protocols (blocking prerequisite)
3. Phase 3: AudioCaptureService (US-1/US-3)
4. **STOP AND CHECK**: Recording via Bluetooth works, rapid start/stop without crash

### Incremental delivery

1. Setup + Foundation → Infrastructure ready
2. US-1/US-3 (AudioCaptureService) → The core is thread-safe (MVP!)
3. US-5 (AudioDeviceManager) → CFString fix + safe callbacks
4. US-6 (RecordingViewModel) → Floating window without race conditions
5. US-7 (OnboardingViewModel) → Onboarding without race conditions
6. US-8 (Logging) → All async paths covered by DiagnosticLogger
7. Finalization → Mocks, tests, clean build without warnings

---

## Notes

- [P] = different files, no dependencies
- [Story] = link to a user scenario
- US-2 (no warnings) does not have a separate phase — it is verified in T033
- US-4 (device switching) is covered by task T024a in Phase 5
- US-8 (logging) — a separate Phase 7, depends on Phases 3-4
- All new files MUST be registered in Verborra.xcodeproj (constitution, principle 5)
- FR-001 adjusted: @MainActor instead of Actor (see research.md R-001)
- Commit after each task or logical group
