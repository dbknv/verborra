# Research: Voice Text Input

**Feature**: 001-voice-input
**Date**: 2026-03-04
**Updated**: 2026-03-04

---

## Decision 1: WYSIWYG Markdown Editor

### Decision

Use `NSTextView` (wrapped in SwiftUI via `NSViewRepresentable`) + `swift-markdown` parser (Apple) for real-time WYSIWYG Markdown rendering.

### Rationale

- `NSTextView` is the only native macOS component providing full editing with support for attributed strings, undo/redo, spell check, accessibility.
- `swift-markdown` (swiftlang/swift-markdown) — Apple's official parser with CommonMark + GFM support and **source location tracking**, which allows accurate mapping of AST nodes to character ranges in `NSTextStorage` for styling.
- Architecture: on every text change (`NSTextStorageDelegate.didProcessEditing`) we parse via `swift-markdown`, get the AST with positions, apply `NSAttributedString` attributes (font size for headings, bold, italic, monospace for code, indents for lists).

### Alternatives Considered

| Alternative | Rejection reason |
|---|---|
| **MarkdownUI** (gonzalezreal) | Display only, no editing — no way to edit text |
| **RichTextKit** (danielsaidi) | RTF editor, not Markdown-aware — would require the same parser integration on top |
| **SwiftUI TextEditor + AttributedString** | `TextEditor` does not support `AttributedString` binding — only `String` |
| **WKWebView + ProseMirror/CodeMirror** | Violates Constitution Principle 1 (native macOS experience), JS-bridge complicates architecture |

### Dependency

- `swift-markdown` (swiftlang/swift-markdown) — SPM, MIT License, maintained by Apple

---

## Decision 2: Global Hotkey

### Decision

Use the **KeyboardShortcuts** library (sindresorhus/KeyboardShortcuts) — a wrapper over Carbon `RegisterEventHotKey` with a built-in SwiftUI `Recorder` for configuring the hotkey.

### Rationale

- Carbon `RegisterEventHotKey` — **does not require Accessibility permissions** (unlike CGEventTap and NSEvent.addGlobalMonitorForEvents).
- Fully compatible with App Sandbox without additional entitlements.
- `KeyboardShortcuts` provides:
  - A ready-made `KeyboardShortcuts.Recorder` SwiftUI component for recording a new hotkey (FR-010).
  - Automatic saving in `UserDefaults`.
  - Conflict detection with other applications.
  - Clean Swift async/await API.
- Replaces ~500 lines of boilerplate code.

### Alternatives Considered

| Alternative | Rejection reason |
|---|---|
| **CGEventTap** (.defaultTap) | Requires Accessibility permission — complicates onboarding |
| **NSEvent.addGlobalMonitorForEvents** | Requires Accessibility, cannot suppress the event |
| **HotKey** (soffes) | No Recorder UI, thin wrapper — minimal gain |
| **Custom Carbon implementation** | ~500 lines instead of a ready-made solution, no Recorder UI |

### Dependency

- `KeyboardShortcuts` (sindresorhus/KeyboardShortcuts) — SPM, MIT License, used in dozens of production Mac applications

---

## Decision 3: Audio Capture and Format

### Decision

Use `AVAudioEngine` with a tap on the input node, convert to **WAV (PCM Int16, 16 kHz, mono)** in-memory, send directly to the OpenAI API.

### Rationale

- WAV 16 kHz mono Int16 — Whisper's native training format, zero-loss transcoding.
- At 16 kHz mono: ~1.92 MB/minute → 25 MB limit covers ~13 minutes (specification — max. 20 minutes when chosen by the user, but 25 MB = ~13 min, so the 25 MB limit will trigger earlier at max duration 20 min).
- In-memory: we accumulate `AVAudioPCMBuffer` frames, on stop we form a 44-byte RIFF WAV header + data → `Data`. No disk writes (Principle 4).
- `AVAudioConverter` for conversion from hardware format (44.1/48 kHz stereo) to target.
- All three transcription models (gpt-4o-mini-transcribe, gpt-4o-transcribe, whisper-1) support the WAV format.

### Alternatives Considered

| Alternative | Rejection reason |
|---|---|
| **m4a (AAC)** | Requires AVAssetWriter or complex conversion, size gain is not critical at 5-minute limit |
| **mp3** | No native encoder on Apple platforms |
| **Recording via AVAudioRecorder** | Always writes to disk — violates Principle 4 |

---

## Decision 4: Integration with OpenAI API

### Decision

Use **raw URLSession** with `async/await` for both APIs:
1. **Audio Transcriptions API** (`/v1/audio/transcriptions`) — multipart/form-data POST with WAV data. Model selected by user (gpt-4o-mini-transcribe default, gpt-4o-transcribe, whisper-1).
2. **Chat Completions API** (`/v1/chat/completions`) — JSON POST for AI formatting. Model selected by user (gpt-4.1-nano default, gpt-4o-mini, gpt-4.1-mini, gpt-5-nano).

