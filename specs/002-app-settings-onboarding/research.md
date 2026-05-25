# Research: App settings and onboarding

**Date**: 2026-03-07 (updated)
**Feature**: 002-app-settings-onboarding

---

## RES-001: Non-closable onboarding window (FR-013)

**Decision**: Remove `.closable` from the NSWindow `styleMask` and override `performClose(_:)` to block Cmd+W.

**Implementation**:
```swift
// styleMask without .closable
super.init(
    contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
    styleMask: [.titled],
    backing: .buffered,
    defer: true
)

// Block Cmd+W
override func performClose(_ sender: Any?) {
    // Intentionally do not call super — the window does not close
}
```

**Alternatives**: NSWindowDelegate.windowShouldClose — the button stays visible, less reliable.

---

## RES-002: Blocking settings and overlay during onboarding (FR-005)

**Decision**: Use `isOnboardingCompleted` from `AppSettings` (@AppStorage) for checks in menu items and in `RecordingViewModel.toggleOverlay()`.

**Current state**: Already implemented — `guard settings.isOnboardingCompleted else { return }` in `toggleOverlay()`.

---

## RES-003: "Back" navigation in onboarding (FR-004)

**Decision**: Common navigation bar in the OnboardingWindow container with "Back"/"Next"/"Finish" buttons.

**Button rules**:
- Welcome: only "Next"
- Permissions: "Back" + "Next" (disabled without Microphone)
- MicrophoneTest: "Back" + "Next"
- Completion: "Back" + "Finish"

---

## RES-004: Recording hotkey — local vs global (FR-024)

**Decision**: Use a local NSEvent handler in KeyCaptureView, not KeyboardShortcuts

**Rationale**:
- KeyboardShortcuts registers **global** hotkeys via the Carbon API (RegisterEventHotKey)
- macOS global hotkeys **require at least one modifier** (Cmd, Option, Control, Shift) — bare Space is not possible
- The recording hotkey works **only when the floating window is open** — this matches the spec
- The current implementation via `KeyCaptureView` (NSView subclass, `keyDown(with:)`) for intercepting Space (keyCode 49) is the right approach

**Customization implementation**:
- Store `recordingKeyCode: UInt16` and `recordingModifiers: UInt` in AppSettings (UserDefaults)
- In `RecordingViewModel.handleKeyDown()` compare the event with the saved values
- Default: Space (keyCode 49, modifiers = 0)
- In the "Hotkeys" tab — a custom recorder view to capture the new hotkey

**Rejected alternatives**:
- KeyboardShortcuts for recording — does not support bare Space, registers globally
- NSEvent.addLocalMonitorForEvents — possible, but KeyCaptureView already works

---

## RES-005: Preventing sidebar collapse (FR-015)

**Decision**: `.toolbar(removing: .sidebarToggle)` (macOS 14+) + `.navigationSplitViewStyle(.prominentDetail)`

**Rationale**:
- macOS 14 added the `.toolbar(removing: .sidebarToggle)` modifier — removes the collapse button
- The project targets macOS 14+, the API is available
- `.prominentDetail` is already used

**Inset from traffic lights**:
- NavigationSplitView + List in the sidebar automatically handles the inset from traffic lights
- If an additional inset is needed — `.safeAreaInset(edge: .top)` on the List

**Rejected alternatives**:
- NSWindow.titlebarAppearsTransparent — changes the visuals of the whole window
- Custom sidebar (VStack) — loss of native style

---

## RES-006: API identifiers for GPT 5.x models

**Decision**: No changes required — already implemented

**Current state** (`LLMModel.swift`):
| Model | API ID | Price (input/output per 1M tokens) |
|-------|--------|------------------------------------|
| GPT-5 Nano | `gpt-5-nano` | — |
| GPT-5 Mini | `gpt-5-mini` | $0.25 / $2.00 |
| GPT-5.1 | `gpt-5.1` | $1.25 / $10.00 |
| GPT-5.2 | `gpt-5.2` | $1.75 / $14.00 |
| GPT-5.3 | `gpt-5.3` | $2.50 / $20.00 |

All use the standard Chat Completions API. The request format is identical to existing models.

---

## RES-007: Floating window positioning (FR-033)

**Decision**: Compute via `NSScreen.visibleFrame`, taking Dock and Menu Bar into account

