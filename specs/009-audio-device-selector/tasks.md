# Tasks: Audio Device Selection in the Floating Window

**Input**: Design artifacts from `specs/009-audio-device-selector/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/protocols.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can be executed in parallel (different files, no dependencies)
- **[Story]**: Which user story it belongs to (US1, US2, …)
- All paths are relative to the repository root

---

## Phase 1: Setup

**Goal**: Prepare new models, protocols, and mock infrastructure

- [X] T001 [P] Create models BluetoothProfileState, BluetoothPreparationContext, BluetoothPreparationResult in Verborra/Models/BluetoothProfileState.swift. BluetoothProfileState: `.a2dp(sampleRate: Float64)`, `.hfp(sampleRate: Float64)`, `.unknown`. BluetoothPreparationContext: `.firstStart`, `.deviceSwitch`, `.reconnect` (String rawValue). BluetoothPreparationResult: `.ready(sampleRate:)`, `.alreadyHFP(sampleRate:)`, `.timeout`, `.error(Error)`, `.deviceDisconnected`.
- [X] T002 [P] Extend the AudioDeviceProviding protocol in Verborra/Services/AudioDeviceProviding.swift: add `bluetoothProfileState(for deviceUID: String) -> BluetoothProfileState` (composite analysis FR-035), `streamChannelCount(for deviceUID: String, scope: UInt32) -> UInt32` (input/output channels), `addStreamConfigChangeListener(for deviceUID: String, handler: @escaping @Sendable () -> Void)` (FR-037).
- [X] T003 Implement BT profile analysis in Verborra/Services/CoreAudioDeviceProvider.swift: (1) `streamChannelCount(for:scope:)` — query `kAudioDevicePropertyStreamConfiguration` for input/output scope, return the channel count; (2) `bluetoothProfileState(for:)` — check transportType (filter: bluetooth only), query nominalSampleRate, return .hfp if sample rate ≤ 24000, .a2dp if sample rate ≥ 44100, otherwise .unknown; (3) `addStreamConfigChangeListener(for:handler:)` — listener on `kAudioDevicePropertyStreamConfiguration` input scope. (FR-035, FR-037) **Updated T044**: inputChannels removed from the criterion — unreliable for input-only BT devices.
- [X] T004 Update MockAudioDeviceProvider in VerborraTests/Mocks/MockAudioDeviceProvider.swift: add `mockBluetoothProfileStates: [String: BluetoothProfileState]`, `mockStreamChannelCounts: [String: [UInt32: UInt32]]` (UID → scope → channels), `simulateStreamConfigChange()`, implement the three new protocol methods.

**Checkpoint**: Models and protocols are ready — can proceed to Phase 2

---

## Phase 2: Foundational — BluetoothProfileManager (FR-031/032/033/034/035/036/037)

**Goal**: A single BT device preparation method with composite analysis and debounce stabilization

**CRITICAL**: US2 (Bluetooth) and US7 (sequential switches) depend on this phase

- [X] T005 Create BluetoothProfileManager in Verborra/Services/BluetoothProfileManager.swift: class `@MainActor @Observable`, takes `AudioDeviceProviding` in init, implements BluetoothProfileManaging. Properties: `isPreparing: Bool`, private `currentContinuation`, private `debounceWork`, private `timeoutWork`. (FR-031)
- [X] T006 Implement `prepareForRecording(device:context:) async -> BluetoothPreparationResult` in Verborra/Services/BluetoothProfileManager.swift: (1) check `provider.bluetoothProfileState(for:)` via composite analysis (FR-035) — if .hfp → .alreadyHFP; (2) subscribe to THREE listeners simultaneously: `addSampleRateChangeListener`, `addStreamConfigChangeListener` (FR-037); (3) on ANY listener firing → start debounce stabilization (FR-036): wait 300 ms, re-read all three properties via `provider.bluetoothProfileState(for:)`, if the result differs from the previous reading — another 300 ms; stabilization when two readings match; (4) async wait via `withCheckedContinuation`; (5) total timeout 5 s via DispatchWorkItem (FR-014); (6) on timeout → .timeout; on device disconnect → .deviceDisconnected.
- [X] T007 Implement `restoreA2DP(device:)` in Verborra/Services/BluetoothProfileManager.swift: logging of the start (`bt_a2dp_restore_start`, DEBUG) and result (`bt_a2dp_restore_complete`, INFO). macOS returns A2DP automatically when AudioUnit is released — the method only logs. Errors are not shown to the user. (FR-033)
- [X] T008 Implement `cancelPreparation()` in Verborra/Services/BluetoothProfileManager.swift: cancel the continuation (resume with .deviceDisconnected), cancel debounceWork and timeoutWork, remove all listeners via provider.removeAllListeners(). Called on rapid device switching. (FR-017)
- [X] T009 Add detailed logging of all stages in BluetoothProfileManager via DiagnosticLogger(.bluetooth) in Verborra/Services/BluetoothProfileManager.swift: `bt_prepare_start` (INFO: context, deviceID, deviceName, currentProfile from composite analysis), `bt_profile_check` (INFO: decision skip/required, sampleRate, inputChannels, outputChannels), `bt_switch_initiated` (INFO: deviceID, listenersInstalled: 3), `bt_debounce_reading` (DEBUG: readingNumber, sampleRate, inputChannels, outputChannels, stable: bool), `bt_os_event_received` (INFO: newSampleRate, waitDuration_ms, debounceCount), `bt_prepare_complete` (INFO: result, finalSampleRate, totalDuration_ms). (FR-034)
- [X] T010 Refactor AudioDeviceManager in Verborra/Services/AudioDeviceManager.swift: (1) add `let bluetoothProfileManager: BluetoothProfileManager` in init; (2) in `selectDevice(uid:)` when isBluetooth → delegate to btProfileManager.prepareForRecording() instead of own startBluetoothSwitch(); (3) result mapping: .ready/.alreadyHFP → onBluetoothSwitchComplete(sampleRate), .timeout/.error → onBluetoothSwitchError(message); (4) remove btSwitchShowSpinnerWork, btSwitchTimeoutWork, and startBluetoothSwitch() — logic moved to BluetoothProfileManager.
- [X] T011 Update RecordingViewModel in Verborra/ViewModels/RecordingViewModel.swift: in `switchAudioDevice(to:)` and `startRecording()` when the device is BT → await the result from the manager; on .timeout/.error → show .deviceUnavailable; on .ready/.alreadyHFP → continue recording; on stopping recording on BT → call manager.bluetoothProfileManager.restoreA2DP(device:). (FR-005, FR-033)

**Checkpoint**: Unified BT Profile Manager with composite analysis and debounce is ready

---

## Phase 3: US1 — Selecting an audio device from the floating window (P1) MVP

**Goal**: The user can select an audio device from the dropdown menu, the selection is preserved between sessions

**Independent test**: Open the floating window → list is correct (System Default on top, divider, alphabetical) → selection is preserved after restart

- [X] T012 [P] [US1] Verify that MicrophoneSelectorButton correctly displays System Default first with a Divider and the rest alphabetically in Verborra/Views/Components/MicrophoneSelectorButton.swift (FR-001, FR-002, FR-003). If already implemented — check and close.
- [X] T013 [US1] Verify that AudioDeviceManager.selectDevice(uid:) saves to AppSettings.selectedAudioDeviceUID and restores at startup with fallback to System Default in Verborra/Services/AudioDeviceManager.swift (FR-009).
- [X] T014 [US1] Verify that AudioCaptureService.startRecording(deviceID:) uses deviceID for kAudioOutputUnitProperty_CurrentDevice in Verborra/Services/AudioCaptureService.swift (FR-006).
- [X] T015 [US1] Add logging of device selection: old device (ID, name) → new device (ID, name) via DiagnosticLogger(.audio) in Verborra/Services/AudioDeviceManager.swift (FR-011).

**Checkpoint**: US1 — device selection works, is preserved, is logged

---

## Phase 4: US2 — Bluetooth A2DP→HFP via the unified method (P1)

**Goal**: BT devices correctly switch profile via a single method with composite analysis and debounce

**Independent test**: Connect AirPods → select → start recording → sound is recorded at HFP sample rate

- [X] T016 [US2] Integrate BT preparation into the recording flow: in RecordingViewModel.startRecording() before audioCaptureService.startRecording() check device.transportType.isBluetooth → call btProfileManager.prepareForRecording(context: .firstStart) → await the result in Verborra/ViewModels/RecordingViewModel.swift (FR-005, FR-031)
- [X] T017 [US2] Implement the UI of the "Switching…" spinner on BT preparation >200ms: DispatchWorkItem with a 200ms delay for isBluetoothSwitching, blocking Start/Stop in Verborra/ViewModels/RecordingViewModel.swift (FR-018)
- [X] T018 [US2] Handle BT→BT switching (AirPods → Jabra): in switchAudioDevice(to:) when switching from BT to BT → cancelPreparation() + restoreA2DP on the old one, then prepareForRecording(context: .deviceSwitch) on the new one in Verborra/ViewModels/RecordingViewModel.swift
- [X] T019 [US2] Add a call to restoreA2DP(device:) after stopRecording() for BT devices in Verborra/ViewModels/RecordingViewModel.swift (FR-033)

**Checkpoint**: US2 — BT devices work via a single method with composite analysis

---

## Phase 5: US3 — Automatic fallback on disconnect (P1)

**Goal**: When the selected device is disconnected → stop recording + fallback to System Default

**Independent test**: Start recording on BT → disconnect → recording stopped, "Device disconnected", selection = System Default

- [X] T020 [US3] Verify AudioDeviceManager.handleDeviceListChanged() when selectedDevice disappears → fallback + onDeviceDisconnected in Verborra/Services/AudioDeviceManager.swift (FR-008)
- [X] T021 [US3] Verify RecordingViewModel on onDeviceDisconnected → stop recording + show .deviceDisconnected(deviceName) error, do NOT continue automatically in Verborra/ViewModels/RecordingViewModel.swift (FR-008)
- [X] T022 [US3] Add fallback logging: reason, old device (ID, name), new "System Default" via DiagnosticLogger(.audio) in Verborra/Services/AudioDeviceManager.swift (FR-011)

**Checkpoint**: US3 — fallback works for all device types

---

## Phase 6: US7 — Multiple sequential switches (P1)

**Goal**: The system is stable with 5+ switches in a row without leaks

**Independent test**: 5+ switches System Default → USB → BT → built-in → Continuity during active recording — each time a correct restart

- [X] T023 [US7] Implement cancelPreparation() on rapid switching: in switchAudioDevice(to:) → cancel the previous switchTask + btProfileManager.cancelPreparation() before a new switch in Verborra/ViewModels/RecordingViewModel.swift (FR-017)
- [X] T024 [US7] Verify correct resource release on device change: engine stop, tap remove, buffers reset, listeners cleanup in Verborra/Services/AudioCaptureService.swift (FR-016, FR-017)
- [X] T025 [US7] Handle the change of System Default during recording: if "System Default" is selected + kAudioHardwarePropertyDefaultInputDevice changed → restart recording in Verborra/ViewModels/RecordingViewModel.swift (FR-030)

**Checkpoint**: US7 — stable under any sequence

---

## Phase 7: US4 — Handling recording start error (P2)

**Goal**: Clear error, device selection is preserved

**Independent test**: Attempt to record on an unavailable device → error, device remains selected

- [X] T026 [US4] Verify that on startRecording error → .deviceUnavailable error WITHOUT resetting selectedAudioDeviceID in Verborra/ViewModels/RecordingViewModel.swift (FR-007)
- [X] T027 [US4] Add error logging: device ID, device name, error code via DiagnosticLogger(.audio) in Verborra/Services/AudioCaptureService.swift (FR-013)

**Checkpoint**: US4 — graceful error handling

---

## Phase 8: US5 — Sample rate validation (P2)

**Goal**: The engine starts strictly with the device's actual rate

**Independent test**: Recording on devices with different sample rates → correct rate each time

- [X] T028 [US5] Verify that prepareAndStartEngine() uses `deviceNominalSampleRate(for:)` for tap format (not inputNode.outputFormat) in Verborra/Services/AudioCaptureService.swift (FR-006)
- [X] T029 [US5] Verify that handleDeviceFormatChange() fully restarts the engine with the new sample rate in Verborra/Services/AudioCaptureService.swift (FR-015)

**Checkpoint**: US5 — sample rate is always correct

---

## Phase 9: US6 — Diagnostic logging (P2)

**Goal**: All device operations are fully logged

**Independent test**: Device operations → all events with device ID, name, sample rate in Console.app

- [X] T030 [US6] Add deviceID and deviceName to the "Ring buffer drain" log in AudioCaptureService.updateLevelsFromAtomic() in Verborra/Services/AudioCaptureService.swift (FR-029)
- [X] T031 [US6] Add deviceID and deviceName to all key audio engine log events: "Recording on device", "Engine hardware format", "Installing recording tap" in Verborra/Services/AudioCaptureService.swift (FR-012)
- [X] T032 [US6] Verify the completeness of BluetoothProfileManager logging (T009): all 7 events are present with metadata including composite analysis (inputChannels, outputChannels, debounceCount)

**Checkpoint**: US6 — complete diagnostic logging

---

## Phase 10: US8 — Support for all device types (P3)

**Goal**: Correct work with all types: built-in, USB, Bluetooth, Continuity

**Independent test**: Recording from each device type

- [X] T033 [US8] Verify that CoreAudioDeviceProvider.enumerateInputDevices() returns all types without filtering in Verborra/Services/CoreAudioDeviceProvider.swift (FR-004)
- [X] T034 [US8] Verify that Continuity (iPhone) is handled as a regular device — fallback on disconnect in Verborra/Services/AudioDeviceManager.swift

**Checkpoint**: US8 — all types work

---

## Phase 11: US9 — Saving audio to disk (P3)

**Goal**: Optional WAV writing via Advanced Settings

**Independent test**: Enable → select folder → record → file is created with the correct name

- [X] T035 [P] [US9] Create AudioFileWriter in Verborra/Services/AudioFileWriter.swift: implement AudioFileWriting — startWriting(deviceName:sampleRate:format:folder:) creates AVAudioFile `YYYY-MM-DD_HH-mm-ss_<sanitized name>.wav`; write(buffer:) writes AVAudioPCMBuffer; stopWriting() closes. Characters `/`, `:`, `\` → `_`. Errors are logged, do not interrupt recording. (FR-022, FR-023, FR-025, FR-026)
- [X] T036 [US9] Add settings to AppSettings: isAudioSaveEnabled (default false), audioSaveFolderBookmark (Data?) with Security-Scoped Bookmarks in Verborra/Models/AppSettings.swift (FR-020, FR-021, FR-027)
- [X] T037 [US9] Add UI to Advanced Settings: toggle "Save audio recordings to disk" (disabled without a folder), folder selection button via NSOpenPanel in Verborra/Views/AdvancedSettingsView.swift (FR-020, FR-021, FR-027)
- [X] T038 [US9] Integrate AudioFileWriter into AudioCaptureService: audioSaveSettings, on start → startWriting(), in handleAudioBuffer → write(), on stop/reset → stopWriting(), on format change → restart writing in Verborra/Services/AudioCaptureService.swift (FR-022, FR-024, FR-025, FR-028)
- [X] T039 [US9] Sync settings from AppSettings to AudioCaptureService before startRecording() in Verborra/ViewModels/RecordingViewModel.swift (FR-028)
- [X] T040 [US9] Add entitlement `com.apple.security.files.bookmarks.app-scope` in Verborra.entitlements

**Checkpoint**: US9 — WAV to disk via settings

---

## Phase 12: Polish & Cross-Cutting Concerns

**Goal**: Final polish, edge cases

- [X] T041 Handle hot-plug with the dropdown open: .id(deviceListVersion) to close the Menu in Verborra/Views/Components/MicrophoneSelectorButton.swift (FR-010)
- [X] T042 Verify correct closing of the WAV file when saving is disabled during recording in Verborra/Services/AudioCaptureService.swift
- [X] T043 Verify the absence of leaks: CoreAudio listeners are removed, the engine is stopped, the ring buffer is reset on 5+ switches

---

## Phase 13: Bugfixes — Issues found during testing (2026-03-21)

**Goal**: Fixing critical bugs discovered during manual testing with real devices

- [X] T044 [critical] [US2] Fix BT profile detection in CoreAudioDeviceProvider.bluetoothProfileState(): the condition `inputChannels > 0 || sampleRate <= 24000` erroneously detected A2DP (48kHz) as HFP for input-only BT devices (AntennaPods, Loopback). Fixed to `sampleRate <= 24000` — sample rate is the only reliable criterion. (FR-035)
- [X] T045 [critical] Fix the infinite format listener loop: `handleDeviceFormatChange()` restarted the engine → `installDeviceFormatListener()` → the CoreAudio listener fired immediately (engine setup changes audio properties) → infinite loop. Added `lastKnownSampleRate` — ignore notifications if sampleRate has not changed. (FR-015)
- [X] T046 [high] [US1] Add callback `onDeviceFallback` to AudioCaptureServiceProtocol: on fallback to the default device after an engine error (code -10868) the UI did not update — the floating window continued to show the name of the non-working device. On fallback, `switchAudioDevice(to: "")` is called via the standard flow. (FR-008)
- [X] T047 [medium] [US6] Improve logging in AudioCaptureService: (1) add deviceName + deviceID to all log calls where they were missing (stopRecording, resetRecording, Device not responding, Silent device, Engine stopped, Ring buffer overflow, format listener events); (2) unify the order: deviceName first, deviceID second; (3) rename the key `"device"` → `"deviceName"` in startRecording. (FR-012, FR-013, FR-029)

**Checkpoint**: Critical bugs are fixed, logging is complete and consistent

---

## Phase 14: BT flow refactoring — two-phase startup (2026-03-21)

**Goal**: Eliminate the format mismatch crash when recording on BT devices. Move stabilization from BluetoothProfileManager to AudioCaptureService.

**Reason**: `prepareForRecording` in BluetoothProfileManager waited for A2DP→HFP switching **before** the engine started, but macOS switches the profile only **after** the engine starts → 5s timeout. Also `already_hfp` is unreliable — `deviceNominalSampleRate` may return a stale rate after A2DP restore → format mismatch → crash.

- [X] T048 [critical] [US2] Simplify BluetoothProfileManager.prepareForRecording() to instant profile detection: remove continuation/listeners/timeout/debounce. Returns `.alreadyHFP`, `.needsSwitch`, or `.error`. Add `.needsSwitch(currentSampleRate:)` to BluetoothPreparationResult. (FR-032, FR-037)
- [X] T049 [critical] [US2] Implement two-phase BT startup in AudioCaptureService: add `awaitBluetoothSwitch` parameter to `startRecording`; if true: (1) `startEngineForBTSwitch()` — engine without tap; (2) `awaitBluetoothStabilization()` — listener on `kAudioDevicePropertyNominalSampleRate` + 300ms debounce + 5s timeout; (3) stop trigger engine; (4) `prepareAndStartEngine()` with tap at the stabilized rate. (FR-032, FR-036, FR-040)
- [X] T050 [critical] [US2] Make `awaitBluetoothSwitch: true` mandatory for ALL BT devices: `already_hfp` is unreliable due to a stale rate after A2DP restore. Update RecordingViewModel: startRecording, switchAudioDevice, startInputRecording. (FR-040)
- [X] T051 [critical] [US2] In `handleBTStabilizationEvent()` accept only HFP rate (≤24kHz): engine setup causes false listener triggers at 48kHz → stabilization erroneously returned the A2DP rate → format mismatch crash on `prepareAndStartEngine`. Initial check after 300ms for already-HFP. (FR-036, FR-040)
- [X] T052 [medium] Add extension `AudioCaptureServiceProtocol` with default `awaitBluetoothSwitch: false` for backward compatibility (OnboardingViewModel, non-BT flows). Update MockAudioCaptureService.

**Checkpoint**: BT devices record stably without format mismatch crash

---

## Dependencies and execution order

### Phase dependencies

- **Phase 1 (Setup)**: No dependencies
- **Phase 2 (BT Manager)**: Depends on Phase 1 — **BLOCKS** US2, US7
- **Phase 3 (US1)**: Depends on Phase 1 — **in parallel** with Phase 2
- **Phase 4 (US2)**: Depends on Phase 2
- **Phase 5 (US3)**: Depends on Phase 1 — **in parallel** with Phase 2
- **Phase 6 (US7)**: Depends on Phase 2 + Phase 4
- **Phase 7-9 (US4,5,6)**: Depend on Phase 1 — **parallel** with each other
- **Phase 10 (US8)**: Depends on Phase 3 + Phase 4
- **Phase 11 (US9)**: Depends on Phase 1 — **completely independent**
- **Phase 12 (Polish)**: Depends on all

### Parallelism graph

```
Phase 1 (Setup)
    │
    ├─────────────────┬───────────────┬─────────────┐
    ▼                 ▼               ▼             ▼
