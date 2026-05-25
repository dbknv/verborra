# Tasks: Default Audio Device in Settings

**Input**: Design artifacts from `specs/010-default-audio-device/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/protocols.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can be done in parallel (different files, no dependencies)
- **[Story]**: Which user story it relates to (US1, US2, …)
- All paths are relative to the repository root

---

## Phase 1: Foundational — AudioDeviceManager session/persistent split

**Goal**: Add `selectDeviceForSession(uid:)` — the key method for the whole feature

**⚠️ CRITICAL**: US2, US3 depend on this method

- [X] T001 Add `selectDeviceForSession(uid:)` to Verborra/Services/AudioDeviceManager.swift: updates `selectedDevice` without writing to `settings.selectedAudioDeviceUID`. Logs the change as `selectDeviceForSession`. If uid is not found in the list — fallback to System Default. (FR-006)
- [X] T002 In `handleDeviceListChanged()` add a check on `settings.selectedAudioDeviceUID`: if the saved device disappears from the list → reset `settings.selectedAudioDeviceUID` to "" (System Default), independently of the current `selectedDevice`. (FR-008)

**Checkpoint**: AudioDeviceManager distinguishes persistent and session selection

---

## Phase 2: US1 — Default Device Selection in Settings (P1) 🎯 MVP

**Goal**: The Picker in settings uses the stable UID and AudioDeviceManager

**Independent test**: Open settings → choose a device → restart → verify it persists

- [X] T003 [US1] Store `audioDeviceManager` as a property of `AppController` in Verborra/VerborraApp.swift and inject it via `.environment()` into `SettingsView`. (FR-009)
- [X] T004 [US1] Add `audioDeviceManager: AudioDeviceManager` to `SettingsViewModel.init()` in Verborra/ViewModels/SettingsViewModel.swift. Property `audioDevices` → `audioDeviceManager.devices.filter { !$0.isSystemDefaultEntry }`. (FR-001, FR-002)
- [X] T005 [US1] Update `SettingsView.onAppear` in Verborra/Views/SettingsView.swift: obtain `AudioDeviceManager` from `@Environment`, pass it into `SettingsViewModel`. (FR-001)
- [X] T006 [US1] Replace the Picker binding in GeneralSettingsTab in Verborra/Views/SettingsView.swift: bind to `selectedAudioDeviceUID` via `Binding(get: { settings.selectedAudioDeviceUID }, set: { audioDeviceManager.selectDevice(uid: $0) })`. Tags: `device.uid`. ForEach over `viewModel.audioDevices` with `id: \.uid`. (FR-004, FR-009)

**Checkpoint**: The Picker in settings uses the stable UID; the choice persists across restarts

---

## Phase 3: US2 — Loading the Device on Floating Window Open (P1)

**Goal**: When the window opens, the device is loaded from settings

**Independent test**: Set the device in settings → open the floating window → confirm the dropdown shows it

- [X] T007 [US2] In `showOverlay()` in Verborra/ViewModels/RecordingViewModel.swift: load the device from `settings.selectedAudioDeviceUID` via `audioDeviceManager.selectDeviceForSession(uid:)`. If the device is unavailable — fallback to System Default. (FR-005, FR-010)

**Checkpoint**: The floating window opens with the device from settings

---

## Phase 4: US3 — Temporary Device Switch in a Session (P1)

**Goal**: Switching in the floating window does not change settings

**Independent test**: Settings = A → window shows A → switch to B → close → open → A again

- [X] T008 [US3] In `switchAudioDevice(to:)` in Verborra/ViewModels/RecordingViewModel.swift: replace `audioDeviceManager.selectDevice(uid:)` with `audioDeviceManager.selectDeviceForSession(uid:)`. (FR-006)
- [X] T009 [US3] Verify that `selectedAudioDeviceID` in RecordingViewModel is per-session (not persistent), updated on `switchAudioDevice` but NOT written to AppSettings. (FR-006)

**Checkpoint**: Switching in the window does not affect settings; on reopen — the value from settings

---

## Phase 5: US4 — Automatic Fallback on Disconnect (P2)

**Goal**: When the saved device disappears — reset settings to System Default

**Independent test**: Set BT headphones → disconnect → settings = System Default

- [X] T010 [US4] Verify that T002 (`handleDeviceListChanged`) correctly resets `settings.selectedAudioDeviceUID` on disconnect of the saved device. If the floating window is open — the session device is also reset. (FR-008)

**Checkpoint**: Disconnect → settings automatically on System Default

---

## Phase 6: US5 — CADefaultDeviceAggregate Filtering (P2)

**Goal**: System aggregate devices are hidden from all lists

**Independent test**: CADefaultDeviceAggregate is not visible in settings or in the floating window

- [X] T011 [US5] Verify that `CoreAudioDeviceProvider.enumerateInputDevices()` filters `hasPrefix("CADefaultDeviceAggregate")` in Verborra/Services/CoreAudioDeviceProvider.swift. Ensure filtering applies both in settings and in the floating window. (FR-003)

**Checkpoint**: CADefaultDeviceAggregate is hidden everywhere

---

## Phase 7: Polish & Cross-Cutting Concerns

**Goal**: Final polish

- [X] T012 Verify hot-plug list update in settings: connect/disconnect a device while settings are open → the Picker updates. (FR-011)
- [X] T013 Verify the scenario: settings open simultaneously with the floating window → a choice in settings is reflected in the window. (FR-009)

---

## Dependencies and Execution Order

### Phase dependencies

- **Phase 1 (Foundational)**: No dependencies — **BLOCKS** all other phases
- **Phase 2 (US1)**: Depends on Phase 1
- **Phase 3 (US2)**: Depends on Phase 1
- **Phase 4 (US3)**: Depends on Phase 1
- **Phase 5 (US4)**: Depends on Phase 1 (T002)
- **Phase 6 (US5)**: No dependencies (verification of existing code)
- **Phase 7 (Polish)**: Depends on all

### Parallelism graph

```
Phase 1 (Foundational: T001, T002)
    │
    ├──────────┬──────────┬──────────┐
    ▼          ▼          ▼          ▼
Phase 2     Phase 3    Phase 4    Phase 5
(US1)       (US2)      (US3)      (US4)
    │          │          │          │
    └──────────┴──────────┴──────────┘
                    │
              Phase 6 (US5)
                    │
              Phase 7 (Polish)
```

---

## Implementation Strategy

### MVP (US1 + US2 + US3)

1. Phase 1: Foundational (T001, T002)
2. Phase 2: US1 — Picker in settings (T003-T006)
3. Phase 3: US2 — Load on open (T007)
4. Phase 4: US3 — Session-only switch (T008-T009)
5. **STOP and VALIDATE**: settings work, the floating window loads/resets

### Incremental delivery

1. Phase 1-4 → Core flow works → **MVP!**
2. Phase 5 → Fallback on disconnect
3. Phase 6 → Filtering (verification)
4. Phase 7 → Polish

---

## Notes

- All changes are in existing files; no new files
- T001 is the key task; it blocks everything else
- T003-T006 are partially already implemented in the current session (SettingsView, SettingsViewModel, VerborraApp) — but were reverted by the user; they need to be reapplied correctly
- Commit after each logical group
