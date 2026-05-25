# Protocol Contracts: 010-default-audio-device

**Date**: 2026-03-21

## AudioDeviceManager — API changes

### New method

```swift
/// Select device for current session only (floating window).
/// Updates selectedDevice but does NOT write to settings.selectedAudioDeviceUID.
func selectDeviceForSession(uid: String)
```

### Existing method (signature unchanged)

```swift
/// Select device persistently (Settings picker).
/// Updates selectedDevice AND settings.selectedAudioDeviceUID.
func selectDevice(uid: String)
```

### Changed behavior of handleDeviceListChanged

```swift
/// On disconnect:
/// 1. If selectedDevice disappeared -> fallback selectedDevice to System Default
/// 2. If settings.selectedAudioDeviceUID points to a missing device
///    -> reset settings.selectedAudioDeviceUID to "" (System Default)
///    (regardless of the current selectedDevice)
```

## RecordingViewModel — changed behavior

### showOverlay()

```swift
/// When opening the floating window:
/// 1. Load uid from settings.selectedAudioDeviceUID
/// 2. Call audioDeviceManager.selectDeviceForSession(uid:)
/// 3. If the device is unavailable -> fallback to System Default
```

### switchAudioDevice(to:)

```swift
/// When switching the device in the floating window dropdown:
/// 1. Call selectDeviceForSession(uid:) instead of selectDevice(uid:)
/// 2. settings.selectedAudioDeviceUID is NOT changed
```

## SettingsViewModel — new access

```swift
/// AudioDeviceManager is passed in init.
/// audioDevices returns devices without System Default (it is added separately in the Picker).
let audioDeviceManager: AudioDeviceManager

var audioDevices: [AudioDevice] {
    audioDeviceManager.devices.filter { !$0.isSystemDefaultEntry }
}
```
