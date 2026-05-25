# Data model: App settings and onboarding

**Date**: 2026-03-07 (updated)
**Feature**: 002-app-settings-onboarding

## Entities

### OnboardingStep (unchanged)

Onboarding progression state. **Already exists in code** — no changes required.

```swift
enum OnboardingStep: Int, Codable, CaseIterable {
    case welcome = 0
    case permissions = 1
    case microphoneTest = 2
    case completion = 3
}
```

**Storage**: UserDefaults
- `onboardingCompleted: Bool` — completion flag (default: `false`)
- ~~`onboardingCurrentStep: Int`~~ — **REMOVE** (spec: the current step is NOT persisted between launches)

### LLMModel (unchanged)

All GPT 5.x models are **already implemented** in `LLMModel.swift`.

| Case | Display Name | API ID | Context | Price input/output per 1M |
|------|-------------|--------|---------|---------------------------|
| gpt51 | GPT 5.1 | gpt-5.1 | 128K | $1.25 / $10.00 |
| gpt52 | GPT 5.2 | gpt-5.2 | 400K | $1.75 / $14.00 |
| gpt53 | GPT 5.3 | gpt-5.3 | 1M | $2.50 / $20.00 |

### AppSettings (change)

**File**: `Models/AppSettings.swift`

**New fields**:
```swift
@ObservationIgnored
@AppStorage("recordingKeyCode")
var recordingKeyCode: Int = 49  // Space

@ObservationIgnored
@AppStorage("recordingModifiers")
var recordingModifiers: Int = 0  // No modifiers
```

**Computed property**:
```swift
var recordingKeyDisplayName: String {
    // Convert keyCode → human-readable name (Space, Return, Tab, etc.)
}
```

**Existing fields (unchanged)**: `isOnboardingCompleted`, `selectedSTTModel`, `selectedLLMModel`, `selectedAudioDeviceID`, `maxRecordingDuration`, `autoRecord`, `launchAtLogin`, `apiKey` (Keychain)

### SettingsTab (change)

**File**: `Views/SettingsView.swift`

**Current**: 4 cases — `general`, `prompts`, `about`, `advanced`
**Target**: 6 cases — `general`, `prompts`, `hotkeys`, `llm`, `about`, `advanced`

```swift
enum SettingsTab: String, CaseIterable {
    case general
    case prompts
    case hotkeys      // NEW
    case llm          // NEW
    case about
    case advanced

    var title: String {
        switch self {
        case .general: return "General"
        case .prompts: return "Prompts"
        case .hotkeys: return "Hotkeys"
        case .llm: return "LLM"
        case .about: return "About"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .prompts: return "text.bubble"
        case .hotkeys: return "keyboard"
        case .llm: return "brain"
        case .about: return "info.circle"
        case .advanced: return "gearshape.2"
        }
    }
}
```

### OnboardingViewModel (changes)

**Remove**:
- `@AppStorage("onboardingCurrentStep")` — the current step is not persisted
- `saveProgress()` — the method and all of its call sites

**Change init**:
- Always `self.currentStep = .welcome` (do not restore from UserDefaults)

### OverlayPanel (changes)

**File**: `Views/OverlayPanel.swift`

**Remove**:
- `compactSize` / `expandedSize` — replace with `fixedSize`
- `resizeToCompact()` / `resizeToExpanded()`

**Add**:
```swift
static let fixedSize = NSSize(width: 480, height: 400)

func positionOnScreen() {
    let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
    guard let visibleFrame = screen?.visibleFrame else { return }

    let x = visibleFrame.origin.x + (visibleFrame.width - Self.fixedSize.width) / 2
    let y = visibleFrame.origin.y + visibleFrame.height * 0.10

    setFrame(NSRect(origin: NSPoint(x: x, y: y), size: Self.fixedSize), display: true)
}
```

**Style mask**: add `styleMask` without `.resizable` (borderless already has no resize)

## State transitions

### Onboarding

```
[First launch] → welcome → permissions → microphoneTest → completion → [Normal mode]
                    ↑           ↑              ↑
                    └───────────┴──────────────┘
                    ("Back" navigation between steps)
```

**Transition conditions**:
- welcome → permissions: always allowed
- permissions → microphoneTest: only if Microphone is granted
- microphoneTest → completion: always allowed
- completion → [finish]: via the "Finish" button

**On restart**: If the onboarding has not been completed → it starts from welcome.

### API key on the completion screen

```
[Enter key] → "Save and verify" → validating → success → Keychain
                                              → error → show error
[No input]  → "Skip" → finish without a key
```

## Data migration between tabs

The transfer is purely a UI operation. Data is stored in `AppSettings` (UserDefaults/Keychain) and does not depend on the View. No migration is required.

| Data | Current tab | New tab | Storage |
|------|-------------|---------|---------|
| Overlay hotkey | General | Hotkeys | KeyboardShortcuts |
| Recording hotkey | (new) | Hotkeys | @AppStorage |
| API key | General | LLM | Keychain |
| STT model | Prompts (footer) | LLM | @AppStorage |
| LLM model | Prompts (footer) | LLM | @AppStorage |

## Validation

- Microphone is required for transition from the permissions screen (FR-008b)
- Accessibility is not required for the transition (FR-008b)
- The API key is checked via a test API request (FR-011a)
- Hotkey conflict: identical keyCode + modifiers are not allowed (FR-025)
- GPT 5.x model not supported by the API → show error (Edge Case)