### Rationale

- URLSession — Swift's standard tool (Principle 2), zero dependencies.
- Multipart upload for transcription: ~80 lines (boundary, fields, audio data).
- Chat Completions: standard JSON request/response, ~40 lines.
- Non-streaming for both APIs: the text is short, streaming adds complexity without noticeable UX gain.

### Transcription Model Compatibility

| Parameter | whisper-1 | gpt-4o-transcribe | gpt-4o-mini-transcribe |
|---|---|---|---|
| Endpoint | `/v1/audio/transcriptions` | `/v1/audio/transcriptions` | `/v1/audio/transcriptions` |
| Request format | multipart/form-data | multipart/form-data | multipart/form-data |
| `response_format` | json, text, srt, verbose_json, vtt | **json, text only** | **json, text only** |
| `language` (ISO 639-1) | Yes | Yes | Yes |
| Streaming | No incremental | Incremental SSE | Incremental SSE |
| `logprobs` | No | Yes | Yes |

**Important**: we use `response_format: "json"` for compatibility with all three models.

### Alternatives Considered

| Alternative | Rejection reason |
|---|---|
| **MacPaw/OpenAI** | Adds a dependency for the sake of ~120 lines of code — excessive |
| **SwiftOpenAI** (jamesrochabrun) | Same — too heavy a wrapper for 2 simple requests |
| **Streaming Chat API** | Post-processing of short text; latency difference is minimal, complexity increases |

### API Parameters

**Audio Transcriptions API:**
- Endpoint: `POST https://api.openai.com/v1/audio/transcriptions`
- Model: configurable (gpt-4o-mini-transcribe default)
- Format: multipart/form-data (file: WAV, model, language)
- `response_format`: `json` (for compatibility with all models)
- Response: `{"text": "..."}`

**Chat Completions API:**
- Endpoint: `POST https://api.openai.com/v1/chat/completions`
- Model: configurable (gpt-4.1-nano default)
- Temperature: 0.2 (determinism more important than creativity)
- System prompt: selected named prompt from settings (FR-015)

---

## Decision 5: Overlay Window (NSPanel)

### Decision

Use `NSPanel` with `.nonactivatingPanel` style mask and `orderFrontRegardless()` for display without focus interception.

### Rationale

