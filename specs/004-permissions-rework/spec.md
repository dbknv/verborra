# Feature Specification: Rework of the Permission Request Process and Status Display

**Feature Branch**: `004-permissions-rework`
**Created**: 2026-03-14
**Status**: Draft
**Input**: Full rework of the permission request process (Microphone, Accessibility) and permission status display in the macOS application

## User Scenarios and Testing *(required)*

### US1 — Launching the application without microphone access (Priority: P1)

The user launches the application for the first time (or had previously revoked microphone access). The application detects that microphone access is missing and opens the onboarding window — even if onboarding had been completed previously. Onboarding always opens **from the first step**, and the user goes through all steps in full (welcome, API key setup, permissions, etc.).

**Why this priority**: The microphone is a required permission. Without it, the application cannot perform its main function (voice input). Blocking scenario.

**Independent test**: Revoke microphone access in System Settings → Privacy & Security → Microphone, restart the application — the onboarding window must open.

**Acceptance Scenarios**:

1. **Given** the application is launched and microphone access is missing, **When** the application starts, **Then** the onboarding window opens showing the microphone status and a "Request access" button
2. **Given** the application is launched and microphone access is granted, **When** the application starts, **Then** the application starts in normal mode without showing onboarding
3. **Given** the application is launched, **When** access is checked at startup, **Then** the Accessibility check at startup is **not** performed

---

### US2 — Microphone access request via onboarding/settings (Priority: P1)

The user sees the current microphone access status (granted/not granted). They click "Request access". macOS behavior depends on whether the permission was requested previously:

- **First request** (status `.notDetermined`): macOS shows a modal window with the question "Allow the application to access the microphone?". The user can allow or decline.
- **Repeated request** (status `.denied`): macOS does **not** show the modal window again. The application shows a modal window with instructions and, after confirmation, quits while opening System Settings (details — see US2a)
- **Restricted access** (status `.restricted`): Access is restricted at the system level (MDM, parental controls). The application opens System Settings, but the user may not be able to change the setting themselves

The application **never** invokes the system request on its own — only on an explicit button click. The "Request access" button works in both cases — the user does not need to know which exact mechanism will be used.

**Why this priority**: Key user flow — without it microphone access cannot be obtained.

**Independent test**: Open onboarding/settings, click "Request access" for the microphone — on the first request the macOS system dialog must appear; on a repeated one — System Settings must open.

**Acceptance Scenarios**:

1. **Given** microphone access is not granted and status is `.notDetermined` (not previously requested), **When** the user clicks "Request access", **Then** macOS shows the permission request modal
2. **Given** microphone access was previously denied (`.denied`), **When** the user clicks "Request access", **Then** the application shows a modal with restart instructions (see US2a)
3. **Given** microphone access is restricted (`.restricted`), **When** the user clicks "Request access", **Then** the application opens macOS System Settings on the Privacy & Security → Microphone page
4. **Given** the user granted/denied access in the OS modal window (at `.notDetermined`), **When** the modal closes, **Then** the application window automatically comes to the foreground above all windows
5. **Given** the onboarding/settings screen is open, **When** 1 second passes, **Then** microphone access status is refreshed (background polling every second)

---

### US2a — Repeated microphone access request at status `.denied` (Priority: P1)

The user previously denied microphone access (or revoked it in System Settings). On clicking "Request access", macOS **cannot** show the permission request modal again — this is a system limitation. In addition, macOS caches the permission status in process memory (TCC cache): even if the user changes the permission in System Settings, the application will not learn about it until restart.

Therefore, on clicking "Request access" at the `.denied` status, the application:
1. Shows a **modal window with instructions** explaining what will happen next
2. Modal text: *"The application will close → system settings will open → grant microphone access → reopen the application. These are macOS system limitations"*
3. The modal has a confirmation button "Got it, open settings"
4. After confirmation: the application opens System Settings on the Privacy & Security → Microphone page and **quits** itself
5. On the next launch, the application reads the current status from the TCC database

**Why a restart is necessary**: macOS caches the microphone access check result (`AVCaptureDevice.authorizationStatus`) in process memory. After the permission is changed in System Settings, calling this method keeps returning the old value. Restarting the application clears the cache, and the method reads the current status from the TCC database anew.

**Why this priority**: Without this scenario, a user who revoked access cannot restore it in a comprehensible way.

**Independent test**: Revoke microphone access in System Settings → open the application → click "Request access" → a modal with instructions must appear → after confirmation the application quits and System Settings opens.

