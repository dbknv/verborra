# Quickstart: Permission Request Process Rework

**Feature**: 004-permissions-rework
**Date**: 2026-03-15 (updated)

## Overview

The feature reworks the permission management process (Microphone, Accessibility) in Verborra — a macOS voice input application. Main changes:
- Unified `PermissionManager` distinguishing the four microphone states (`.notDetermined`, `.restricted`, `.denied`, `.authorized`)
- Modal window (NSAlert) with instructions for the microphone `.denied` status: quit + opening System Settings
- TCC cache awareness: polling only detects microphone changes for `.notDetermined`; external changes require a restart

## Key Files

### Existing files (modification)
- `Verborra/Services/PermissionManager.swift` — add `.denied` logic (NSAlert + quit), three behavior branches
- `Verborra/Services/PermissionChecking.swift` — no changes (PermissionStatus already contains 4 values)
- `Verborra/Views/Components/PermissionStatusView.swift` — update button behavior for microphone `.denied`
- `Verborra/Views/OverlayContentView.swift` — "No access" state with "Go to settings" button
- `Verborra/Views/Onboarding/PermissionsStep.swift` — display 4 statuses
- `Verborra/VerborraApp.swift` — shouldShowOnboarding logic for `.denied`
- `Verborra/ViewModels/OnboardingViewModel.swift` — adaptation for the `.denied` scenario
- `Verborra/Localizable.xcstrings` — new localization strings

## Architecture (brief)

```text
┌─────────────────────────────────────────────────┐
│              PermissionManager                  │
│  (@Observable, singleton)                       │
│                                                 │
│  microphoneStatus: PermissionStatus             │
│  accessibilityStatus: PermissionStatus          │
│                                                 │
│  requestMicrophoneAccess()                      │
│    ├── .notDetermined → AVCaptureDevice.request │
│    ├── .denied → NSAlert + quit + System Settings│
│    └── .restricted → System Settings            │
│                                                 │
│  requestAccessibilityAccess()                   │
│  startMonitoring() / stopMonitoring()           │
└────────────┬────────────────────────────────────┘
             │ (used by)
     ┌───────┼───────────┬──────────────┐
     │       │           │              │
Onboarding Settings  Recording    Services
 ViewModel  ViewModel  ViewModel   (Audio, Paste)
     │       │           │
     └───────┼───────────┘
             │
   PermissionStatusView
   (reusable UI)
```

### Microphone `.denied` flow (US2a)

```text
"Request access" button (status == .denied)
    │
    ▼
NSAlert: "The application will close → system settings will open → grant access → restart"
    │
    ├── "Got it, open settings"
    │       │
    │       ▼
    │   NSWorkspace.open(System Settings URL)
    │       │
    │       ▼ (0.5s delay)
    │   NSApp.terminate(nil)
    │
    └── "Cancel"
            │
            ▼
        Nothing happens
```

## How to Test

1. **Microphone not granted at startup**: Revoke access in System Settings → restart the application → onboarding must open at the first step
2. **Microphone request (first time)**: Reset permissions via `tccutil reset Microphone <bundle-id>` → click "Request access" → a macOS modal window appears
3. **Microphone request (repeated, `.denied`)**: After denial, click "Request access" → an NSAlert with instructions appears → "Got it, open settings" → System Settings opens, the application quits
4. **Cancel the modal**: In the NSAlert, click "Cancel" → the dialog closes, the application keeps running
5. **Restart after granting access**: Grant access in System Settings → start the application → the application starts in normal mode
6. **Background update (Accessibility)**: Open settings → toggle Accessibility in System Settings → status updates within 1 second
7. **Floating window without microphone**: Revoke the microphone → open the recording window → "No access" + "Go to settings" button → application settings open, the floating window closes

## Dependencies

No new external dependencies. Only macOS SDK APIs are used:
- `AVFoundation` (AVCaptureDevice) — microphone check/request
- `ApplicationServices` (AXIsProcessTrusted) — Accessibility check/request
- `AppKit` (NSWorkspace, NSAlert, NSApp.terminate) — System Settings, modal window, termination
- `Observation` framework — reactive UI updates

## Important Constraints

- **TCC cache**: `AVCaptureDevice.authorizationStatus` caches the microphone status in process memory. External changes (via System Settings) are not detected until restart. That is why `.denied` requires a quit.
- **No Accessibility cache**: `AXIsProcessTrusted()` always returns the current value — polling works.
- **Polling only when status screens are open**: the Timer starts/stops following a reference counting pattern.
