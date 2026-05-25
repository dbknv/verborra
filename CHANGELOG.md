# Changelog

All notable changes to Verborra are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

—

## [1.0.0] - 2026-05-22

First public release. A complete, native macOS voice-input tool: global hotkey → record → OpenAI STT → LLM formatting → paste.

### Added

#### Core voice input
- Global hotkey toggles a floating overlay panel (NSPanel) that captures audio and shows live transcription.
- Auto-record on overlay open (configurable); Space or the Stop button finalizes a recording.
- OpenAI speech-to-text and LLM post-formatting in a single pipeline.
- WYSIWYG Markdown editor in the overlay with real-time formatting.
- Paste into the previously focused app via clipboard + Cmd+V simulation (CGEvent).
- Toggle-to-close behavior: re-pressing the hotkey while the overlay is open closes it without inserting.
- Configurable recording limit (1 / 5 / 10 / 20 min) with a 30-second warning and auto-stop; 25 MB per-recording cap.
- Retry-without-re-recording: API failures show a Retry button while the audio is preserved.

#### Prompts and personalization
- Named system prompts with Markdown support; one is marked as the default.
- Switch the active prompt from inside the overlay; switching re-runs formatting on the same audio.
- "Default" prompt auto-created on first launch.
- **Vocabularies** — user-defined dictionary of correct spellings and phonetic alt-spellings; injected into every formatting prompt so domain terms (product names, jargon) come out right.
- **Personal preferences** — free-form context that's prepended to every formatting prompt.

#### Models
- Selectable transcription models: `gpt-4o-mini-transcribe` (default), `gpt-4o-transcribe`, `whisper-1`.
- Selectable formatting models: `gpt-4.1-nano` (default), `gpt-4o-mini`, `gpt-4.1-mini`, `gpt-5-nano`.
- Per-model price/quality reference in the settings UI.

#### Languages
- Independent selection of speech language and response language.
- Language UI integrated into the General tab (no separate language picker tab).
- UI follows the system locale; localized for English and Russian.

#### Audio
- Audio input device selector with explicit device list.
- "System default" mode that follows changes to the default input device live.
- Bluetooth profile awareness — handles HFP ↔ A2DP transitions and sample-rate changes without dropping a recording.
- Lock-free SPSC ring buffer for capture-thread → main-thread audio handoff (swift-atomics).

#### Settings & onboarding
- Tabbed settings window: General, Hotkeys, LLM, Prompts, Vocabularies, Advanced, About.
- API key stored in the macOS Keychain (`kSecAttrAccessibleAfterFirstUnlock`); validated on save with a live API ping.
- Auto-launch at login via `SMAppService` (on by default, togglable).
- In-settings permission checks for Microphone and Accessibility, with one-click prompts when missing.

#### Diagnostics
- Opt-in structured JSONL logging to `~/Library/Application Support/Verborra/Logs/`.
- Configurable log level; automatic log-file rotation and size limits.
- Bluetooth event throttling to keep logs readable.
- Sensitive-data masking (API keys, etc.) in all log output.
- Flow tracking (`FlowTracker`) for correlating events across a single recording.

#### App shell
- Menu bar app (`LSUIElement`) — no Dock icon.
- Overlay panel correctly accepts keyboard input and global hotkeys; app activates only when needed and returns to background otherwise.

### Notes
- Audio is never persisted to disk. Each recording is one-shot.
- No telemetry. Network calls go only to the OpenAI API using the user-provided key.
- Built with Swift 5.9+, SwiftUI, AppKit, AVFoundation, CoreAudio.

[Unreleased]: https://github.com/dbknv/verborra/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/dbknv/verborra/releases/tag/v1.0.0