**Acceptance Scenarios**:

1. **Given** microphone access has status `.denied`, **When** the user clicks "Request access", **Then** the application shows a modal with instructions about the need for a restart
2. **Given** the instructions modal is shown, **When** the user clicks the confirmation button, **Then** the application opens System Settings → Privacy & Security → Microphone and quits itself
3. **Given** the instructions modal is shown, **When** the user closes the window without confirmation (Escape / close button), **Then** the modal closes and the application stays in its current state
4. **Given** the application quit after redirecting to System Settings, **When** the user grants microphone access and restarts the application, **Then** the application detects the current `.authorized` status and starts in normal mode

---

### US3 — Accessibility access request via onboarding/settings (Priority: P2)

The user sees the current Accessibility access status (granted/not granted). They click "Request access". macOS behavior depends on whether the permission was requested previously:

- **First request**: macOS shows a modal suggesting to open System Settings to grant Accessibility access.
- **Repeated request** (access previously denied or revoked): macOS does **not** show the modal again. The application opens System Settings on the Privacy & Security → Accessibility page, where the user can manually enable/disable access.

Accessibility is optional access: without it the application still works, but the feature of pasting text into other applications is unavailable. The "Request access" button works in both cases — the user does not need to know which mechanism will be used.

**Why this priority**: Accessibility extends functionality (text pasting) but is not mandatory for the basic operation of the application.

**Independent test**: Open onboarding/settings, click "Request access" for Accessibility — on the first request the macOS system dialog must appear; on a repeated one — System Settings must open.

**Acceptance Scenarios**:

1. **Given** Accessibility access is not granted and was not previously requested, **When** the user clicks "Request access", **Then** macOS shows a modal suggesting to open System Settings
2. **Given** Accessibility access was previously requested (denied or revoked), **When** the user clicks "Request access", **Then** the application opens macOS System Settings on the Privacy & Security → Accessibility page (the macOS modal does not appear)
3. **Given** the user granted/denied access in the OS modal, **When** the modal closes, **Then** the application window automatically comes to the foreground
4. **Given** the user granted access via System Settings, **When** the user returns to the application (or background polling detects the change), **Then** the application window automatically comes to the foreground and the status updates
5. **Given** the onboarding/settings screen is open, **When** 1 second passes, **Then** the Accessibility access status is refreshed (background polling every second)

---

### US4 — Floating recording window: access check on open (Priority: P1)

When the floating recording window opens, a background check of Microphone and Accessibility statuses is performed. Depending on the result, the appropriate interface is displayed.

**Why this priority**: The floating window is the main working tool of the application. Incorrect behavior in the absence of access is critical.

**Independent test**: Revoke microphone access → open the floating recording window — the "No microphone access" state with a "Go to settings" button must be displayed.

**Acceptance Scenarios**:

1. **Given** microphone access is granted, **When** the user opens the floating recording window, **Then** the recording interface is displayed
2. **Given** microphone access is missing, **When** the user opens the floating recording window, **Then** the "No microphone access" state with a "Go to settings" button is displayed
3. **Given** microphone access is missing and the floating window shows "No access", **When** the user clicks "Go to settings", **Then** **application settings** open (not OS System Settings), and the floating window closes
4. **Given** the floating window is open and shows "No microphone access", **When** the user grants access via the system dialog (first request from application settings), **Then** after restarting the floating window the recording interface is displayed. Note: automatic microphone status update on external changes in System Settings is not possible due to the TCC cache — an application restart is required
5. **Given** Accessibility access is granted, **When** the user opens the floating recording window, **Then** the "Paste text" button is active
6. **Given** Accessibility access is missing, **When** the user opens the floating recording window, **Then** the "Paste text" button is in the `disabled` state

---

### US5 — Background status update on status screens (Priority: P2)

On screens where access status is displayed (onboarding, settings), a background poll is performed every second. If the user changes permissions in macOS system settings — the UI instantly reflects the current status. During normal application operation (with no status screens open) background checks are **not** performed.

**Why this priority**: Ensures the displayed status stays current and the correct reaction to access revocation.

**Independent test**: Open settings → go to System Settings and grant/revoke access → return to the application — the status must update within 1 second.

**Acceptance Scenarios**:

