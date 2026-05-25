# Implementation Plan: Audio Device Selection in the Floating Window

**Branch**: `009-audio-device-selector` | **Date**: 2026-03-20 | **Specification**: [spec.md](spec.md)
**Input**: Specification from `/specs/009-audio-device-selector/spec.md`

## Summary

Implementation of audio device selection in the floating recording window with support for all device types (built-in, USB, Bluetooth, Continuity). The key architectural decision is the creation of a dedicated `BluetoothProfileManager` for unified management of A2DP↔HFP switching across all scenarios (first start of recording, device change, reconnect). Profile detection via composite analysis of three CoreAudio properties (sample rate + input channels + output channels) with debounce stabilization of 300 ms. Additionally: optional saving of audio to disk (WAV), extended diagnostic logging.

## Technical Context

**Language/Version**: Swift 5.9+ (Xcode 15+)
**Primary Dependencies**: SwiftUI, AVFoundation (AVAudioEngine), CoreAudio (AudioHardware API), Security (Keychain), swift-atomics 1.2.0+, swift-markdown 0.4.0+, KeyboardShortcuts 2.0.0+
**Storage**: UserDefaults / @AppStorage (settings), macOS Keychain (API key), Security-Scoped Bookmarks (audio folder)
**Testing**: XCTest / Swift Testing + MockAudioDeviceProvider
**Target Platform**: macOS 15+ (Sequoia), macOS 26 (Tahoe)
**Project Type**: Native macOS application (single target)
**Performance Goals**: < 300 ms from hotkey to recording readiness; < 5 s for BT A2DP→HFP switching (including 300 ms debounce); real-time audio capture (lock-free)
**Constraints**: App Sandbox, audio is not saved to disk by default (Principle 4), minimum third-party dependencies
**Scale**: 1 user, 1-10 devices simultaneously, ~10 changed files

## Constitution Check

*GATE: Must pass before Phase 0. Re-check after Phase 1.*

| Principle | Status | Comment |
|-----------|--------|---------|
| 1. Native macOS experience | PASS | SwiftUI + NSPanel for overlay, native CoreAudio APIs for devices |
| 2. Swift-first | PASS | All code in Swift, CoreAudio C API called directly without Obj-C |
| 3. Minimalism | PASS | Dropdown menu in the existing floating window, settings in UserDefaults |
| 4. Security | CONTROLLED | WAV write to disk — uses an approved exception (constitution v1.3.1): opt-in, Advanced Settings, disabled by default |
| 5. Code quality | PASS | AudioDeviceProviding protocol for mocking, existing tests are extended |
| 6. Logging | PASS | DiagnosticLogger with categories .audio, .bluetooth, dual-sink (os.Logger + JSONL) |

**GATE Result**: PASS (one controlled deviation documented in Complexity Tracking)

## Project Structure

### Documentation (this feature)

```text
specs/009-audio-device-selector/
├── plan.md              # This file
├── research.md          # Phase 0: research
├── data-model.md        # Phase 1: data model
├── quickstart.md        # Phase 1: quickstart
├── contracts/           # Phase 1: internal protocols
│   └── protocols.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2: tasks (created by /speckit.tasks)
```

### Source code (repository root)

```text
Verborra/
├── Models/
│   ├── AudioDevice.swift                    # Exists (no changes)
│   ├── AppSettings.swift                    # Exists (+ audioSave settings)
│   ├── RecordingState.swift                 # Exists (+ BT errors)
│   └── BluetoothProfileState.swift          # NEW: profile, context, result
├── Services/
│   ├── AudioCaptureService.swift            # Exists (+ audioSaveSettings, device info in logs)
│   ├── AudioDeviceManager.swift             # Exists (delegating BT → BluetoothProfileManager)
│   ├── AudioDeviceProviding.swift           # Exists (+ bluetoothProfileState, compositeProfileAnalysis)
│   ├── CoreAudioDeviceProvider.swift        # Exists (+ composite analysis implementation FR-035)
│   ├── BluetoothProfileManager.swift        # NEW: unified BT preparation method with debounce
│   ├── AudioFileWriter.swift                # NEW: streaming WAV write to disk
│   └── Logging/
│       └── DiagnosticLogger.swift           # Exists (used)
├── ViewModels/
│   └── RecordingViewModel.swift             # Exists (integration with BT preparation)
└── Views/
    ├── Components/
    │   └── MicrophoneSelectorButton.swift   # Exists (already implemented)
    └── AdvancedSettingsView.swift            # Exists (+ audio saving section)

VerborraTests/
├── AudioDeviceManagerTests.swift            # Exists (+ BT tests)
├── BluetoothProfileManagerTests.swift       # NEW
├── AudioFileWriterTests.swift               # NEW
├── Mocks/
│   └── MockAudioDeviceProvider.swift        # Exists (+ simulateBTProfileChange, mockStreamConfig)
└── ViewModels/
    └── RecordingViewModelTests.swift        # Exists (+ device switch tests)
```

