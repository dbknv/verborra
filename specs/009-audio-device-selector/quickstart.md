# Quickstart: Audio Device Selection

**Feature**: 009-audio-device-selector
**Date**: 2026-03-20

## Overview

The feature adds audio input device selection to the floating recording window. The user sees a dropdown menu with the "System Default" item at the top (with a divider) and the other devices alphabetically. Automatic fallback on disconnect, Bluetooth A2DP→HFP switching, and hot-plug list updates are supported.

## Prerequisites

- macOS 15+ (Sequoia)
- Xcode 15+ with Swift 5.9+
- A connected audio device (built-in microphone, USB, Bluetooth, or Continuity)
- Microphone access permission

## Key files

| File | Purpose |
|------|---------|
| `Verborra/Models/AudioDevice.swift` | Device model with DeviceUID |
| `Verborra/Services/AudioDeviceManager.swift` | List management, hot-plug, fallback |
| `Verborra/Services/BluetoothProfileManager.swift` | **NEW**: Unified BT A2DP→HFP preparation (FR-031) |
| `Verborra/Models/BluetoothProfileState.swift` | **NEW**: Profile, context, result models |
| `Verborra/Services/AudioFileWriter.swift` | Streaming WAV write to disk |
| `Verborra/Services/AudioCaptureService.swift` | Audio capture (existing, modification) |
| `Verborra/ViewModels/RecordingViewModel.swift` | ViewModel (existing, modification) |
| `Verborra/Views/ControlBarView.swift` | UI dropdown menu (existing, modification) |
| `Verborra/Views/AdvancedSettingsTab.swift` | Save settings (existing, modification) |
| `Verborra/Models/AppSettings.swift` | Selection storage (existing, modification) |

## Architecture

```
┌─────────────────────────────────────────────────┐
│                 ControlBarView                   │
│  ┌──────────────────────────────────┐           │
│  │ Menu (mic.fill, hotkey "1")      │           │
│  │  ┌─ System Default  ✓           │           │
│  │  ├─ ─ ─ ─ ─ ─ ─ ─ ─ ─          │           │
│  │  ├─ AirPods Pro                  │           │
│  │  ├─ Blue Yeti                    │           │
│  │  └─ MacBook Pro Microphone       │           │
│  └──────────────────────────────────┘           │
└──────────────────────┬──────────────────────────┘
                       │ viewModel.switchAudioDevice(to:)
                       ▼
┌─────────────────────────────────────────────────┐
│            RecordingViewModel                    │
│  selectedDeviceUID: String?                      │
│  isBluetoothSwitching: Bool                      │
│  bluetoothSwitchingMessage: String?              │
└──────────────────────┬──────────────────────────┘
            ┌──────────┴──────────┐
            ▼                     ▼
┌───────────────────────┐  ┌───────────────────────────┐
│  AudioDeviceManager   │  │   AudioCaptureService      │
│                       │  │                             │
│ devices: [Device]     │  │ startRecording(deviceID:)   │
│ selectedDevice        │  │ stopRecording() → Data      │
│ hot-plug listener     │  │ resetRecording()             │
│ fallback logic        │  │ AVAudioEngine lifecycle      │
│                       │  │                             │
│ ┌───────────────────┐ │  │ ┌───────────────────────┐  │
│ │ BT Profile Manager│ │  │ │  AudioFileWriter      │  │
│ │ prepareForRecording│ │  │ │  (WAV on disk, opt.)  │  │
│ │ restoreA2DP       │ │  │ └───────────────────────┘  │
│ └───────────────────┘ │  │                             │
└───────────────────────┘  └───────────────────────────┘
         │                        │
         └────────┬───────────────┘
                  ▼
         ┌────────────────────────┐
         │  CoreAudioDeviceProvider│
         │  (AudioDeviceProviding) │
         └────────┬───────────────┘
                  ▼
         ┌────────────────┐
         │   CoreAudio    │
         │ (macOS system) │
         └────────────────┘
```

