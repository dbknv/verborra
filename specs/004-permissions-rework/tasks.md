# Tasks: Permission Request Process and Status Display Rework

**Input**: Design documents from `/specs/004-permissions-rework/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Organization**: Tasks are grouped by user stories for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can be executed in parallel (different files, no dependencies)
- **[Story]**: Which user story the task belongs to (US1, US2, US3, US4, US5, US6)

## Phase 1: Setup

**Purpose**: Create base types and the protocol for the permissions system

- [X] T001 Create the `PermissionType` enum and the `PermissionStatus` enum in Verborra/Services/PermissionManager.swift — permission types (microphone, accessibility) and statuses (notDetermined, granted, denied, restricted) per data-model.md. Add the `isRequired: Bool` property to PermissionType and `systemSettingsURL: String`
- [X] T002 Create the `PermissionChecking` protocol in Verborra/Services/PermissionChecking.swift — properties `microphoneStatus`, `accessibilityStatus` (both PermissionStatus), methods `requestMicrophoneAccess()`, `requestAccessibilityAccess()`, `startMonitoring()`, `stopMonitoring()` per plan.md

---

## Phase 2: Foundational (PermissionManager — system core)

**Purpose**: A single permissions manager covering US5 (background monitoring) and US6 (reusable component)

**CRITICAL**: All user stories depend on completion of this phase

- [X] T003 [US6] Implement the `PermissionManager` class (@Observable, singleton) in Verborra/Services/PermissionManager.swift, implementing the `PermissionChecking` protocol: properties `microphoneStatus` and `accessibilityStatus`, internal state `monitoringCount` and `pollingTimer` per data-model.md
- [X] T004 Implement the `checkMicrophoneStatus()` method in Verborra/Services/PermissionManager.swift — use `AVCaptureDevice.authorizationStatus(for: .audio)` without side effects (R1 from research.md), mapping of system statuses to PermissionStatus
- [X] T005 Implement the `checkAccessibilityStatus()` method in Verborra/Services/PermissionManager.swift — use `AXIsProcessTrusted()` without side effects (R2 from research.md), mapping Bool to PermissionStatus (.granted / .denied)
- [X] T006 Implement the `requestMicrophoneAccess()` method in Verborra/Services/PermissionManager.swift — two-branch logic: if `.notDetermined` → `AVCaptureDevice.requestAccess(for: .audio)`, if `.denied`/`.restricted` → `NSWorkspace.shared.open(URL)` for System Settings (R3 from research.md, FR-004a/FR-004b). Add the `isRequestInProgress` flag — ignore repeated calls while the system dialog is active (edge case from spec.md). **The `.denied` branch is redefined in T033 (US2a): instead of a direct openSystemSettings → showMicrophoneDeniedAlert (NSAlert + quit)**
- [X] T007 Implement the `requestAccessibilityAccess()` method in Verborra/Services/PermissionManager.swift — `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`; if the application is already in the list and is disabled → additionally open System Settings (R4 from research.md, FR-004a/FR-004b). Use the shared `isRequestInProgress` flag from T006
- [X] T008 [US5] [US6] Implement `startMonitoring()` / `stopMonitoring()` in Verborra/Services/PermissionManager.swift — subscriber counter pattern: increment/decrement monitoringCount, Timer with a 1-second interval, calling `checkMicrophoneStatus()` + `checkAccessibilityStatus()` on every tick (R5 from research.md, FR-006/FR-007)
- [X] T009 [US5] [US6] Implement status-change detection in Verborra/Services/PermissionManager.swift — when the status changes from denied/notDetermined to granted (or back) save the previous value and publish the change via @Observable. **Important**: PermissionManager only publishes the change; it does NOT call NSApp.activate — that is the UI layer's responsibility via `.onChange(of:)` (R6, FR-014, separation of concerns)

**Checkpoint**: PermissionManager is ready — user story implementation can begin

---

## Phase 3: US1 — Application launch without microphone access (Priority: P1) MVP

**Goal**: When the application launches without microphone access, onboarding opens from the first step

**Independent test**: Revoke microphone access in System Settings → Privacy & Security → Microphone, restart the application — the onboarding window must open

### US1 implementation

- [X] T010 [US1] Modify Verborra/VerborraApp.swift — at startup check `PermissionManager.shared.microphoneStatus`: if != .granted → show onboarding from the first step (full flow), regardless of `isOnboardingCompleted` (FR-001, FR-002). Do NOT check Accessibility at startup (FR-003)

**Checkpoint**: US1 completed — the application correctly detects missing microphone access at startup

---

## Phase 4: US2 — Microphone access request (Priority: P1)

**Goal**: The user can request microphone access through a unified UI from onboarding and settings

**Independent test**: Open onboarding/settings → click "Request access" → on the first request a macOS system dialog, on repeated — System Settings

### US2 implementation

- [X] T011 [US2] [US6] Create `PermissionStatusView` in Verborra/Views/Components/PermissionStatusView.swift — a SwiftUI View accepting PermissionType, displaying the status for all 4 PermissionStatus values: `.notDetermined` → "Request access" button (will invoke the system modal), `.denied`/`.restricted` → "Open settings" button (will open System Settings), `.granted` → "Access granted" check icon. Use PermissionManager to get status and to request (FR-005, FR-015)
- [X] T012 [US2] Modify Verborra/Views/Onboarding/PermissionsStep.swift — replace the current status display logic with PermissionStatusView for the microphone. Add a `PermissionManager.shared.startMonitoring()` call in onAppear and `stopMonitoring()` in onDisappear (FR-006)
- [X] T013 [US2] Modify Verborra/Views/SettingsView.swift — replace the current microphone status display section with PermissionStatusView. Add `startMonitoring()` / `stopMonitoring()` calls (FR-006)
- [X] T014 [US2] Modify Verborra/ViewModels/OnboardingViewModel.swift — remove the methods `requestMicrophone()`, `checkMicrophonePermission()` and the property `isMicrophoneGranted`; replace with using `PermissionManager.shared` (FR-015, removing duplication)
- [X] T015 [US2] Modify Verborra/ViewModels/SettingsViewModel.swift — remove the methods `requestMicrophonePermission()`, `checkMicrophonePermission()` and the property `isMicrophoneGranted`; replace with using `PermissionManager.shared` (FR-015, removing duplication)
- [X] T016 [US2] Add an `.onChange(of:)` handler in PermissionsStep.swift and SettingsView.swift for `microphoneStatus` and `accessibilityStatus` — when either status changes, call `NSApp.activate(ignoringOtherApps: true)` to bring the window to the front (FR-014). A unified handler for both statuses — task T026 from US3 is not needed

**Checkpoint**: US2 completed — microphone request works uniformly from onboarding and settings

---

## Phase 5: US4 — Floating recording window: access check (Priority: P1)

**Goal**: The floating window shows the "No access" state or the recording interface depending on microphone status

**Independent test**: Revoke microphone access → open the floating recording window — it must show "No microphone access" with a "Go to settings" button

### US4 implementation

- [X] T017 [US4] Modify Verborra/Views/OverlayContentView.swift — add a `PermissionManager.shared.startMonitoring()` call in onAppear and `stopMonitoring()` in onDisappear. Add a `microphoneStatus` check to choose the displayed content (FR-009)
- [X] T018 [US4] Modify Verborra/Views/RecordingView.swift — add a "No microphone access" state with a "Go to settings" button (FR-010, FR-011). The "Go to settings" button opens the application settings and closes the floating window (FR-011a)
- [X] T019 [US4] Add auto-refresh in Verborra/Views/RecordingView.swift — `.onChange(of: permissionManager.microphoneStatus)`: on transition to .granted automatically switch to the recording interface (FR-011b)
- [X] T020 [US4] Modify Verborra/Views/RecordingView.swift — disable the "Paste text" button (`.disabled()`) if `accessibilityStatus != .granted` (FR-012, FR-013)
- [X] T021 [US4] Modify Verborra/ViewModels/RecordingViewModel.swift — replace direct permission checks with using `PermissionManager.shared` to determine button and feature availability

**Checkpoint**: US4 completed — the floating window reacts correctly to absence/presence of access

---

## Phase 6: US3 — Accessibility access request (Priority: P2)

**Goal**: The user can request Accessibility access through a unified UI from onboarding and settings

**Independent test**: Open onboarding/settings → click "Request access" for Accessibility — on the first request a system dialog, on repeated — System Settings

### US3 implementation

- [X] T022 [US3] Add PermissionStatusView for Accessibility in Verborra/Views/Onboarding/PermissionsStep.swift — similar to the microphone, status display and a "Request access" button for Accessibility
- [X] T023 [US3] Add PermissionStatusView for Accessibility in Verborra/Views/SettingsView.swift — an Accessibility status section using the unified component
- [X] T024 [US3] Modify Verborra/ViewModels/OnboardingViewModel.swift — remove the methods `requestAccessibility()`, `checkAccessibility()` and the property `isAccessibilityGranted`; replace with using `PermissionManager.shared`
- [X] T025 [US3] Modify Verborra/ViewModels/SettingsViewModel.swift — remove the methods `requestAccessibilityPermission()`, `checkAccessibilityPermission()` and the property `isAccessibilityGranted`; replace with using `PermissionManager.shared`

> **Note (F2)**: Between Phase 4 (US2) and the completion of Phase 6 (US3), the ViewModels are in an intermediate state — microphone logic is removed, Accessibility is not yet in place. This is expected and correct.

**Checkpoint**: US3 completed — Accessibility requests work uniformly

---

## Phase 6a: US2a — Repeated microphone request at `.denied` (Priority: P1)

**Goal**: When "Request access" is clicked for the microphone at `.denied` status, show a modal with instructions, and after confirmation — open System Settings and quit the application. This is required by the TCC cache: `AVCaptureDevice.authorizationStatus` does not refresh without restarting the process.

**Independent test**: Revoke microphone access in System Settings → open the application → click "Request access" → a modal with instructions appears → "Got it, open settings" → System Settings opens, the application quits → grant access → start the application → normal startup

### US2a implementation

- [X] T033 [US2a] Update the `requestMicrophoneAccess()` method in Verborra/Services/PermissionManager.swift — change the `.denied` branch: instead of calling `openSystemSettings(for: .microphone)` directly, call the new method `showMicrophoneDeniedAlert()`. The `.restricted` branch still opens System Settings directly (FR-016, FR-020). The `.notDetermined` branch is unchanged
- [X] T034 [US2a] Implement the `showMicrophoneDeniedAlert()` method in Verborra/Services/PermissionManager.swift — create NSAlert (R9 from research.md): messageText = "Restart required", informativeText = "The application will close → system settings will open → grant microphone access → reopen the application. These are macOS system limitations", alertStyle = .informational, buttons: "Got it, open settings" + "Cancel" (FR-017, FR-019)
- [X] T035 [US2a] Implement NSAlert result handling in `showMicrophoneDeniedAlert()` in Verborra/Services/PermissionManager.swift — on `.alertFirstButtonReturn`: (1) open System Settings via `NSWorkspace.shared.open(URL)`, (2) via DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) call `NSApp.terminate(nil)` (R10 from research.md, FR-018). On `.alertSecondButtonReturn` (Cancel): do nothing, close the dialog (FR-019)
- [X] T036 [P] [US2a] Add localization strings in Verborra/Localizable.xcstrings — keys for the US2a modal: title "Restart required", instruction text, "Got it, open settings" button, "Cancel" button. For Russian and English languages
- [X] T037 [US2a] Update Verborra/Views/Components/PermissionStatusView.swift — for `permissionType == .microphone` and `status == .denied` change the button text from the current "Open settings" to "Request access" (uniform for the user — FR-004c). The button behavior (calling `requestMicrophoneAccess()`) stays the same, but now PermissionManager will show NSAlert instead of opening System Settings directly

**Checkpoint**: US2a completed — for microphone `.denied` a modal with instructions is shown; confirmation → quit + System Settings, cancel → nothing

---

## Phase 7: Service integration and edge cases

**Purpose**: Update services to use PermissionManager and handle edge cases

- [X] T026 [P] Modify Verborra/Services/AudioCaptureService.swift — replace the direct `AVCaptureDevice.authorizationStatus` check with `PermissionManager.shared.microphoneStatus` before starting recording. Add handling for microphone revocation **during recording**: on detecting `.denied` → stop recording, show an error message (edge case from spec.md)
- [X] T027 [P] Modify Verborra/Services/PasteService.swift — replace the direct `AXIsProcessTrusted()` call with `PermissionManager.shared.accessibilityStatus` before pasting text
- [X] T028 Add defensive handling in Verborra/Services/PermissionManager.swift — graceful fallback for unknown `AVAuthorizationStatus` values (future macOS versions may add new cases) → map to `.notDetermined`. Handle `NSWorkspace.shared.open(URL)` errors → show a textual instruction on how to open System Settings manually (edge cases from spec.md)

---

## Phase 8: Tests and finalization

**Purpose**: Unit tests for PermissionManager business logic (constitution requirement, Principle 5) and final validation

- [X] T030 Create `MockPermissionManager` in VerborraTests/Mocks/MockPermissionManager.swift — a mock implementing the `PermissionChecking` protocol for unit tests. It must allow programmatically setting statuses and tracking method calls
- [X] T031 Write unit tests for PermissionManager in VerborraTests/Services/PermissionManagerTests.swift — tests for: (1) correct mapping of system statuses to PermissionStatus, (2) two-branch logic of requestMicrophoneAccess (notDetermined → requestAccess, denied → openSettings), (3) two-branch logic of requestAccessibilityAccess, (4) reference counting of monitoring (start/stop/counter), (5) protection against multiple clicks (isRequestInProgress)
- [X] T032 Validate against quickstart.md — check all 5 test scenarios: launch without microphone, first/repeated request, background update, floating window without microphone. Check SwiftLint compliance for all new/modified files
- [X] T038 Update unit tests in VerborraTests/Services/PermissionManagerTests.swift — add tests for US2a: (1) requestMicrophoneAccess at `.denied` calls showMicrophoneDeniedAlert, (2) NSAlert confirmation → openSystemSettings + terminate, (3) NSAlert cancel → no actions, (4) requestMicrophoneAccess at `.restricted` → opens System Settings directly (without NSAlert)
- [X] T039 Validate against the updated quickstart.md — check all 7 test scenarios including: (1) `.denied` → NSAlert → confirmation → quit + System Settings, (2) `.denied` → NSAlert → cancel → nothing, (3) restart after granting access → normal startup. Check SwiftLint compliance

---

## Dependencies and execution order

### Phase dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately. T001→T002 sequentially (T002 depends on types from T001)
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories. T003→T004,T005→T006,T007→T008→T009 (sequentially)
- **US1 (Phase 3)**: Depends on Phase 2 — single task (T010)
- **US2 (Phase 4)**: Depends on Phase 2. T011 first, then T012-T016
- **US4 (Phase 5)**: Depends on Phase 2. Can run in parallel with US2
- **US3 (Phase 6)**: Depends on Phase 2 + T011 (PermissionStatusView from US2). Can run in parallel with US4
- **US2a (Phase 6a)**: Depends on Phase 2 + T006 (requestMicrophoneAccess). T033→T034→T035, T036 in parallel, T037 after T035
- **Integration (Phase 7)**: Depends on completion of all USs including US2a. T026 ∥ T027, then T028
- **Tests (Phase 8)**: Depends on Phase 7 + Phase 6a. T030 → T031, T038, then T039

### User story dependencies

- **US1 (P1)**: Phase 2 only — independent of other USs
- **US2 (P1)**: Phase 2 only — independent of other USs. Creates PermissionStatusView (used in US3)
- **US2a (P1)**: Phase 2 + T006 (requestMicrophoneAccess). Modifies PermissionManager and PermissionStatusView
- **US4 (P1)**: Phase 2 only — independent of other USs
- **US3 (P2)**: Phase 2 + PermissionStatusView from US2 (T011)
- **US5**: Covered in T008 [US5], T009 [US5] (Phase 2)
- **US6**: Covered in T003 [US6], T008 [US6], T009 [US6], T011 [US6] (Phase 2 + Phase 4)

### Parallelization opportunities

- US1 ∥ US2 ∥ US4 (after Phase 2 — different files)
- T026 ∥ T027 (Phase 7 — different services)
- T030 → T031 (Phase 8 — tests depend on the mock)

---

## Parallel example: Phase 1 + Phase 2

```bash
# Phase 1 — sequentially (T002 uses types from T001):
T001 → T002

