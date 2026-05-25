# Implementation plan: App settings and onboarding

**Branch**: `002-app-settings-onboarding` | **Date**: 2026-03-07 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-app-settings-onboarding/spec.md`

## Summary

Reorganize the settings window from 4 to 6 tabs (add "Hotkeys" and "LLM"), move related settings into the new tabs, improve the visuals and UX of settings (insets, grouping, no scrolling, static sidebar). Fixed positioning of the floating overlay (horizontal center, 10% from the bottom), non-resizable window. Add a recording start/stop hotkey (Space). Onboarding improvements and edge cases.

## Technical context

**Language/Version**: Swift 5.9+, macOS 14+ (Sequoia)
**Primary dependencies**: SwiftUI, AppKit (NSPanel, NSWindow), AVFoundation (AVAudioEngine), Security (Keychain), ServiceManagement (SMAppService), KeyboardShortcuts (sindresorhus v2.0+), swift-markdown (swiftlang v0.4+)
**Storage**: UserDefaults (@AppStorage), macOS Keychain (Security framework), JSON in Application Support (prompts)
**Testing**: XCTest / Swift Testing
**Target platform**: macOS 14+ (Sequoia, macOS 25, macOS 26)
**Project type**: single (native macOS Menu Bar app)
**Performance**: time from hotkey to recording-ready ≤ 300ms, 60fps animations
**Constraints**: App Sandbox disabled (Accessibility API), no Dock icon (LSUIElement)
**Scale**: ~38 Swift files, ~10 test files, 1 user

## Constitution check

*GATE: Must pass before Phase 0. Re-check after Phase 1.*

| Principle | Status | Comment |
|-----------|--------|---------|
| 1. Native macOS experience | PASS | SwiftUI + NSPanel, follow HIG, NavigationSplitView for the sidebar |
| 2. Swift-first | PASS | All code in Swift, SPM, MVVM + @Observable |
| 3. Minimalism and simplicity | PASS | Tab reorganization — structuring, not added complexity; UserDefaults for settings, Keychain for the key |
| 4. Security and privacy | DEVIATION | App Sandbox disabled (FR-037) — justified: AXIsProcessTrusted, CGEvent are incompatible with the sandbox. Distribution — direct download |
| 5. Code quality | PASS | Unit tests for new models and services, protocols for mocking |

### Deviation tracking

| Violation | Justification | Why a simpler alternative does not work |
|-----------|---------------|-----------------------------------------|
| App Sandbox disabled | The Accessibility API (AXIsProcessTrusted, CGEvent) is incompatible with the sandbox | With the sandbox auto text insertion — the app's primary function — is impossible. Distribution via direct download, not the Mac App Store |

## Project structure

### Documentation (this feature)

```text
specs/002-app-settings-onboarding/
├── plan.md              # This file
├── research.md          # Phase 0: research
├── data-model.md        # Phase 1: data model
├── quickstart.md        # Phase 1: quickstart guide
├── contracts/           # Phase 1: contracts (N/A — no API)
└── tasks.md             # Phase 2: tasks (/speckit.tasks)
```

### Source code (repository root)

```text
Verborra/
├── VerborraApp.swift              # Entry point + AppDelegate
├── Models/
│   ├── AppSettings.swift              # @Observable settings (MODIFY: add recordingHotkey)
│   ├── LLMModel.swift                 # LLM models enum (OK: GPT 5.x already present)
│   ├── STTModel.swift                 # STT models enum (OK)
│   ├── OnboardingState.swift          # Onboarding steps enum (OK)
│   ├── RecordingState.swift           # Recording state (OK)
│   ├── SystemPrompt.swift             # Prompts (OK)
│   └── ...                            # Other models
├── Services/
│   ├── HotkeyService.swift            # Global hotkey (MODIFY: add toggleRecording)
│   ├── KeychainService.swift          # Keychain (OK)
│   ├── AudioCaptureService.swift      # Audio capture (OK)
│   └── ...                            # Other services
├── ViewModels/
│   ├── SettingsViewModel.swift        # Settings VM (MODIFY: new tabs, hotkey conflict)
│   ├── RecordingViewModel.swift       # Recording VM (MODIFY: recording hotkey)
│   └── OnboardingViewModel.swift      # Onboarding VM (OK)
└── Views/
    ├── SettingsView.swift             # MAJOR MODIFY: 4→6 tabs, settings transfer
    ├── OverlayPanel.swift             # MODIFY: positioning, fixed size
    ├── OverlayContentView.swift       # MODIFY: controls at the bottom
    ├── Components/
    │   ├── HotkeyRecorder.swift       # OK
    │   └── ...
    └── Onboarding/
        └── ...                        # OK: 4 steps already implemented