1. **Given** the onboarding/settings screen is open and microphone access is not granted (status `.notDetermined`), **When** the user grants/denies access via the macOS system dialog, **Then** the UI updates within 1 second and shows the current status
2. **Given** the onboarding/settings screen is open and Accessibility access is not granted, **When** the user grants/revokes access via macOS System Settings, **Then** the UI updates within 1 second and shows the current status
3. **Given** the onboarding/settings screen is open and microphone access is changed in macOS System Settings (external change), **When** background polling checks the status, **Then** the change is **not detected** due to the TCC cache — the current microphone status will be obtained only after restarting the application
4. **Given** no status display screens are open, **When** the application runs in normal mode, **Then** background status checking is **not** performed (resource saving)

---

### US6 — Unified reusable access request process (Priority: P2)

The access request process code (status check, permission request, UI display) is unified across all entry points: onboarding, settings, floating window, any future screens. Duplication of logic is avoided.

**Why this priority**: Ensures uniform behavior and simplifies maintenance. Eliminates logic drift between screens.

**Independent test**: The access request process works identically from onboarding, settings, and the floating window — a single code base, a single behavior.

**Acceptance Scenarios**:

1. **Given** the access request process is implemented as a single component, **When** it is used in onboarding, settings, or another screen, **Then** the behavior is identical across all entry points
2. **Given** the unified access management component, **When** the check/request logic changes, **Then** the change automatically applies to all screens

---

### Edge cases

- What happens if the user revokes microphone access **during recording**? → Recording must stop, the user must see an error message. Note: due to the TCC cache, polling `AVCaptureDevice.authorizationStatus` will not detect an external revocation — detection happens via an AVAudioEngine error on the next attempt to continue recording
- What happens if the user clicks "Request access" several times in quick succession? → Repeated clicks must be ignored while the system dialog or the instructions modal is shown
- What happens on a status check error (system API failure)? → The status is displayed as "Undefined", and the user is asked to restart the application
- What happens if System Settings is unavailable when trying to open the Privacy page? → The application shows a textual instruction on how to grant access manually
- What happens if the application starts with microphone access, and then access is revoked before opening the floating window? → Due to the TCC cache, the application may not learn about the revocation until restart. On restart the status updates and the application opens onboarding
- What happens if the user confirmed the modal (US2a) but did not grant access in System Settings and launched the application again? → The application will detect `.denied` status and open onboarding again; on a repeated click of "Request access" it will show the instructions modal
- What happens if microphone access has status `.restricted` (MDM, parental controls)? → The application opens System Settings, but the user may not be able to change the setting. A corresponding message is shown

## Requirements *(required)*

### Functional requirements

- **FR-001**: The system MUST check the microphone access status on every application launch
- **FR-002**: The system MUST open the onboarding window **from the first step** (full flow) at startup if microphone access is missing, regardless of whether onboarding was previously completed
- **FR-003**: The system MUST NOT check Accessibility status at application startup
- **FR-004**: The system MUST NOT invoke a system access request (Microphone / Accessibility) without an explicit user click of the "Request access" button
- **FR-004a**: When "Request access" is clicked, if the permission has not been requested before (status undefined), the system MUST initiate showing the OS modal
- **FR-004b**: When "Request access" is clicked, if the permission was previously denied or revoked: for Accessibility — the system MUST open macOS System Settings on the corresponding Privacy & Security page; for Microphone at `.denied` — FR-016–FR-019 apply (modal with instructions + quit)
- **FR-004c**: The "Request access" button MUST work uniformly for the user — automatically determining the right mechanism (modal or System Settings) without additional user action
- **FR-005**: The system MUST display the current microphone and Accessibility access status **separately** on the onboarding and settings screens
- **FR-006**: The system MUST perform background status polling every second on screens where the status is displayed (onboarding, settings). Note: for the microphone, polling detects changes only on the first request (`.notDetermined` → system dialog); external changes in System Settings are not detected until restart (TCC cache). For Accessibility, polling works without restrictions
- **FR-007**: The system MUST NOT perform background status polling during normal application operation (outside status display screens)
- **FR-008**: The system MUST correctly reflect both granting and revoking access when permissions change in macOS System Settings
- **FR-009**: The system MUST perform a background check of Microphone and Accessibility status when the floating recording window opens
- **FR-010**: The system MUST show the recording interface in the floating window if microphone access is granted
- **FR-011**: The system MUST show the "No microphone access" state with a "Go to settings" button in the floating window if microphone access is missing
- **FR-011a**: The "Go to settings" button in the floating window MUST open **application settings** (not OS System Settings), and the floating window must close
- **FR-011b**: The floating window MUST automatically refresh access status and switch to the recording interface upon granting microphone access (without the user having to close/open the window)
- **FR-012**: The system MUST disable the "Paste text" button (`disabled`) in the floating window if Accessibility access is missing
- **FR-013**: The system MUST enable the "Paste text" button in the floating window if Accessibility access is granted
- **FR-014**: The system MUST automatically bring the application window to the foreground after the user action in the OS modal when requesting access, as well as on return from System Settings (detected via background status polling)
- **FR-015**: The access request process MUST be implemented as a single reusable component for all entry points (onboarding, settings, floating window, other screens)
- **FR-016**: When "Request access" is clicked for the microphone at status `.denied`, the system MUST show a modal with instructions explaining the need to restart the application
- **FR-017**: The modal (FR-016) MUST contain the text: *"The application will close → system settings will open → grant microphone access → reopen the application. These are macOS system limitations"* and the confirmation button "Got it, open settings"
- **FR-018**: After confirmation in the modal (FR-017), the system MUST open System Settings → Privacy & Security → Microphone and **quit the application**, so that on the next launch the current status is read from the TCC database
- **FR-019**: The modal (FR-016) MUST allow the user to cancel the action (close without confirmation) — in which case the application stays in its current state
- **FR-020**: The system MUST distinguish four microphone access states: `.notDetermined` (not requested), `.restricted` (restricted by the system), `.denied` (declined/revoked by the user), `.authorized` (granted)