**Structure decision**: Native macOS single-target application. New files are added to existing Services/ and Models/ directories. The key refactoring is the extraction of `BluetoothProfileManager` from `AudioDeviceManager` for FR-031, with composite profile analysis per FR-035 and debounce stabilization per FR-036.

## Complexity Tracking

| Violation | Why needed | Why a simpler alternative does not work |
|-----------|------------|-----------------------------------------|
| WAV write to disk (Principle 4) | FR-020..FR-027: diagnostics and archiving on user request | Constitution v1.3.1 already contains an approved exception for opt-in WAV recording in Advanced Settings |

## Detected issues (2026-03-21)

Testing with real BT devices (AntennaPods, AirPods, Loopback) revealed 3 critical bugs:

### Bug 1: BT profile detection error (T044, FR-035)

**Symptom**: `bt_prepare_start` shows `currentProfile: "HFP"` with `currentSampleRate: 48000` (48kHz = A2DP, not HFP).

**Cause**: The condition `inputChannels > 0 || sampleRate <= 24000` — for input-only BT devices (Loopback aggregate with UID `14-14-7D-E5-38-4A:input`) `inputChannels` is always > 0 regardless of profile. The OR condition made inputChannels dominant.

**Solution**: Remove inputChannels from the criterion. Sample rate is the only reliable indicator: `≤24kHz` → HFP, `≥44.1kHz` → A2DP.

### Bug 2: Infinite format listener loop (T045, FR-015)

**Symptom**: 462 log lines in seconds, the cycle `Device format changed → restart → listener installed → listener fires → restart...` with an interval of ~380ms on the Hijack Mic device.

**Cause**: `handleDeviceFormatChange()` → `prepareAndStartEngine()` → `installDeviceFormatListener()`. Installing a new engine changes CoreAudio properties → the listener fires immediately. There was no check for actual sampleRate change.

**Solution**: Add `lastKnownSampleRate`. Ignore notifications where sampleRate matches the last known value.

### Bug 3: UI does not update on fallback to default (T046, FR-008)

**Symptom**: Engine crashed on AntennaPods (error `-10868`), silently switched to the default device. The floating window continued to show "AntennaPods", the file was written as "AntennaPods.wav".

**Cause**: The `prepareAndStartEngine` fallback path did not notify the UI layer. `selectedDevice` in `AudioDeviceManager` remained the same.

**Solution**: Callback `onDeviceFallback` → `switchAudioDevice(to: "")` via the standard flow.

### Bug 4: prepareForRecording timeout 5s — engine not started (T048/T049)

**Symptom**: `bt_prepare_complete` with `result: "timeout"`, `totalDuration_ms: 5039`. Recording does not start.

**Cause**: `BluetoothProfileManager.prepareForRecording` subscribed to CoreAudio listeners and waited for A2DP→HFP switching. But macOS switches the profile only when the engine actually uses the device as input. The engine started AFTER `prepareForRecording` → the listener never fired → timeout.

**Solution**: Move stabilization to `AudioCaptureService`. New flow: (1) `BluetoothProfileManager` — only profile detection (instant); (2) `AudioCaptureService.startRecording(awaitBluetoothSwitch: true)` — engine without tap → listener waits for HFP rate → stop → fresh engine with tap.

### Bug 5: Format mismatch crash — stale rate (T050/T051)

**Symptom**: `Engine hardware format: actualHWSampleRate: 48000` but `deviceNominalSampleRate` returned 24000. Or vice versa: stabilization returned 48000, but the engine switched to 24000. Crash: `Format mismatch: input hw 24000 Hz, client format 48000 Hz`.

**Cause 1**: `bt_profile_check` → `already_hfp` (rate 24kHz from CoreAudio), but by the time the engine started the device had already returned to A2DP (48kHz). The CoreAudio property was stale.

**Cause 2**: Stabilization accepted 48kHz as a stable rate — a false listener trigger from engine setup (not an actual rate change).

**Solution**: (1) `awaitBluetoothSwitch: true` for ALL BT devices, including `already_hfp`; (2) stabilization accepts only rate ≤24kHz (HFP-range), ignoring A2DP notifications; (3) initial check after 300ms for the already-HFP case.
