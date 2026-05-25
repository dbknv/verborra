# Data Model: Default Audio Device

**Date**: 2026-03-21
**Feature**: 010-default-audio-device

## Entities

### AppSettings (exists, extended)

| Field | Type | Storage | Description |
|-------|------|---------|-------------|
| `selectedAudioDeviceUID` | String | @AppStorage | Stable UID of the default device. Empty string = System Default. Not changed from the floating window. |

**Note**: The `selectedAudioDeviceUID` field already exists from 009. The change is semantic: it stops being updated from the floating window (only from settings).

### AudioDeviceManager (exists, extended)

| Property | Type | Description |
|----------|------|-------------|
| `selectedDevice` | AudioDevice? | Currently active device (session-level). Updated by both methods. |
| `devices` | [AudioDevice] | List of available devices (without CADefaultDeviceAggregate). |

**New methods**:
- `selectDeviceForSession(uid:)` — updates `selectedDevice` without writing to settings

**Existing methods** (semantics unchanged):
- `selectDevice(uid:)` — updates `selectedDevice` AND `settings.selectedAudioDeviceUID`

### RecordingViewModel (exists, behavior changes)

| Property | Type | Description |
|----------|------|-------------|
| `selectedAudioDeviceID` | String? | Per-session, not persistent. Initialized from settings on every `showOverlay()`. |

## Device Selection Lifecycle

```
[Application launch]
    │
    ▼
AudioDeviceManager.init() → restoreSelection()
    → settings.selectedAudioDeviceUID → selectedDevice
    │
    ├── [Settings]
    │   └── Picker → selectDevice(uid:) → persistent + selectedDevice
    │
    └── [Floating window]
        ├── showOverlay() → selectDeviceForSession(uid: settings.selectedAudioDeviceUID)
        │                    → selectedDevice (session only)
        ├── switchAudioDevice() → selectDeviceForSession(uid:)
        │                         → selectedDevice (session only, settings NOT changed)
        └── closeOverlay() → [session state discarded]
                              → next showOverlay() loads from settings again
```

## States and Transitions

### Device in settings (persistent)

```
System Default ←→ Specific device
      ▲                    │
      │                    │ [device disconnected]
      └────────────────────┘
```

### Device in a session (floating window)

```
[showOverlay: load from settings]
         │
         ▼
  Device from settings ──[switchAudioDevice]──→ Another device
         │                                              │
         │ [closeOverlay]                    [closeOverlay]
         ▼                                              ▼
    [state discarded]                           [state discarded]
```