# Phase 2 — sequential chain:
T003 → T004, T005 (in parallel) → T006, T007 (in parallel) → T008 → T009
```

## Parallel example: after Phase 2

```bash
# Three user stories in parallel:
US1: T010 (VerborraApp.swift)
US2: T011 → T012, T013 (in parallel) → T014, T015 (in parallel) → T016
US4: T017 → T018 → T019, T020 (in parallel) → T021
```

---

## Implementation strategy

### MVP (US1 + US2 + US4 only)

1. Complete Phase 1: Setup (T001-T002)
2. Complete Phase 2: Foundational — PermissionManager (T003-T009)
3. Complete Phase 3: US1 — launch without microphone (T010)
4. Complete Phase 4: US2 — microphone request (T011-T016)
5. Complete Phase 5: US4 — floating window (T017-T021)
6. **STOP and VALIDATE**: Verify US1, US2, US4 independently

### Full delivery

7. Complete Phase 6a: US2a — `.denied` modal + quit (T033-T037) — P1, higher priority than US3
8. Complete Phase 6: US3 — Accessibility (T022-T025) — P2
9. Complete Phase 7: Integration and edge cases (T026-T028)
10. Complete Phase 8: Tests and validation (T030-T032, T038-T039)
11. Validate all scenarios from quickstart.md + SwiftLint

---

## Notes

- Unit tests are included in Phase 8 (constitution requirement, Principle 5: business logic MUST be covered by tests)
- [P] tasks = different files, no dependencies
- PermissionManager is a singleton (@Observable), created at startup, lives the entire application runtime
- The PermissionChecking protocol is in a separate file for dependency cleanliness and mocking in tests
- No new external dependencies — only macOS SDK APIs
- All USs are marked in spec.md with P1/P2 priorities
- US5 and US6 are covered by explicit [US5]/[US6] markers in Phase 2 and Phase 4 tasks
- Edge cases from spec.md are covered by tasks T026 (revocation during recording), T006/T007 (multiple clicks — isRequestInProgress), T028 (defensive fallback for unknown statuses and unavailable System Settings)
- SwiftLint check is included in final validation T039 (constitution, Principle 5)
- US2a (Phase 6a): New tasks T033-T037 for the microphone `.denied` scenario — NSAlert + quit + System Settings (FR-016–FR-020, R8–R10 from research.md)
- T038-T039: Updated tests and validation, including all 7 scenarios from quickstart.md
