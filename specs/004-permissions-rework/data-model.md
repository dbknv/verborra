# Data Model: Permission Request Process Rework

**Feature**: 004-permissions-rework
**Date**: 2026-03-14

## Entities

### PermissionType

The type of permission supported by the application.

| Value | Description | Requirement |
|----------|----------|----------------|
| `microphone` | Microphone access for voice recording | Required — without it the application does not work |
| `accessibility` | Accessibility API access for pasting text | Optional — works without it, but pasting is unavailable |

**Attributes**:
- `isRequired: Bool` — whether the permission is required for the application to work
- `systemSettingsURL: String` — URL to open the corresponding System Settings page

---

### PermissionStatus

Current status of a specific permission.

| Value | Description | Available actions |
|----------|----------|--------------------|
| `notDetermined` | The permission has not yet been requested | Can show the system modal window |
| `granted` | The permission has been granted | Functionality is available |
| `denied` | The permission was denied by the user | Only switching to System Settings |
| `restricted` | The permission is restricted by system policy | Only switching to System Settings |

**Relationships**: Each `PermissionType` has one `PermissionStatus` at any given time.

**State transitions**:

```text
                    ┌─────────────────┐
                    │  notDetermined  │
                    └────────┬────────┘
                             │
                    User clicked
                    "Request access"
                             │
                    ┌────────┴────────┐
                    │   OS showed     │
                    │   modal window  │
                    └────────┬────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
            Allowed                    Denied
                │                         │
        ┌───────┴───────┐         ┌───────┴───────┐
        │    granted    │         │    denied     │
        └───────┬───────┘         └───────┬───────┘
                │                         │
            User                       User
            revoked in                 granted in
            System Settings            System Settings
                │                         │
        ┌───────┴───────┐         ┌───────┴───────┐
        │    denied     │         │    granted    │
        └───────────────┘         └───────────────┘
```

**Note**: The transition from `denied` back to `granted` is possible **only** via System Settings on macOS. The application cannot programmatically change the status from `.denied` to `.granted`.

**TCC cache (microphone only)**: `AVCaptureDevice.authorizationStatus(for: .audio)` caches the status in process memory. Transitions `denied ↔ granted` via System Settings **are not detected** until the application is restarted. For Accessibility (`AXIsProcessTrusted()`) there is no caching — transitions are detected by polling in real time.

---

### PermissionManager

A single manager that handles permission checking and requesting.

**Properties (observable)**:
- `microphoneStatus: PermissionStatus` — current microphone status
- `accessibilityStatus: PermissionStatus` — current Accessibility status

**Internal state**:
- `monitoringCount: Int` — counter of active monitoring subscribers
- `pollingTimer: Timer?` — background polling timer (1 second)

**Operations**:
- `checkMicrophoneStatus()` → updates `microphoneStatus` without side effects
- `checkAccessibilityStatus()` → updates `accessibilityStatus` without side effects
- `requestMicrophoneAccess()` → FR-004a/FR-004b: system dialog (`.notDetermined`), modal with instructions + quit (`.denied`), or System Settings (`.restricted`)
- `requestAccessibilityAccess()` → FR-004a/FR-004b: modal or System Settings
- `startMonitoring()` → increment counter, start the timer if first
- `stopMonitoring()` → decrement counter, stop the timer if last

**Lifecycle**: Singleton, created at application startup, lives for the entire application runtime.

---

## Relationships with Existing Entities

| Existing entity | Interaction with PermissionManager |
|---|---|
| `OnboardingViewModel` | Reads `microphoneStatus`, `accessibilityStatus`; calls `requestMicrophoneAccess()`, `requestAccessibilityAccess()` |
| `SettingsViewModel` | Reads `microphoneStatus`, `accessibilityStatus`; calls `requestMicrophoneAccess()`, `requestAccessibilityAccess()` |
| `RecordingViewModel` | Reads `microphoneStatus`, `accessibilityStatus` to determine button availability |
| `AudioCaptureService` | Reads `microphoneStatus` before starting recording |
| `PasteService` | Reads `accessibilityStatus` before pasting text |
| `AppDelegate` | Reads `microphoneStatus` at startup to decide whether to show onboarding |

## Data Storage

This feature does **not** introduce new storage. Permission statuses are runtime state obtained from macOS system APIs on every check. No persistence is required — macOS stores permissions in its own TCC (Transparency, Consent, and Control) database.
