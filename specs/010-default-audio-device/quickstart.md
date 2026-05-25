# Quick Start: 010-default-audio-device

## Prerequisites

- macOS 15+ (Sequoia)
- Xcode 15+
- Branch `010-default-audio-device`
- Completed feature 009-audio-device-selector (in main)

## What Is Being Implemented

Splitting audio device selection into two levels:
1. **Settings** (persistent) — default device, persisted across sessions
2. **Floating window** (session) — temporary choice, reset on close

## Main Changes

### AudioDeviceManager
- New method `selectDeviceForSession(uid:)` — session-only, no writes to settings
- `handleDeviceListChanged()` — fallback for persistent selection on disconnect

### RecordingViewModel
- `showOverlay()` — load the device from settings
- `switchAudioDevice()` — session-only via `selectDeviceForSession`

### SettingsView
- Picker bound to `selectedAudioDeviceUID` (stable UID)
- Device list from `AudioDeviceManager.devices`
- Selection via `selectDevice(uid:)` (persistent)

### VerborraApp
- `AudioDeviceManager` injected via `.environment()` for SettingsView

## Testing

1. Open settings → choose USB Microphone → restart → verify it persists
2. Open the floating window → confirm USB Microphone is selected
3. Switch to Built-in in the window → close → open → USB Microphone again
4. Disconnect USB Microphone → settings reset to System Default
5. CADefaultDeviceAggregate is not visible either in settings or in the window
