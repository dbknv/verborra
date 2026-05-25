# Tasks: App settings and onboarding

**Input**: Artifacts from `/specs/002-app-settings-onboarding/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/protocols.md, quickstart.md

**Tests**: Not requested in the specification — test tasks are not included.

**Organization**: Tasks are grouped by User Story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which User Story the task belongs to (US1, US2, US3, US4, US5, US6, US7)
- All paths from the root: `Verborra/`

---

## Phase 1: Foundational — Data model fixes (COMPLETED)

**Purpose**: Remove discrepancies with the specification in shared components.

- [X] T001 ✅ VERIFIED Remove persistence of the current onboarding step from Verborra/ViewModels/OnboardingViewModel.swift
- [X] T002 ✅ VERIFIED [P] Add the computed property `isOnboardingCompleted` in Verborra/Models/AppSettings.swift

**Checkpoint**: OnboardingViewModel always starts from welcome, AppSettings exposes the onboarding completion flag

---

## Phase 2: User Story 1 — Onboarding on first launch (Priority: P1) (COMPLETED)

- [X] T003 ✅ VERIFIED [US1] "Back"/"Next"/"Finish" navigation in onboarding
- [X] T004 ✅ VERIFIED [US1] Non-closable onboarding window
- [X] T005 ✅ VERIFIED [P] [US1] Block settings during onboarding
- [X] T006 ✅ VERIFIED [P] [US1] Block the floating window during onboarding
- [X] T007 ✅ VERIFIED [US1] Permissions screen (auto-check, buttons, descriptions, transition condition)
- [X] T008 ✅ VERIFIED [US1] Completion screen (hotkey, API key, validation)

---

## Phase 3: User Story 2 — GPT 5.x LLM models (Priority: P1) (COMPLETED)

- [X] T009 ✅ VERIFIED [US2] Verify GPT 5.x models in LLMModel.swift

---

## Phase 4: US3 settings visuals, US4 onboarding reset (Priority: P2/P3) (COMPLETED)

- [X] T010 ✅ VERIFIED [US3] Increase the size of the settings window
- [X] T011 ✅ VERIFIED [P] [US3] Improve the General tab
- [X] T012 ✅ VERIFIED [P] [US3] Improve the Prompts tab
- [X] T013 ✅ VERIFIED [P] [US3] Improve the About tab
- [X] T014 ✅ VERIFIED [US4] Add the `.advanced` case to SettingsTab
- [X] T015 ✅ VERIFIED [US4] Create AdvancedSettingsTab

---

## Phase 5-10: Edge cases, permissions, bugfixes (COMPLETED)

- [X] T016 ✅ VERIFIED Edge case: missing API key
- [X] T017 ✅ VERIFIED Edge case: model not supported by the API
- [X] T018 ✅ VERIFIED Validation per quickstart.md
- [X] T019 ✅ VERIFIED AppDelegate refactoring
- [X] T020 ✅ VERIFIED [BUG] isOnboardingCompleted reactivity
- [X] T021 ✅ VERIFIED [US3] Split check/request for permissions
- [X] T022 ✅ VERIFIED [US3] Update permission buttons
- [X] T023 ✅ VERIFIED [US1] Disable App Sandbox
- [X] T024 ✅ VERIFIED [US1] Handle denied Microphone
- [X] T025 ✅ VERIFIED [US1] openSettings() in RecordingViewModel
- [X] T026 ✅ VERIFIED [US1] openSettings from SwiftUI environment
- [X] T027 ✅ VERIFIED [US1] Update the button in RecordingView
- [X] T028 ✅ VERIFIED [US1] Request Microphone on notDetermined
- [X] T029 ✅ VERIFIED [BUG] Keychain without Data Protection

---

## Phase 11: Setup — Prepare the data model for new features

**Goal**: Extend the data model and enum to support the new settings tabs and the configurable recording hotkey

- [X] T030 ✅ VERIFIED Add the fields `recordingKeyCode: Int` (default 49, Space) and `recordingModifiers: Int` (default 0) with `@ObservationIgnored @AppStorage` and the computed property `recordingKeyDisplayName: String` (conversion keyCode → human-readable name) in Verborra/Models/AppSettings.swift (RES-004, data-model.md)
- [X] T031 ✅ VERIFIED Extend the `SettingsTab` enum to 6 cases: add `.hotkeys` (title: "Hotkeys", icon: "keyboard") and `.llm` (title: "LLM", icon: "brain") between `.prompts` and `.about` in Verborra/Views/SettingsView.swift (RES-009, data-model.md)

**Checkpoint**: Data model and navigation are ready for the new tabs

---

## Phase 12: User Story 3 (follow-up) — Settings sidebar reorganization (Priority: P2)

**Goal**: Update the sidebar to 6 tabs, remove the sidebar collapse button, fixed width 210px, correct insets from the traffic lights

**Independent test**: Open settings → sidebar with 6 tabs, the collapse button is absent, the insets from the traffic lights are correct

### Implementation

- [X] T032 ✅ VERIFIED [US3] Add `.toolbar(removing: .sidebarToggle)` to NavigationSplitView to remove the sidebar collapse button in Verborra/Views/SettingsView.swift (FR-015, RES-005)
- [X] T033 ✅ VERIFIED [US3] Add routing for the new tabs `.hotkeys` and `.llm` in the NavigationSplitView detail section (initially with placeholder views) in Verborra/Views/SettingsView.swift (FR-014)

**Checkpoint**: Sidebar with 6 tabs, no collapse button, correct insets

---

## Phase 13: User Story 5 — "Hotkeys" tab in settings (Priority: P2)

**Goal**: New tab with the overlay hotkey setting (moved from General) and the recording hotkey (new, default Space), conflict detection

**Independent test**: Settings → "Hotkeys" → two hotkeys visible, change each one, check the warning on conflict. The overlay hotkey is no longer in the General tab

### User Story 5 implementation

- [X] T034 ✅ VERIFIED [US5] Create Verborra/Views/HotkeysSettingsTab.swift with the overlay invocation hotkey section — move HotkeyRecorder (KeyboardShortcuts.Recorder) from GeneralSettingsTab (FR-023)
- [X] T035 ✅ VERIFIED [US5] Add the recording start/stop hotkey section to HotkeysSettingsTab — create a custom NSViewRepresentable recorder for capturing a keyCode without a modifier (default Space), human-readable name display, reset-to-default button in Verborra/Views/HotkeysSettingsTab.swift (FR-024, RES-011)
- [X] T036 ✅ VERIFIED [US5] Implement hotkey conflict detection: method `hasHotkeyConflict(keyCode:modifiers:) -> Bool` in SettingsViewModel, inline warning in HotkeysSettingsTab on conflict, blocking the save in Verborra/ViewModels/SettingsViewModel.swift and Verborra/Views/HotkeysSettingsTab.swift (FR-025, RES-008)
- [X] T037 ✅ VERIFIED [US5] Remove the "Hotkey" section (HotkeyRecorder) from GeneralSettingsTab in Verborra/Views/SettingsView.swift (US5-SC6)
- [X] T038 ✅ VERIFIED [US5] Update `handleKeyDown()` in RecordingViewModel to use `appSettings.recordingKeyCode` and `appSettings.recordingModifiers` instead of the hardcoded keyCode 49 (Space) in Verborra/ViewModels/RecordingViewModel.swift (RES-004)

**Checkpoint**: "Hotkeys" tab with two settings and conflict detection, General has no hotkey

---

## Phase 14: User Story 6 — "LLM" tab in settings (Priority: P2)

**Goal**: New tab with the API key (moved from General), STT model and LLM model (moved from Prompts), info popovers

**Independent test**: Settings → "LLM" → API key, STT model, LLM model with info popovers are visible. General has no API key, Prompts has no models

### User Story 6 implementation

- [X] T039 ✅ VERIFIED [US6] Create Verborra/Views/LLMSettingsTab.swift with the OpenAI API key section — move the SecureField + validation + "Save and verify" from GeneralSettingsTab (FR-026)
- [X] T040 ✅ VERIFIED [US6] Add the STT model selection section (Picker with info popover) to LLMSettingsTab — move from PromptsSettingsTab in Verborra/Views/LLMSettingsTab.swift (FR-027)
- [X] T041 ✅ VERIFIED [US6] Add the LLM model selection section (Picker with info popover, description + price) to LLMSettingsTab in Verborra/Views/LLMSettingsTab.swift (FR-028, FR-029, FR-030)
- [X] T042 ✅ VERIFIED [US6] Remove the "OpenAI API" section from GeneralSettingsTab in Verborra/Views/SettingsView.swift (US6-SC5)
- [X] T043 ✅ VERIFIED [US6] Remove modelsSection (STT/LLM Picker + info popovers) from PromptsSettingsTab in Verborra/Views/SettingsView.swift (US6-SC5)
- [X] T044 ✅ VERIFIED [US6] Replace the placeholder views in the SettingsView detail section with the real HotkeysSettingsTab and LLMSettingsTab in Verborra/Views/SettingsView.swift

**Checkpoint**: "LLM" tab is fully functional, General and Prompts are cleared of the moved settings

---

## Phase 15: User Story 7 — Positioning and fixed size of the floating window (Priority: P2)

**Goal**: Horizontal center, 10% from the bottom, fixed size, controls at the bottom, multi-monitor

**Independent test**: Trigger the overlay → position (horizontal center, 10% from the bottom), fixed size, controls at the bottom, on multi-monitor — on the screen with the key window

### User Story 7 implementation

- [X] T045 ✅ VERIFIED [P] [US7] Implement `positionOnScreen()` in OverlayPanel: position by horizontal center and 10% from the bottom via `NSScreen.visibleFrame`, multi-monitor (NSApp.keyWindow?.screen ?? NSScreen.main) in Verborra/Views/OverlayPanel.swift (FR-033, RES-007)
- [X] T046 ✅ VERIFIED [US7] Replace `compactSize`/`expandedSize` with a single `fixedSize = NSSize(width: 480, height: 400)`, remove `resizeToCompact()`/`resizeToExpanded()` from OverlayPanel and OverlayManager, call `positionOnScreen()` instead of `center()` in `show()` in Verborra/Views/OverlayPanel.swift (FR-034, RES-007)
- [X] T047 ✅ VERIFIED [US7] Handle the edge case: if the window does not fit on a small screen — `clamp` the coordinates within visibleFrame in Verborra/Views/OverlayPanel.swift (Edge Case)
- [X] T048 ✅ VERIFIED [US7] Move the selectors bar (PromptSelectorView, LanguageSelectorView) from the top of the VStack to the bottom in Verborra/Views/OverlayContentView.swift (FR-035, RES-010)
- [X] T049 ✅ VERIFIED [US7] Remove the `resizeToExpanded()` call in onChange(of: viewModel.state) in OverlayContentView (the method was removed in T046) in Verborra/Views/OverlayContentView.swift

**Checkpoint**: The overlay has a fixed size, is positioned correctly, controls are at the bottom

---

## Phase 16: Polish & Cross-Cutting Concerns

**Goal**: Final check and validation

- [X] T050 ✅ VERIFIED Verify that data is not lost when settings are moved: API key (Keychain), overlay hotkey (KeyboardShortcuts), STT/LLM models (@AppStorage) — everything is stored in AppSettings, UI-only change
- [X] T051 ✅ VERIFIED Run the validation per quickstart.md — go through all the testing scenarios from specs/002-app-settings-onboarding/quickstart.md

---

## Dependencies and execution order

### Phase dependencies

- **Phase 11 (Setup)**: No dependencies — start immediately. Blocks Phase 13, 14
- **Phase 12 (US3 sidebar)**: Depends on T031 (Phase 11). Blocks Phase 13, 14 (navigation to new tabs)
- **Phase 13 (US5 Hotkeys)**: Depends on T030, T031 (Phase 11) and T033 (Phase 12)
- **Phase 14 (US6 LLM tab)**: Depends on T031 (Phase 11) and T033 (Phase 12)
- **Phase 15 (US7 Overlay)**: Fully independent — can start immediately in parallel with Phase 11
- **Phase 16 (Polish)**: Depends on all previous phases

### Dependencies between User Stories (new)

- **US5 (Hotkeys)** and **US6 (LLM tab)**: Independent of each other, both depend on US3 (sidebar)
- **US7 (Overlay)**: Fully independent of the others

### Inside each User Story

- US5: T034 → T035 → T036 (the recorder is needed for detection), T037 in parallel with T034, T038 after T030
- US6: T039, T040, T041 in parallel (different sections) → T042, T043 (removal from old tabs) → T044
- US7: T045 → T046 (positionOnScreen is needed for show), T047 after T045, T048 and T049 in parallel

### Parallelization opportunities

- T030 and T031 — in parallel (different files)
- Phase 15 (US7) in parallel with Phase 11-14
- T039, T040, T041 — in parallel (different sections of one file, but creating a new file)
- T048 and T049 — in parallel (different aspects of OverlayContentView)

---

## Parallel example: Phase 11

```bash
# In parallel — different files:
T030: "AppSettings.swift — add recordingKeyCode/recordingModifiers"
T031: "SettingsView.swift — extend SettingsTab to 6 cases"
```

## Parallel example: Independent User Stories

```bash
# After Phase 11, in parallel:
Phase 12-14 (US3/US5/US6): Settings — SettingsView, HotkeysSettingsTab, LLMSettingsTab
Phase 15 (US7): Overlay — OverlayPanel.swift, OverlayContentView.swift
```

---

## Implementation strategy

### Recommended order

1. **Phase 11** (Setup): T030 + T031 in parallel
2. **Phase 12** (US3 sidebar): T032 + T033
3. **Phase 13** (US5 Hotkeys): T034-T038
4. **Phase 14** (US6 LLM tab): T039-T044
5. **Phase 15** (US7 Overlay): T045-T049 — can run in parallel with Phase 12-14
6. **Phase 16** (Polish): T050-T051

### Incremental delivery

1. Phase 11 + 12 → Sidebar with 6 tabs (visually ready, placeholders)
2. Phase 13 → "Hotkeys" tab functional
3. Phase 14 → "LLM" tab functional, old tabs cleaned up
4. Phase 15 → Overlay positioned correctly
5. Phase 16 → Final validation

---

## Notes

- [P] = different files, no dependencies
- [Story] = link to a User Story for traceability
- Each User Story is independently testable
- Commit after each task or logical group
- New files: HotkeysSettingsTab.swift, LLMSettingsTab.swift
- Moving settings — UI-only operation, data in AppSettings/Keychain is unchanged
- Recording hotkey — local (KeyCaptureView), not global (KeyboardShortcuts)
- `.toolbar(removing: .sidebarToggle)` is available in macOS 14+ (target platform)
