# Quick Start: Voice Text Input

**Feature**: 001-voice-input
**Date**: 2026-03-04
**Updated**: 2026-03-05

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Xcode | 15.0+ | Build and debug |
| macOS | 14.0+ (Sequoia) | Target platform |
| Swift | 5.9+ | Development language |
| OpenAI API key | — | Audio Transcriptions + Chat Completions |

---

## Project Setup

### 1. Clone and Build

```bash
git clone <repo-url>
cd speech-to-text
swift build
```

### 2. Info.plist

```xml
<!-- Hide from Dock and Cmd+Tab -->
<key>LSUIElement</key>
<true/>

<!-- Description for microphone request -->
<key>NSMicrophoneUsageDescription</key>
<string>The application uses the microphone to record voice and recognize speech.</string>
```

### 3. Entitlements

```xml
<!-- App Sandbox -->
<key>com.apple.security.app-sandbox</key>
<true/>

<!-- Microphone access -->
<key>com.apple.security.device.audio-input</key>
<true/>

<!-- Outgoing network connections (OpenAI API) -->
<key>com.apple.security.network.client</key>
<true/>
```

**Note**: For text insertion via CGEvent.postToPid(), the application is distributed as a notarized DMG (not Mac App Store), so Accessibility permission is requested via `AXIsProcessTrustedWithOptions` on first launch.

### 4. SPM Dependencies (Package.swift)

| URL | Version | Purpose |
|---|---|---|
| `https://github.com/swiftlang/swift-markdown` | `>= 0.4.0` | WYSIWYG Markdown parsing |
| `https://github.com/sindresorhus/KeyboardShortcuts` | `>= 2.0.0` | Global hotkey + Recorder UI |

### 5. File Structure

```
Verborra/
├── VerborraApp.swift
├── Info.plist
├── Verborra.entitlements
├── Models/
│   ├── RecordingState.swift       # RecordingState enum + RecordingError
│   ├── TranscriptionResult.swift  # Recognition result
│   ├── SystemPrompt.swift         # Named prompt (Codable)
│   ├── STTModel.swift             # Transcription models (enum)
│   ├── LLMModel.swift             # Processing models (enum)
│   ├── SupportedLanguage.swift    # 10 languages (enum)
│   ├── MaxRecordingDuration.swift # Duration options (enum)
│   └── AppSettings.swift          # Settings (@Observable)
├── Services/
│   ├── AudioCaptureService.swift       # AVAudioEngine, WAV in-memory
│   ├── TranscriptionService.swift      # OpenAI Audio API
│   ├── FormattingService.swift         # OpenAI Chat Completions API
│   ├── KeychainService.swift           # Security framework wrapper
│   ├── APIKeyValidationService.swift   # API key validation
│   ├── PasteService.swift              # NSPasteboard + CGEvent
│   └── PromptsStore.swift              # JSON prompt storage
├── Views/
│   ├── OverlayPanel.swift         # NSPanel subclass
│   ├── OverlayContentView.swift   # Overlay content
│   ├── RecordingView.swift        # Recording UI (indicator, timer)
│   ├── ResultView.swift           # WYSIWYG Markdown editor
│   ├── SettingsView.swift         # Settings window (3 tabs)
│   └── Components/
│       ├── AudioWaveformView.swift    # Visual level indicator
│       ├── PromptSelectorView.swift   # Prompt selector
│       └── LanguageSelectorView.swift # Language selectors
├── ViewModels/
│   ├── RecordingViewModel.swift   # Recording flow coordinator
│   └── SettingsViewModel.swift    # Settings logic
└── Resources/
    └── Assets.xcassets
```

---

## First Launch

### 1. Build

```bash
# Swift Package Manager
swift build

# Or in Xcode
open Package.swift
# Cmd+R to run
```

### 2. Initial Setup

On first launch:

1. **Accessibility permission** — the system will show a dialog, the user must grant permission in System Settings → Privacy & Security → Accessibility.
2. **Microphone permission** — requested on the first recording attempt.
3. **API key** — enter in Settings → General → OpenAI API key (validated automatically on save).
4. **Default prompt** — created automatically on first launch.

### 3. Main Flow

```
Option+Space → Overlay appears
  ↓ (if auto-record is enabled — recording starts automatically)
Space (or button) → Start / Stop recording
  ↓
Processing: transcription (STT) → AI formatting (LLM)
  ↓
Result in WYSIWYG editor → Editing
  ↓
"Insert" → Text is inserted into the target field
```

**Overlay options:**
- Prompt selector (can be changed → re-AI processing)
- Voice language and text language selectors
- Buttons: Stop/Space, Insert, Copy, Escape (close)

---

## Running Tests

```bash
# Unit tests
swift test

# Or in Xcode: Cmd+U
```

---

## Environment Variables (for development)

| Variable | Description |
|---|---|
| `OPENAI_API_KEY` | Can be used for tests instead of Keychain |

---

## Useful Links

- [OpenAI Audio Transcriptions API](https://platform.openai.com/docs/api-reference/audio/createTranscription)
- [OpenAI Chat Completions API](https://platform.openai.com/docs/api-reference/chat/create)
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- [swift-markdown](https://github.com/swiftlang/swift-markdown)
- [Apple Human Interface Guidelines — Menu Bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