Phase 2 (BT)    Phase 3 (US1)   Phase 5 (US3)  Phase 11 (US9)
    │                 │               │
    ▼                 │               │
Phase 4 (US2)        │               │
    │                 │               │
    ▼                 ▼               ▼
Phase 6 (US7)   Phase 7-9 (US4,5,6)  Phase 10 (US8)
                      │
                      ▼
               Phase 12 (Polish)
```

---

## Implementation strategy

### MVP (US1)

1. Phase 1: Setup of models and protocols
2. Phase 3: US1 — device selection works
3. **STOP and VALIDATE**

### Incremental delivery

1. Phase 1 + Phase 2 → BT Manager with composite analysis and debounce ready
2. Phase 3 (US1) → selection works → **MVP!**
3. Phase 4 (US2) → Bluetooth via a single method
4. Phase 5 (US3) → fallback
5. Phase 6 (US7) → stability on switches
6. Phase 7-9 (US4,5,6) → errors, sample rate, logs
7. Phase 10-11 (US8,9) → all types + WAV
8. Phase 12 → polish

---

## Notes

- [P] = different files, no dependencies
- [USN] = binding to a user story
- Key new work: T005-T011 (BluetoothProfileManager with composite analysis FR-035 and debounce FR-036) and T035-T040 (AudioFileWriter)
- T003 — critical task: implementation of composite analysis of 3 properties in CoreAudioDeviceProvider
- Commit after each task or logical group
