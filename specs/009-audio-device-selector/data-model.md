# Data Model: Audio Device Selection

**Date**: 2026-03-20
**Feature**: 009-audio-device-selector

## Entities

### AudioDevice

Represents a single audio input device discovered through CoreAudio.

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| `uid` | `String` | Stable identifier (`kAudioDevicePropertyDeviceUID`). Empty string `""` for System Default (canonical representation across all layers: model, UserDefaults, protocols). Real devices always have a non-empty UID. | CoreAudio |
| `name` | `String` | Display name of the device | `kAudioObjectPropertyName` |
| `audioDeviceID` | `AudioDeviceID` | Numeric CoreAudio ID (unstable, for internal use) | CoreAudio |
| `transportType` | `AudioDeviceTransportType` | Connection type (built-in, USB, Bluetooth, virtual) | `kAudioDevicePropertyTransportType` |
| `isSystemDefault` | `Bool` | Whether this is the system default device | Comparison with `kAudioHardwarePropertyDefaultInputDevice` |

**Protocols**: `Identifiable` (id = `uid.isEmpty ? "system-default" : uid`), `Equatable`, `Hashable`

**Validation rules**:
- `uid` — empty string `""` only for System Default; non-empty string for all real devices
- `name` cannot be an empty string
- `audioDeviceID` must have at least one input stream

### AudioDeviceTransportType

Enumeration of device connection types.

| Value | CoreAudio constant | Description |
|-------|---------------------|-------------|
| `.builtIn` | `kAudioDeviceTransportTypeBuiltIn` | Built-in microphone |
| `.usb` | `kAudioDeviceTransportTypeUSB` | USB device |
| `.bluetooth` | `kAudioDeviceTransportTypeBluetooth` | Bluetooth (Classic) |
| `.bluetoothLE` | `kAudioDeviceTransportTypeBluetoothLE` | Bluetooth Low Energy |
| `.virtual` | `kAudioDeviceTransportTypeVirtual` | Virtual (aggregate) |
| `.unknown` | All others | Unknown type |

**Rule**: `isBluetooth` — `true` for `.bluetooth` and `.bluetoothLE`. Used to determine the need for A2DP→HFP switching.

### DeviceSelection

The user's stored choice (UserDefaults).

| Field | Type | Storage | Description |
|-------|------|---------|-------------|
| `selectedDeviceUID` | `String` | `@AppStorage("selectedAudioDeviceUID")` | UID of the selected device. Empty string = System Default |

**Migration**: On the first launch after the update — if `selectedAudioDeviceID` (the old key) is not empty, attempt to match it with current devices and write to `selectedAudioDeviceUID`. The old key is cleared.

## Device lifecycle

```
[Not detected] ──── hot-plug connection ────▶ [Available]
                                                    │
                                    User selects
                                                    │
                                                    ▼
                                              [Selected]
                                                    │
                                    ┌───────────────┼───────────────┐
                                    │               │               │
                              Recording start  Disconnection   Switch to another
                                    │               │               │
                                    ▼               ▼               ▼
                              [Recording]    [Fallback to     [Available]
                                    │         System Default]
                                    │
                              ┌─────┼─────┐
                              │           │
                        Disconnection  Device change
                              │           │
                              ▼           ▼
                        [Stop recording  [Stop recording
                         + Fallback       + Restart on
                         + Notification]  new device]
```

### BluetoothProfileState (new, FR-035)

The detected profile of a Bluetooth device. Derived via composite analysis of three CoreAudio properties (macOS does not provide a direct API).

| Value | Detection condition (composite analysis) | Description |
|-------|------------------------------------------|-------------|
| `.a2dp(sampleRate: Float64)` | sample rate ≥ 44100 **AND** input channels == 0 **AND** output channels ≥ 2 | High-quality playback |
| `.hfp(sampleRate: Float64)` | sample rate ≤ 24000 **OR** input channels > 0 (the most reliable indicator) | Hands-Free Profile (recording) |
| `.unknown` | could not be determined / transitional state | Indeterminate state |

**Composite analysis (FR-035)**: three properties are checked simultaneously:
1. `kAudioDevicePropertyNominalSampleRate` — primary indicator
2. `kAudioDevicePropertyStreamConfiguration` (input) — input channels > 0 = HFP (the most reliable)
3. `kAudioDevicePropertyStreamConfiguration` (output) — 1 ch = HFP mono, 2 ch = A2DP stereo

**Debounce stabilization (FR-036)**: after a notification — 300 ms pause, re-read all three, repeat if the result is unstable. Total timeout 5 s.

### BluetoothPreparationContext (new, FR-034)

The call context of the unified BT device preparation method.