VerborraTests/
├── Services/                          # ADD: tests for hotkey conflict
└── ViewModels/
    └── SettingsViewModelTests.swift    # MODIFY: tests for new tabs
```

**Structure decision**: We reuse the existing structure from feature 001. New files are only the new settings View tabs (HotkeysSettingsTab.swift, LLMSettingsTab.swift). The rest are modifications of existing files.

## Areas of change

### 1. Settings reorganization (US3, US5, US6)

**Current state**: 4 tabs (General, Prompts, About, Advanced)
**Target state**: 6 tabs (General, Prompts, Hotkeys, LLM, About, Advanced)

**Settings transfer**:
- General → "Hotkeys": HotkeyRecorder (overlay invocation)
- General → "LLM": OpenAI API key (SecureField + validation)
- Prompts → "LLM": STT model, LLM model (Picker + info popover)
- General: remains — audio device, duration, auto-record, permissions, launch at login

**New settings**:
- "Hotkeys": recording start/stop hotkey (default: Space)
- "Hotkeys": hotkey conflict detection

**Files**:
- New: `Views/HotkeysSettingsTab.swift`
- New: `Views/LLMSettingsTab.swift`
- Modify: `Views/SettingsView.swift` (SettingsTab enum, GeneralSettingsTab, PromptsSettingsTab)
- Modify: `ViewModels/SettingsViewModel.swift` (hotkey conflict)

### 2. Recording hotkey (US5)

**Current state**: Space is handled in KeyCaptureView (hardcoded in RecordingViewModel.handleKeyDown)
**Target state**: Configurable recording hotkey via KeyboardShortcuts

**Approach**: Add `KeyboardShortcuts.Name.toggleRecording` with a default of Space. The hotkey is not global — it works only when the overlay is open. Implementation via a local event monitor inside OverlayPanel, not via global KeyboardShortcuts (Space without modifiers cannot be registered as a global hotkey).

**Files**:
- Modify: `Services/HotkeyService.swift`
- Modify: `Models/AppSettings.swift` (saving the recording hotkey)
- Modify: `ViewModels/RecordingViewModel.swift` (using the configurable hotkey)
- Modify: `Views/OverlayContentView.swift` (KeyCaptureView)

### 3. Overlay positioning (US7)

**Current state**: `center()` (screen center), resizable size (compact/expanded)
**Target state**: horizontal center, 10% from the bottom; fixed size; non-resizable

**Approach**:
- Compute position via `NSScreen.main?.visibleFrame` (accounting for Dock and Menu Bar)
- On multi-monitor — `NSScreen` of the key window
- Disable `isMovableByWindowBackground`
- Fixed size (no compact/expanded switching for the overlay)

**Files**:
- Modify: `Views/OverlayPanel.swift` (positioning, fixed size)
- Modify: `Views/OverlayContentView.swift` (controls at the bottom)

### 4. Visual improvements for settings (US3)

**Approach**:
- Sidebar: `navigationSplitViewColumnWidth` pinned to 210px (min/ideal/max), top inset for the traffic lights
- Window: increase minWidth/minHeight to fit all elements
- Sidebar: remove the collapse button (`.navigationSplitViewStyle(.prominentDetail)` + toolbar modifier)
- Command+Q: standard macOS behavior (works by default)
- Command+W: already works for the settings NSWindow

**Files**:
- Modify: `Views/SettingsView.swift`

### 5. Onboarding — edge cases (US1)

**Current state**: Basic onboarding is already implemented (4 steps, VM, window)
**Improvements**:
- Check that closing the window is blocked (Cmd+W, close button)
- Check that settings and the overlay are blocked until completion
- `isOnboardingCompleted` reactivity for the menu
- Edge case: "Open settings" from an error in the overlay

**Files**:
- Modify: `Views/Onboarding/OnboardingWindow.swift` (if fixes are needed)
- Modify: `VerborraApp.swift` (menu blocking)