- `.nonactivatingPanel` — the canonical way to create an overlay in macOS (Spotlight, Alfred, Raycast).
- `becomesKeyOnlyIfNeeded = true` — the panel becomes key window only when necessary (click in the editor's text field).
- `canBecomeMain → false` — never becomes main window.
- `hidesOnDeactivate = false` — remains visible when switching applications.
- `level = .floating` — above ordinary windows.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` — visible on all Spaces and above fullscreen.

### Key Settings

```swift
panel.styleMask = [.nonactivatingPanel, .borderless, .fullSizeContentView]
panel.level = .floating
panel.becomesKeyOnlyIfNeeded = true
panel.hidesOnDeactivate = false
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.isOpaque = false
panel.backgroundColor = .clear
```

---

## Decision 6: Text Insertion into Target Application

### Decision

**Main method**: `NSPasteboard` + simulation of `Cmd+V` via `CGEvent.postToPid()`.
**Fallback**: display of "text copied to clipboard" notification when the target application is unavailable.

### Rationale

- `CGEvent.postToPid()` — the most universal method, works in all popular applications (Safari, Chrome, VS Code, Slack, Telegram, Notes, TextEdit, Terminal).
- Accessibility API (`AXUIElement.kAXSelectedTextAttribute`) is unreliable in Electron applications (VS Code, Slack) and terminals.
- **Requires Accessibility permission** — necessary for CGEvent and AXUIElement.
- Clipboard restoration: snapshot → paste → 200ms delay → restore (with `changeCount` check).

### Distribution

- **Not via Mac App Store** — CGEvent.postToPid() is blocked in sandbox without special entitlements.
- Distribution via **notarized DMG** (direct download).
- Accessibility permission requested via `AXIsProcessTrustedWithOptions` on first launch.

### Alternatives Considered

| Alternative | Rejection reason |
|---|---|
| **AXUIElement (kAXSelectedTextAttribute)** | Unreliable in Electron apps and terminals |
| **AppleScript** | Slower, less universal |
| **Clipboard copy only** | Does not satisfy FR-007 (automatic insertion) |

---

## Decision 7: API Key Storage

### Decision

Use **Security framework** (SecItemAdd/SecItemCopyMatching) with a thin Swift wrapper (~50 lines).

### Rationale

- macOS Keychain — standard secure storage (Principle 4).
- `kSecClass: kSecClassGenericPassword`, `kSecAttrService: bundleID`, `kSecAttrAccount: "openai-api-key"`.
- Fully compatible with App Sandbox without additional entitlements.
- No need for a third party — the API is simple for one key.

---

## Decision 8: Auto-Launch at Login

### Decision

Use `SMAppService.mainApp` (ServiceManagement framework, macOS 13+).

### Rationale

- Modern API replacing the deprecated `SMLoginItemSetEnabled`.
- Fully compatible with App Sandbox.
- Simple toggle: `register()` / `unregister()`.
- The user can manage via System Settings > General > Login Items.

---

## Decision 9: Menu Bar Application

### Decision

Use SwiftUI `MenuBarExtra` (macOS 13+) + `LSUIElement = YES` in Info.plist.

### Rationale

- `MenuBarExtra` — pure SwiftUI API for the menu bar.
- `.menu` style — native pull-down menu for quick actions (Settings, Quit).
- `Settings {}` scene + `@Environment(\.openSettings)` to open the settings window.
- `LSUIElement = YES` — the application does not show in the Dock and Cmd+Tab.

---

## Decision 10: Named Prompt Storage

### Decision

Store named prompts in a **JSON file** in the application's `Application Support` directory.

### Rationale

- Prompts contain long Markdown text, which is inconvenient to store in UserDefaults/plist.
- JSON provides simple serialization/deserialization via Swift `Codable`.
- `Application Support` — the standard directory for application data on macOS.
- Path: `~/Library/Application Support/Verborra/prompts.json`

### File Structure

```json
{
  "prompts": [
    {
      "id": "uuid-string",
      "name": "Standard",
      "content": "Fix punctuation...",
      "isDefault": true,
      "voiceLanguage": "ru",
      "textLanguage": "ru"
    }
  ]
}
```

### Alternatives Considered

| Alternative | Rejection reason |
|---|---|
| **UserDefaults** | Inconvenient for long Markdown text, size limitations |
| **CoreData** | Excessive for a simple list of prompts |
| **Realm/SwiftData** | Adds a dependency, excessive (Principle 3) |
| **Separate .md files** | Harder to manage metadata (name, language, isDefault) |

---

## Decision 11: OpenAI Model Selection

### Decision

Global selectors for STT and LLM models in the "System Prompts" tab of settings. Models are stored in UserDefaults.

### Rationale

- Models are applied to all operations (FR-023c), therefore it is logical to place the selectors globally, not per-prompt.
- Next to each selector — a tooltip icon (?) with a popover reference about models and prices (FR-023d).

### Available STT Models

| Model | Price | Default |
|---|---|---|
| `gpt-4o-mini-transcribe` | $0.003/min | ✅ |
| `gpt-4o-transcribe` | $0.006/min | |
| `whisper-1` | $0.006/min | |

### Available LLM Models

| Model | Price (input/output per 1M tokens) | Default |
|---|---|---|
| `gpt-4.1-nano` | $0.10 / $0.40 | ✅ |
| `gpt-4o-mini` | $0.15 / $0.60 | |
| `gpt-4.1-mini` | $0.40 / $1.60 | |
| `gpt-5-nano` | $0.05 / $0.40 | |

### Compatibility Constraints

- For model `gpt-4o-mini-transcribe` or `gpt-4o-transcribe`, `response_format` MUST be `json` or `text` (srt/verbose_json/vtt not supported).
- The code MUST use `response_format: "json"` for compatibility with all models.

---

## Decision 12: Language Settings

### Decision

For each prompt, two language parameters are set: **voice language** (input audio language, passed to the `language` parameter of the Whisper API) and **text language** (output language, specified in the system prompt for Chat Completions).

### Rationale

- Separation of input and output languages enables the scenario "I speak in Russian, text in English" (and vice versa).
- Voice language improves transcription accuracy (ISO 639-1).
- Text language is specified in the system prompt: "Response in {language}".

### Available Languages

| Language | ISO 639-1 code |
|---|---|
| English | `en` |
| Russian | `ru` |
| Spanish | `es` |
| French | `fr` |
| German | `de` |
| Portuguese | `pt` |
| Chinese | `zh` |
| Japanese | `ja` |
| Korean | `ko` |
| Italian | `it` |

### Overlay Behavior

- Language selectors are visible at all stages (recording, processing, result).
- By default — values from the selected prompt.
- On prompt change — languages are automatically updated to the values of the new prompt.
- The user can change languages manually (changes are not saved to the prompt, applying only to the current recording).

---

## Dependencies Summary

| Dependency | Purpose | License | Rationale |
|---|---|---|---|
| `swift-markdown` | WYSIWYG Markdown parsing | MIT | Apple's official parser with source location tracking |
| `KeyboardShortcuts` | Global hotkey + Recorder UI | MIT | Replaces ~500 lines of boilerplate, includes Recorder for settings |

**Total**: 2 third-party dependencies, both MIT, both widely used in production.

---

## Permissions Summary

| Permission | Why | When requested |
|---|---|---|
| **Microphone** | Audio capture | On first recording attempt |
| **Accessibility** | CGEvent.postToPid() for text insertion | On first launch (onboarding) |
| **Network (Outgoing)** | OpenAI API | Automatically (App Sandbox entitlement) |
