# Research: Default Audio Device in Settings

**Date**: 2026-03-21
**Feature**: 010-default-audio-device

## Decision 1: Persistent vs Session Selection Split

**Decision**: Add `selectDeviceForSession(uid:)` to `AudioDeviceManager`. The existing `selectDevice(uid:)` remains persistent.

**Rationale**:
- The current `selectDevice(uid:)` always writes to `settings.selectedAudioDeviceUID` (line 94 of AudioDeviceManager.swift)
- For FR-006 we need to update `selectedDevice` without writing to settings
- Minimal change: one new method, call sites switch over

**Alternatives considered**:
- `persist: Bool` flag in `selectDevice()` — rejected: non-obvious API, easy to confuse
- A separate `sessionDevice` property — rejected: duplication, violates SRP

## Decision 2: Loading the Device on Window Open

**Decision**: In `showOverlay()` call `selectDeviceForSession(uid: settings.selectedAudioDeviceUID)`.

**Rationale**:
- `showOverlay()` already contains the session initialization logic (lines 465-467 of RecordingViewModel.swift)
- `settings.selectedAudioDeviceUID` is the canonical source of truth for persistent selection
- If the device is unavailable — `selectDeviceForSession` returns a fallback (System Default)

## Decision 3: SettingsView → AudioDeviceManager

**Decision**: Inject `AudioDeviceManager` via SwiftUI `.environment()`; SettingsViewModel uses it for the device list and persistent selection.

**Rationale**:
- SettingsView currently uses `AudioCaptureService.availableInputDevices()` — which returns numeric IDs, not UIDs
- `AudioDeviceManager.devices` already contains a filtered list with UID and correct sorting
- `.environment()` is the standard SwiftUI pattern for dependency injection

## Decision 4: Disconnect Fallback in Settings

**Decision**: In `handleDeviceListChanged()` additionally check `settings.selectedAudioDeviceUID` — if the device has disappeared, reset to "".

**Rationale**:
- The current code resets `selectedDevice` (runtime) and `settings.selectedAudioDeviceUID` on disconnect
- But only if the current `selectedDevice` matches the one that disappeared
- For FR-008 we also need to reset if the session device differs from persistent, but persistent has disappeared