### Key entities

- **PermissionType**: The type of permission — Microphone (required) or Accessibility (optional)
- **PermissionStatus**: The current permission status — `.notDetermined` (not requested), `.restricted` (restricted by the system), `.denied` (declined/revoked), `.authorized` (granted)
- **PermissionManager**: A single permission manager providing status checks, requests, and background monitoring

## Success criteria *(required)*

### Measurable outcomes

- **SC-001**: The permission status on the onboarding/settings screens updates within 1 second: for the microphone — after a response in the system dialog (first request); for Accessibility — after any change in System Settings. External changes to microphone status via System Settings are not detected until application restart (TCC cache limitation)
- **SC-002**: If microphone access is missing, the application always opens onboarding at startup — 100% of cases
- **SC-003**: A system access request never appears without an explicit user click of the button — 0 unauthorized requests
- **SC-004**: The application window returns to the foreground after the action in the system dialog in 100% of cases
- **SC-005**: Background status checking does not consume resources when no status display screen is open
- **SC-006**: The access request process code is used from a single source across all entry points (onboarding, settings, floating window) — 0 logic duplication

## Clarifications

### Session 2026-03-14

- Q: On launch without microphone — show the full onboarding or only the permissions step? → A: Onboarding always opens from the first step; the user goes through all steps in full
- Q: Floating window — auto-refresh on status change? Where does the "Go to settings" button lead? → A: Auto-refresh enabled. The button opens application settings (not System Settings); the floating window closes at the same time

### Session 2026-03-15

- Q: How to handle the microphone `.denied` status given the TCC cache? → A: Show a modal with instructions, then quit the application and open System Settings. The TCC cache (`AVCaptureDevice.authorizationStatus`) does not refresh without restart — this is a macOS system limitation
- All four microphone states added: `.notDetermined`, `.restricted`, `.denied`, `.authorized`
- US2a added — the repeated-request scenario at `.denied` with a modal and a restart
- Q: Keep or remove microphone background polling given the TCC cache? → A: Keep. Polling works on the first access request (`.notDetermined` → system dialog), which is a valid scenario. For external changes in System Settings polling does not help due to the TCC cache — this is documented
- Q: Confirmation button text in the US2a modal? → A: "Got it, open settings"

## Assumptions

- The application runs on macOS 15+ (Sequoia and newer) where the corresponding APIs for checking Microphone and Accessibility are available
- For the microphone `.denied` status, the only way to grant access is via macOS System Settings (a repeated system dialog is not possible)
- **TCC cache**: macOS (`AVCaptureDevice.authorizationStatus`) caches microphone access status in process memory. After changing the permission in System Settings, the method keeps returning the old value until the application is restarted. This is a macOS system limitation that cannot be bypassed programmatically — therefore the `.denied` scenario requires restarting the application
- For Accessibility, `AXIsProcessTrusted` / `AXIsProcessTrustedWithOptions` are used — standard macOS APIs (not subject to TCC caching, status updates without restart)
- The user uses standard macOS system settings (not customized MDM policies)
- The `.restricted` status (MDM, parental controls) is a rare scenario; the application handles it but does not specifically optimize UX for this case