**Algorithm**:
```swift
func positionOnScreen() {
    // Screen with the key window (for multi-monitor)
    let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
    guard let visibleFrame = screen?.visibleFrame else { return }

    let panelSize = Self.fixedSize

    // Horizontal center
    let x = visibleFrame.origin.x + (visibleFrame.width - panelSize.width) / 2

    // 10% from the bottom of the visible area
    let y = visibleFrame.origin.y + visibleFrame.height * 0.10

    setFrame(NSRect(origin: NSPoint(x: x, y: y), size: panelSize), display: true)
}
```

**Fixed size**:
- A single fixed size (no compact/expanded switching)
- Remove `resizeToCompact()` and `resizeToExpanded()`
- In ResultView — scroll inside the fixed window for long text
- Size is set via `NSSize` and does not change: `isMovableByWindowBackground = true` (moving is allowed — the spec only forbids resizing)
- **Style mask**: add `.titled` for standard chrome or keep `.borderless` — to be decided during implementation

**Rejected alternatives**:
- `NSScreen.main` — does not account for multi-monitor
- Absolute coordinates — does not adapt to resolution

---

## RES-008: Hotkey conflict detection (FR-025)

**Decision**: Check in SettingsViewModel when saving the hotkey

**Approach**:
- Overlay hotkey — global, stored in KeyboardShortcuts (with a modifier)
- Recording hotkey — local, stored in UserDefaults (may be without a modifier)
- Conflict: identical keyCode + modifierFlags
- On conflict: inline warning in the UI, the hotkey is not saved

**Implementation**:
```swift
func hasHotkeyConflict(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
    guard let overlayShortcut = KeyboardShortcuts.getShortcut(for: .toggleOverlay) else {
        return false
    }
    return overlayShortcut.carbonKeyCode == keyCode
        && overlayShortcut.carbonModifiers == modifiers.carbonFlags
}
```

---

## RES-009: Settings tabs reorganization

**Decision**: Extend the `SettingsTab` enum from 4 to 6 cases, create two new View files

**Current tabs**: General, Prompts, About, Advanced
**New tabs**: General, Prompts, **Hotkeys**, **LLM**, About, Advanced

**Settings transfer**:
| From | To | What |
|------|----|------|
| General → Hotkeys | HotkeyRecorder (overlay invocation) |
| General → LLM | API key (SecureField + validation) |
| Prompts → LLM | STT model, LLM model (Pickers + info popovers) |

**New settings in "Hotkeys"**:
- Recording start/stop hotkey (default: Space) — custom recorder

**After moving out, General contains**: audio device, duration, auto-record, permissions, launch at login

**New files**:
- `Views/HotkeysSettingsTab.swift`
- `Views/LLMSettingsTab.swift`

---

## RES-010: Controls at the bottom of the overlay (FR-035)

**Decision**: Move the selectors bar from the top to the bottom of OverlayContentView

**Current layout**:
```
┌──────────────────────────┐
│ [Prompt] [Language]      │  ← selectors (top)
│    Recording / Result    │
└──────────────────────────┘
```

**Target layout**:
```
┌──────────────────────────┐
│    Recording / Result    │
│ [Prompt] [Language] [⚙]  │  ← controls (bottom)
└──────────────────────────┘
```

The change is a rearrangement of elements in the VStack inside OverlayContentView.

---

## RES-011: Custom recorder for the recording hotkey

**Decision**: NSView-based recorder to capture the keyCode

**Approach**:
- Cannot use `KeyboardShortcuts.Recorder` (for global hotkeys)
- Custom NSViewRepresentable: when focused, a key press is recorded as the new hotkey
- Display a human-readable name: `keyCode → displayName` (Space, Return, Tab, etc.)
- Validation: warning when picking a letter key without a modifier

---

## RES-012: Third-party dependencies

**Decision**: No new dependencies required

All changes use the existing stack. Consistent with Principle 2 of the constitution.

---

## RES-013: Incomplete onboarding step is not persisted

**Decision**: Remove `@AppStorage("onboardingCurrentStep")` from OnboardingViewModel, always start from `.welcome`

**Rationale**: Spec: "The current step is NOT persisted between launches"

**Current state**: If there is `@AppStorage` for the step — remove it. If not — OK.