## Data flows

### 1. Device selection (without recording)
1. The user opens the dropdown → `AudioDeviceManager.devices`
2. The user selects a device → `viewModel.switchAudioDevice(to: uid)`
3. The ViewModel saves to `@AppStorage("selectedAudioDeviceUID")`
4. The dropdown updates the display (checkmark)

### 2. Device selection (during recording)
1. The user selects a device → `viewModel.switchAudioDevice(to: uid)`
2. The ViewModel calls `audioCaptureService.resetRecording()`
3. If Bluetooth → show the spinner after 200ms (FR-018)
4. The ViewModel calls `audioCaptureService.startRecording(deviceID:)`
5. Recording restarts from scratch on the new device

### 3. Hot-plug (disconnection of the selected device)
1. CoreAudio → `AudioDeviceManager` (property listener callback)
2. The manager detects that the selected device has disappeared
3. The manager switches to System Default
4. If recording is active → `audioCaptureService.onDeviceError?(.disconnected)`
5. The ViewModel stops the recording, shows "Device disconnected"

### 4. Application startup
1. `AudioDeviceManager` reads `@AppStorage("selectedAudioDeviceUID")`
2. Enumerates current devices
3. If the saved UID is found → selects it
4. If not found → silent fallback to System Default (without notification)

## Dependencies

- **Feature 008** (Fix Async Concurrency): lock-free audio capture architecture
- **Feature 007** (Diagnostic Logging): DiagnosticLogger system for logging
- **Feature 005** (Recording Window Redesign): floating window and ControlBarView

## Data flows (additional)

### 5. Saving audio to disk (WAV)
1. The user enables "Save audio recordings to disk" in Advanced Settings
2. Selects a folder via NSOpenPanel → a Security-Scoped Bookmark is saved to UserDefaults
3. On recording start: `AudioFileWriter` creates `YYYY-MM-DD_HH-mm-ss_<device>.wav`
4. Each audio buffer from the tap is written to the file via `AVAudioFile.write(from:)`
5. On device/sample rate switch → the file is closed, a new one is created
6. On recording stop → the file is correctly finalized
7. Disk write errors do not interrupt the main recording (graceful degradation)

### 7. Bluetooth Profile Preparation (FR-031/032) — Unified flow

The single method `BluetoothProfileManager.prepareForRecording()` is used in all three scenarios:

**Scenario A: First start of recording on a BT device**
1. The user presses Start → the ViewModel checks `device.transportType.isBluetooth`
2. Call `btProfileManager.prepareForRecording(device, context: .firstStart)`
3. The manager checks the profile via composite analysis (FR-035): sample rate + input channels + output channels
4. If A2DP → subscribe to three properties simultaneously (FR-037), wait with debounce 300 ms (FR-036)
5. If already HFP → `.alreadyHFP(sampleRate:)` — skip waiting
6. After stabilization (two readings match) → the ViewModel starts recording with the final sample rate

**Scenario B: Switch the device to BT**
1. The user switches → `viewModel.switchAudioDevice(to: btUID)`
2. Call `btProfileManager.prepareForRecording(device, context: .deviceSwitch)`
3. Identical sequence of steps 3-6

**Scenario C: Reconnect after disconnect**
1. BT device disconnected → fallback to System Default
2. BT device reconnected → user selects it again
3. Call `btProfileManager.prepareForRecording(device, context: .reconnect)`
4. Identical sequence of steps 3-6

**After stopping recording**: `btProfileManager.restoreA2DP(device)` — silent return (FR-033)

### 6. System Default change during recording (FR-028)
1. The user changes the default device in System Settings
2. CoreAudio → `AudioDeviceManager` (listener `kAudioHardwarePropertyDefaultInputDevice`)
3. If "System Default" is selected and recording is active → restart recording on the new device
4. If WAV recording is active → close the file, create a new one with a timestamp and "System Default"
