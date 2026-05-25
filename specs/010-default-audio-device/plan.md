# Implementation Plan: Default Audio Device in Settings

**Branch**: `010-default-audio-device` | **Date**: 2026-03-21 | **Spec**: [spec.md](spec.md)
**Input**: Specification from `/specs/010-default-audio-device/spec.md`

## Summary

Splitting audio device selection into two levels: **persistent** (application settings — default device) and **session** (floating window — temporary choice for a single session). When the floating window opens, the device is loaded from settings; switching in the window does not affect settings. Filtering of `CADefaultDeviceAggregate`, fallback when the device disappears, stable UID.

**Key change**: `switchAudioDevice()` in the floating window no longer saves the choice to `settings.selectedAudioDeviceUID`. The choice in settings is only changed via the Picker in SettingsView.

## Technical Context

**Language/Version**: Swift 5.9+ (Xcode 15+)
**Primary Dependencies**: SwiftUI, AVFoundation, CoreAudio, swift-atomics 1.2.0+, KeyboardShortcuts 2.0.0+
**Storage**: UserDefaults / @AppStorage (settings)
**Testing**: XCTest / Swift Testing
**Target Platform**: macOS 15+ (Sequoia), macOS 26 (Tahoe)
**Project Type**: Native macOS single-target application
**Performance Goals**: < 300 ms device load on window open
**Constraints**: App Sandbox, existing infrastructure from 009
**Scale**: 1 user, 1-10 devices, ~6 changed files

## Constitution Check

*GATE: Must pass before Phase 0.*

| Principle | Status | Comment |
|-----------|--------|---------|
| 1. Native macOS experience | ✅ PASS | SwiftUI Picker in settings, existing dropdown in floating window |
| 2. Swift-first | ✅ PASS | All code in Swift |
| 3. Minimalism | ✅ PASS | Picker already exists, changes in logic, not UI |
| 4. Security | ✅ PASS | No new data, only UID in UserDefaults |
| 5. Code quality | ✅ PASS | Protocols and mocking from 009 |
| 6. Logging | ✅ PASS | Existing logging covers it |

**GATE result**: PASS (no deviations)

## Project Structure

### Documentation (this feature)

```text
specs/010-default-audio-device/
├── plan.md              # This file
├── research.md          # Phase 0: analysis of current code
├── data-model.md        # Phase 1: data model
├── quickstart.md        # Phase 1: quick start
├── contracts/
│   └── protocols.md     # Phase 1: protocol changes
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2: tasks
```

### Source Code (files to change)

```text
Verborra/
├── Services/
│   └── AudioDeviceManager.swift         # selectDevice → two methods: persistent + session
├── ViewModels/
│   ├── RecordingViewModel.swift         # showOverlay() — load from settings; switchAudioDevice — session-only
│   └── SettingsViewModel.swift          # audioDevices → from AudioDeviceManager
├── Views/
│   ├── SettingsView.swift               # Picker → selectedAudioDeviceUID + AudioDeviceManager
│   └── ControlBarView.swift             # No changes (already uses UID)
└── VerborraApp.swift                    # Inject AudioDeviceManager into SettingsView

VerborraTests/
├── AudioDeviceManagerTests.swift        # + tests for session vs persistent
└── ViewModels/
    └── RecordingViewModelTests.swift    # + tests for reset on window open
```

**Structure decision**: Native macOS single-target. Changes in existing files, no new files.

## Current State Analysis (Phase 0)

### What already works

1. **Stable UID**: `AppSettings.selectedAudioDeviceUID` already stores `kAudioDevicePropertyDeviceUID` (009)
2. **CADefaultDeviceAggregate filtering**: already in `CoreAudioDeviceProvider.enumerateInputDevices()` (009)
3. **Hot-plug**: `AudioDeviceManager.handleDeviceListChanged()` with fallback (009)
4. **Session selectedAudioDeviceID**: `RecordingViewModel` already has a non-persistent property (009)
5. **Load on open**: `showOverlay()` already copies the current UID from the manager (009)

### What needs to be fixed

1. **SettingsView Picker** is bound to `selectedAudioDeviceID` (old numeric key) instead of `selectedAudioDeviceUID`
2. **SettingsViewModel.audioDevices** pulls data from `AudioCaptureService.availableInputDevices()` (numeric IDs, no filtering) instead of `AudioDeviceManager.devices`
3. **switchAudioDevice()** calls `audioDeviceManager.selectDevice(uid:)` which saves to settings → violates FR-006
4. **AudioDeviceManager** does not distinguish persistent vs session selection
5. **SettingsView** does not have access to `AudioDeviceManager`
6. **Disconnect fallback** only resets `settings.selectedAudioDeviceUID` if the device was selected in the manager, but does not separately check settings

### Architectural decision

Split `AudioDeviceManager.selectDevice()` into two methods:
- `selectDevice(uid:)` — **persistent**: saves to settings, used from SettingsView
- `selectDeviceForSession(uid:)` — **session-only**: updates `selectedDevice` without writing to settings, used from the floating window

On `showOverlay()` → call `selectDeviceForSession(uid: settings.selectedAudioDeviceUID)` to load from settings.

## Implementation Phases

### Phase 1: AudioDeviceManager — persistent/session split (FR-004, FR-006)

1. Add `selectDeviceForSession(uid:)` to `AudioDeviceManager` — updates `selectedDevice` without writing to `settings.selectedAudioDeviceUID`
2. Keep existing `selectDevice(uid:)` as persistent (for SettingsView)
3. In `handleDeviceListChanged()` — on disconnect, check `settings.selectedAudioDeviceUID` and reset if needed (FR-008)

### Phase 2: RecordingViewModel — session logic (FR-005, FR-006, FR-007)

1. In `showOverlay()` — load the device from `settings.selectedAudioDeviceUID` via `selectDeviceForSession()` (FR-005, FR-007)
2. In `switchAudioDevice()` — replace `selectDevice(uid:)` with `selectDeviceForSession(uid:)` (FR-006)
3. If the device from settings is unavailable on open — fallback to System Default (FR-010)

### Phase 3: SettingsView — Picker on UID (FR-001, FR-002, FR-009)

1. Inject `AudioDeviceManager` via `.environment()` into `SettingsView`
2. `SettingsViewModel` — add `audioDeviceManager`, take `audioDevices` from `AudioDeviceManager.devices`
3. Bind the Picker to `selectedAudioDeviceUID` via `selectDevice(uid:)` (persistent)
4. Real-time hot-plug list update (FR-011)

### Phase 4: Disconnect fallback (FR-008)

1. In `handleDeviceListChanged()` — if `settings.selectedAudioDeviceUID` points to a missing device → reset to "" (System Default)
2. If the floating window is open — switch the session device to System Default

## Notes

- All changes are in existing files; no new files
- CADefaultDeviceAggregate filtering (FR-003) is already implemented in 009
- Hot-plug (FR-011) is already implemented in 009 for the floating window; need to ensure settings also update
- Stable UID (FR-004) is already implemented in 009
