# Research: Permission Request Process Rework

**Feature**: 004-permissions-rework
**Date**: 2026-03-14

## R1: Checking microphone status without invoking the system dialog

**Decision**: Use `AVCaptureDevice.authorizationStatus(for: .audio)` — it returns the current status without side effects.

**Rationale**: This API is read-only and does not invoke system dialogs. It returns one of: `.notDetermined`, `.authorized`, `.denied`, `.restricted`. It is safe to call in the background at any frequency.

**Alternatives considered**:
- `AVAudioSession` — iOS-only, not available on macOS
- `AVAudioApplication.requestRecordPermission()` — invokes the system dialog, not suitable for background checks

---

## R2: Checking Accessibility status without invoking the system dialog

**Decision**: Use `AXIsProcessTrusted()` — it returns a `Bool` without side effects.

**Rationale**: Unlike `AXIsProcessTrustedWithOptions(options)` with `kAXTrustedCheckOptionPrompt: true`, the call `AXIsProcessTrusted()` never shows a system dialog. It is safe for periodic polling.

**Alternatives considered**:
- `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: false` — equivalent to `AXIsProcessTrusted()` but more verbose
- Subscribing to status-change notifications — macOS does not provide such a notification for Accessibility; polling is required

---

## R3: Microphone permission request mechanism (first vs repeated request)

**Decision**: Two-branch logic based on `authorizationStatus`:

| Status | Action | Result |
|--------|----------|-----------|
| `.notDetermined` | `AVCaptureDevice.requestAccess(for: .audio)` | macOS shows a modal window |
| `.denied` / `.restricted` | `NSWorkspace.shared.open(URL)` | Opens System Settings → Privacy → Microphone |
| `.authorized` | Nothing | Access already granted |

**Rationale**: macOS allows the permission-request modal to be shown only once (when the status is `.notDetermined`). After the user denies it, the status moves to `.denied`, and a repeated call to `requestAccess` does not show the dialog — it returns `false` immediately. The only way to change `.denied` → `.authorized` is via System Settings.

**System Settings URL**: `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`

---

## R4: Accessibility permission request mechanism (first vs repeated request)

**Decision**: Two-branch logic:

| State | Action | Result |
|-----------|----------|-----------|
| Not previously requested | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` | macOS shows a dialog offering to open System Settings |
| Previously denied/revoked | `NSWorkspace.shared.open(URL)` | Opens System Settings → Privacy → Accessibility |

**Rationale**: Unlike the microphone, the Accessibility API has no explicit `.notDetermined` status. The function `AXIsProcessTrustedWithOptions` with prompt = true always shows the system dialog if the application is not in the list. However, if the application is already in the list (but disabled), a repeated call does not show the dialog. Therefore the safer approach is: if `AXIsProcessTrusted() == false`, call `AXIsProcessTrustedWithOptions` (will show the dialog if the application is not in the list) or open System Settings directly.

**System Settings URL**: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`

**Practical solution**: Always use `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` — macOS itself decides whether to show the dialog. If the application is already in the Accessibility list (but disabled), the dialog does not appear — in that case, additionally open System Settings.

---

## R5: Background status polling — managing the Timer lifecycle

**Decision**: A "subscriber counter" (reference counting) pattern in PermissionManager.

**Rationale**: Several screens may simultaneously display the status (unlikely, but possible). The counter guarantees that the timer starts on the first subscriber and stops on the last. This satisfies FR-007 (no polling outside status screens).

**Implementation**:
- `startMonitoring()` → increment counter, if counter == 1 → start Timer (1 second)
- `stopMonitoring()` → decrement counter, if counter == 0 → stop Timer
- The Timer calls `checkAllStatuses()` — updates published properties

**Alternatives considered**:
- Combine `Timer.publish` — less controllable lifecycle, harder to stop/resume
- `DispatchSource.makeTimerSource` — low-level, overkill for the task
- `Task.sleep` loop — inconvenient for cancellation and restart

---

## R6: Bringing the window to the foreground after a status change

**Decision**: When a status change is detected by polling — call `NSApp.activate(ignoringOtherApps: true)`.

**Rationale**: After the user grants/revokes access in System Settings, macOS does not automatically notify the application. Polling detects the change → PermissionManager notifies the UI → the UI (or AppDelegate) activates the window.