| Value | Raw Value | Description |
|-------|-----------|-------------|
| `.firstStart` | `"first_start"` | First start of recording on a BT device |
| `.deviceSwitch` | `"device_switch"` | Switching from another device to BT |
| `.reconnect` | `"reconnect"` | Re-connect after disconnect |

### BluetoothPreparationResult (new, FR-032)

The result of the unified preparation method.

| Value | Description |
|-------|-------------|
| `.ready(sampleRate: Float64)` | Switching completed, device is ready |
| `.alreadyHFP(sampleRate: Float64)` | Already in HFP, switching not required |
| `.timeout` | Did not complete within 5 seconds |
| `.error(Error)` | Error during preparation |
| `.deviceDisconnected` | The device was disconnected during preparation |

## Bluetooth Profile Preparation states (FR-031/032)

```
┌─────────┐
│  idle   │ ← initial
└────┬────┘
     │ prepareForRecording(device, context)
     ▼
┌──────────┐
│ checking │ ← checking the current profile
└────┬─────┘
     │
     ├── already HFP → [.alreadyHFP] → idle
     │
     ▼
┌───────────┐
│ switching │ ← A2DP→HFP, listener + 5s timeout
└────┬──────┘
     │
     ├── sample rate changed → [.ready] → idle
     ├── 5s timeout → [.timeout] → idle
     ├── device disconnected → [.deviceDisconnected] → idle
     └── error → [.error] → idle
```

## Bluetooth switching states (UI, FR-018)

```
[Idle] ──── BT device selection ────▶ [Waiting for HFP]
                                            │
                                    ┌───────┼───────┐
                                    │               │
                              < 200ms          ≥ 200ms
                                    │               │
                                    ▼               ▼
                              [Ready]         [Show spinner]
                                                    │
                                            ┌───────┼───────┐
                                            │               │
                                      Stabilization   5s timeout
                                            │               │
                                            ▼               ▼
                                      [Ready]         [Error:
                                                       "Device
                                                       unavailable"]
```

## Relationships between entities

```
AudioDeviceManager ──1:N──▶ AudioDevice
       │
       ├── selectedDevice: AudioDevice?  (current selection)
       ├── systemDefault: AudioDevice    (always exists)
       ├── devices: [AudioDevice]        (sorted list)
       └── bluetoothProfileManager: BluetoothProfileManager
              │
              └── uses AudioDeviceProviding (CoreAudio abstraction)

RecordingViewModel ──1:1──▶ AudioDeviceManager
       │
       └── audioCaptureService: AudioCaptureService
              │
              ├── Uses AudioDeviceID from AudioDevice for the CoreAudio API
              └── uses AudioFileWriter (WAV to disk, optional)
```

### AudioSaveSettings

Settings for saving audio to disk (Advanced Settings).

| Field | Type | Storage | Description |
|-------|------|---------|-------------|
| `isAudioSaveEnabled` | `Bool` | `@AppStorage("isAudioSaveEnabled")` | Whether saving is enabled. Default `false` |
| `audioSaveFolderBookmark` | `Data?` | `UserDefaults` (key `audioSaveFolderBookmark`) | Security-Scoped Bookmark for the selected folder |

**Rules**:
- If `isAudioSaveEnabled == true` and `audioSaveFolderBookmark == nil` → prompt the user to select a folder when recording (FR-027)
- The bookmark is updated when the folder is re-selected or when `bookmarkDataIsStale` is detected

### AudioRecordingFile

Represents a single WAV file being written to disk. Not a persisted entity — exists only during recording.

| Field | Type | Description |
|-------|------|-------------|
| `fileURL` | `URL` | Full path to the file |
| `deviceName` | `String` | Device name (or "System Default") |
| `startedAt` | `Date` | The time when recording into this file started |
| `sampleRate` | `Float64` | Sample rate |
| `audioFile` | `AVAudioFile` | Open file for streaming writes |

**File name**: `YYYY-MM-DD_HH-mm-ss_<deviceName>.wav`
- Characters `/`, `:`, `\` in `deviceName` are replaced with `_`
- For System Default: `2026-03-20_14-30-15_System Default.wav`

**Lifecycle**: Created on recording start → receives buffers via `write(buffer:)` → closed on recording stop, device switch, or sample rate change.

## Storage

| Data | Mechanism | Key |
|------|-----------|-----|
| Selected device UID | `@AppStorage` (UserDefaults) | `selectedAudioDeviceUID` |
| Audio saving on/off | `@AppStorage` (UserDefaults) | `isAudioSaveEnabled` |
| Save folder bookmark | UserDefaults (`Data`) | `audioSaveFolderBookmark` |
| Device list | In-memory (enumeration at startup + hot-plug) | — |
| BT switching state | In-memory (`@Observable` property) | — |
| Current AudioRecordingFile | In-memory (recording lifecycle) | — |
