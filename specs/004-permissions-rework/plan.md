# Implementation Plan: Permission Request Process Rework

**Branch**: `004-permissions-rework` | **Date**: 2026-03-15 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/004-permissions-rework/spec.md`

## Brief Description

Rework of the process for requesting and displaying macOS permissions (Microphone, Accessibility). Key changes:
- Differentiation of the four microphone states (`.notDetermined`, `.restricted`, `.denied`, `.authorized`)
- Modal window with instructions for the microphone `.denied` status (quit + opening System Settings due to the TCC cache)
- Background status polling that accounts for TCC cache limitations for the microphone
- A single reusable component for permission requests across all entry points

## Technical Context

**Language/Version**: Swift 5.9+ (Xcode 15+)
**Primary Dependencies**: SwiftUI, AppKit (NSPanel, NSWindow, NSAlert), AVFoundation (AVCaptureDevice), Accessibility API (AXIsProcessTrusted)
**Storage**: UserDefaults / @AppStorage (settings), macOS Keychain (API key)
**Testing**: XCTest / Swift Testing
**Target Platform**: macOS 15+ (Sequoia)
**Project Type**: Native macOS application (Menu Bar app)
**Performance Goals**: Polling every 1 second, modal window opening time < 100ms
**Constraints**: Microphone TCC cache (AVCaptureDevice.authorizationStatus) does not refresh without restarting the application
**Scale/Scope**: Single-user desktop application

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Comment |
|---------|--------|-------------|
| 1. Native macOS experience | Pass | SwiftUI + NSAlert for the modal window. System Settings via URL scheme. NSPanel for overlay. |
| 2. Swift-first development | Pass | All code in Swift 5.9+, @Observable, MVVM. No new dependencies. |
| 3. Minimalism and simplicity | Pass | Changes affect existing components. The modal window is the only new UI element. |
| 4. Security and privacy | Pass | Correct handling of permission revocation (FR-001, FR-016-020). No new entitlements. |
| 5. Code quality and testing | Pass | The PermissionChecking protocol enables mocking. Unit tests for the state machine. |

**Result**: All gates passed. No violations.

## Project Structure

### Documentation (this feature)

```text
specs/004-permissions-rework/
├── plan.md              # This file
├── research.md          # Phase 0: research on TCC cache, NSAlert
├── data-model.md        # Phase 1: data model (enums, state machine)
├── quickstart.md        # Phase 1: quickstart
└── tasks.md             # Phase 2: tasks (created by /speckit.tasks)
```

### Source code (modified files)

```text
Verborra/
├── Services/
│   ├── PermissionChecking.swift     # Update: PermissionStatus, PermissionChecking protocol
│   └── PermissionManager.swift      # Update: .denied logic (modal window + quit), 4 states
├── Views/
│   ├── Components/
│   │   └── PermissionStatusView.swift   # Update: button behavior differs by status
│   ├── OverlayContentView.swift         # Update: "No access" with a settings button
│   └── Onboarding/
│       └── PermissionsStep.swift        # Update: display 4 statuses
├── ViewModels/
│   ├── OnboardingViewModel.swift        # Update: onboarding logic for .denied
│   └── SettingsViewModel.swift          # Minimal changes
├── VerborraApp.swift                     # Update: shouldShowOnboarding logic
└── Localizable.xcstrings               # New localization strings
```

**Structure Decision**: The existing MVVM structure is preserved. No new modules or directories are required — all changes fit within existing files and components.

## Complexity Tracking

No Constitution violations detected — section is empty.