**Implementation**: When PermissionManager detects a status change from `.denied`/`.notDetermined` to `.authorized` (or vice versa), it publishes the change via `@Observable` properties. The UI layer reacts via `.onChange(of:)` and triggers window activation. This separates responsibilities: PermissionManager knows nothing about windows; the UI layer decides when to activate.

---

## R7: Absence of third-party dependencies

**Decision**: No new dependencies are required.

**Rationale**: All required APIs are provided by the macOS SDK:
- `AVFoundation` — microphone access check/request
- `ApplicationServices` / `AppKit` — `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions()`
- `AppKit` — `NSWorkspace.shared.open()` for opening System Settings
- `Foundation` — `Timer` for periodic polling
- `Observation` — `@Observable` for reactive UI updates

The constitution requires minimizing third-party dependencies (Principle 2).

---

## R8: Microphone TCC cache — behavior and consequences

**Decision**: For the microphone `.denied` status, the application must terminate (quit) after opening System Settings, so that on the next launch it reads the current status from the TCC database.

**Rationale**: macOS caches the result of `AVCaptureDevice.authorizationStatus(for: .audio)` in the process memory. This is an internal cache of the TCC (Transparency, Consent, and Control) subsystem. After the user changes the permission in System Settings → Privacy & Security → Microphone, the `authorizationStatus` method keeps returning the old value until the process restarts. Restarting the application clears the cache, and the method re-reads the current status from the TCC database (`/Library/Application Support/com.apple.TCC/TCC.db`).

**Important**: This cache does **not** affect:
- The first request (`.notDetermined` → the `requestAccess` callback returns the current result)
- Accessibility (`AXIsProcessTrusted()` does not cache status — it always reads the current value)

**Consequences for polling**:
- Polling `AVCaptureDevice.authorizationStatus` is only useful for the transition `.notDetermined` → `.authorized`/`.denied` (via the system dialog)
- Polling will **not** detect external changes to the microphone status via System Settings
- Polling `AXIsProcessTrusted()` works without restrictions for Accessibility

**Alternatives considered**:
- `DistributedNotificationCenter` to track TCC changes — macOS does not publish such notifications
- `kTCCServiceMicrophone` via private TCC.framework APIs — disallowed by the App Store, unreliable
- Periodic restarts of `AVCaptureDevice.requestAccess` — does not solve the problem, since the callback is not invoked again for `.denied`

---

## R9: Modal window for the microphone `.denied` scenario

**Decision**: Use `NSAlert` to display the modal window with instructions.

**Rationale**: `NSAlert` is the standard macOS component for modal dialogs with information and confirmation. It conforms to the Human Interface Guidelines (Principle 1). It does not require creating a separate NSWindow or SwiftUI window.

**Implementation**:
```swift
let alert = NSAlert()
alert.messageText = "Restart required"
alert.informativeText = "The application will close → system settings will open → grant microphone access → reopen the application. These are macOS system limitations"
alert.alertStyle = .informational
alert.addButton(withTitle: "Got it, open settings")
alert.addButton(withTitle: "Cancel")
```

**Button behavior**:
- "Got it, open settings" (`.alertFirstButtonReturn`) → open System Settings + `NSApp.terminate(nil)`
- "Cancel" (`.alertSecondButtonReturn`) → close the dialog, do nothing

**Alternatives considered**:
- SwiftUI `.alert()` modifier — requires binding to a specific View, harder to invoke from PermissionManager
- SwiftUI `.confirmationDialog()` — action sheet style, does not match the seriousness of the action (application quit)
- Custom NSWindow — overkill for a simple dialog with two buttons

---

## R10: Application termination — NSApp.terminate vs exit()

**Decision**: Use `NSApp.terminate(nil)` for a clean shutdown.

**Rationale**: `NSApp.terminate(nil)` performs the full macOS application termination cycle:
- Calls the delegate's `applicationShouldTerminate(_:)`
- Allows state saving (if necessary)
- Properly closes all windows

**Sequence on modal confirmation**:
1. Open System Settings via `NSWorkspace.shared.open(URL)`
2. After a short delay (0.5s) call `NSApp.terminate(nil)` — the delay is needed so that `NSWorkspace.open` has time to handle the request before the process terminates

**Alternatives considered**:
- `exit(0)` — immediate termination without delegate calls, may cause data loss
- `fatalError()` — generates a crash report, unacceptable for a normal scenario
- `NSApp.terminate(nil)` without a delay — may interrupt opening of System Settings
