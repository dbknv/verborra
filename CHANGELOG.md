# Changelog

All notable changes to Verborra are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

## [1.4.1] - 2026-10-15

### Fixed

- **"Couldn't start MacBook Pro Microphone (format 44100 Hz ≠ 48000 Hz)"**: recording failed every time on a microphone selected by name when its sample rate differed from the system default input. The microphone's own rate is now used.

## [1.4.0] - 2026-10-15

Reliability fixes, a new shortcut recorder with Fn support, a reworked floating window, and an updated OpenAI model list.

### Added

- **New text models**: GPT-5.6 Terra, GPT-5.6 Sol, GPT-6 Luna, GPT-6 Sol, GPT-6.1 Sol and GPT-6 Astra, with prices in Settings → LLM (the list scrolls).
- **GPT Transcribe** is the new speech-to-text model.
- **Fn / 🌐︎ shortcuts** — e.g. `🌐︎ Space` (needs Accessibility access).
- **New shortcut recorder** — shows held modifiers as you press them, saves on the first key, and explains why a shortcut can't be used (taken by macOS, another app, or the Verborra window).
- **Launch at login** is asked once at the end of onboarding; Settings shows "needs approval" with an **Open Login Items** button when macOS requires it.
- A clear message when your OpenAI account can't use the selected model.
- Each bottom-bar menu starts with a title: **Input device**, **Output language**, **Using prompt**.
- Prompt names have a 30-character counter in Settings; older longer names are kept but must be shortened before saving.

### Changed

- **Defaults are now GPT Transcribe and GPT-6 Luna.** If you used a model that was removed — or never changed the old default — Verborra switches you to the new default automatically.
- **Floating window**: the prompt menu moved to the bottom bar. Order and keys are **1** microphone, **2** output language, **3** prompt; they work before and during recording. The prompt button is as wide as its name, without ever crowding Start/Stop and Exit.
- Starting the microphone shows "Starting microphone…" and can be cancelled with the shortcut, Esc or the Cancel button. If it can't start, you get a Retry button within 5 seconds instead of a frozen app.
- Verborra no longer switches silently to the system default microphone when your selected one fails.

### Removed

- Models retired by OpenAI: GPT-4o Mini, GPT-4.1 Mini, GPT-5 Nano, GPT-5 Mini, GPT-5.1, GPT-5.4 Nano, GPT-4o Mini Transcribe, GPT-4o Transcribe, Whisper-1.
- GPT-5.4 Pro and GPT-5.5 Pro (they need an OpenAI API that Verborra doesn't use).

### Fixed

- **Launch at login**: the Settings toggle now shows the real macOS state and offers **Open Login Items** when approval is needed (for example after installing a new ad-hoc-signed build).
- **The app could freeze when recording started** (for example after a microphone sample-rate change or with an unplugged USB mic).
- **Overlay keys (1, 2, 3, Esc…) were captured while typing in Settings.**
- Requests that OpenAI rejected (e.g. an unsupported model setting) were retried three times before the error showed.
- A fresh install had no default prompt marked.
- **Switching microphones during a recording failed** for every microphone except System Default; switching now retries like a normal start and shows "Switching to …".
- **Closing the window during a microphone switch could turn the microphone on afterwards.**

## [1.3.0] - 2026-05-29

Model catalog refresh, the "Answer questions" toggle that finally works on the built-in prompt, and visible OpenAI error messages.

### Added

- Six new LLM models: **GPT-5.5, GPT-5.5 Pro, GPT-5.4, GPT-5.4 Pro, GPT-5.4 Mini, GPT-5.4 Nano**. Pricing per 1M tokens shown inline in Settings → LLM.
- OpenAI error messages now appear in the diagnostic log on every non-200 response, so "why did this model return 400?" is answerable from the log alone.

### Changed

- **Default LLM is now GPT-5.1** (was GPT-4.1 Nano). Existing installs keep their selection.
- **Built-in prompt renamed** to **"Speech To Text"** (es/fr/pt/it adjusted to the Speech-side noun; ru/de/zh/ja/ko already aligned).
- **"Answer questions in the first message?" toggle now works on every prompt**, including the built-in one — previously it was disabled in Settings and reset to off on every launch.
- **Mid-chat language switch now affects continuation replies** — previously it only affected the next first-turn dictation.

### Fixed

- **GPT-5 Nano / GPT-5 Mini now work** — the request was sending an unsupported `temperature` parameter. The key is now omitted for reasoning-tier models (`gpt-5-nano`, `gpt-5-mini`, `gpt-5.4-nano`, `gpt-5.4-mini`); other models keep `temperature: 0.2`.
- **"Answer questions" toggle actually changes the response** — a residual response-language directive was still instructing the model to echo the input verbatim. With the toggle on, the model now produces a substantive answer; with it off, the existing dictation behaviour is preserved.

### Removed

- **`gpt-4.1-nano`** — OpenAI deprecated.
- **`gpt-5.3`** — never existed at OpenAI (returned 404).

Existing installs with either selected fall back silently to the new default on next launch.

### Migration

- One-time prompts-schema bump v3 → v4 on first launch re-syncs system prompt names from the registry (this is how the "Speech To Text" rename reaches existing installs). No user data is lost.

## [1.2.0] - 2026-05-28

Dictation flow rework: per-prompt control over question-answering on the first voice message, simplified default prompt, and chat continuation that finally behaves like a real chat.

### Added

- **"Answer questions in the first message?" toggle** on every editable prompt in Settings → System Prompts, with an inline `?` icon explaining the behavior. When off, the model formats your dictation and never answers — even if your speech contains a question. When on, the first voice message can become an exchange with the model and the dialogue continues in the chat window.
- **Strengthened critical-instruction wording** for the "don't answer" mode, with explicit "MUST NOT" prohibitions and a concrete example / counter-example, so small models (e.g. `gpt-4.1-nano`) follow it reliably. Localized in all 10 supported languages.
- **Streaming guard**: while the assistant is still streaming a reply, Send and the re-record voice button are disabled — no parallel requests, no half-formed payloads.

### Changed

- **Default behavior is now "format only"**: every prompt ships with the new toggle off. Previously the model would freely answer any question heard inside the first voice message. To restore the old behavior on a per-prompt basis, turn the toggle on in Settings → System Prompts.
- **Chat continuation uses chat-mode instead of the dictation prompt**: after the first formatted reply, follow-up messages in the result window are no longer re-formatted as if they were new dictation. The model responds conversationally and the full session history is sent every time.
- **`Simple Voice To Text` built-in prompt is simplified and read-only**: the content was tightened to "Fix spelling errors and add punctuation. Return only the corrected text." — no more paragraph splitting. The prompt cannot be edited or deleted; create a custom prompt if you need a different formatter.

### Fixed

- **Lost chat history bug**: previously, the non-streaming branch of a follow-up send transmitted only the latest text without the prior conversation, so the model responded "from scratch." Both paths now share a single context-composition path, and the full session history is included in every continuation request.
- **Edited messages in the chat window**: edits made via the existing in-window edit UI are now reflected in the request payload. Previously the original (pre-edit) text leaked into follow-ups.

### Migration

- A one-time migration on first launch force-overwrites the stored `Simple Voice To Text` content with the new simplified phrasing. Any customizations of that built-in prompt from prior versions are wiped. The migration bumps the prompts data schema to v3 and runs once per install.
- Custom user prompts keep their content; the new `answerQuestionsInFirstMessage` field defaults to off on first load.

### Notes

- History that exceeds the model's token budget is now trimmed in user/assistant pairs from the oldest end — never from the middle. The system prompt and the latest user message are always preserved.
- Internal: the first voice turn now goes through the same streaming send path as continuation messages (`streamChat`). `streamFormat` is no longer the front door for the first turn — see `specs/013-dictation-flow-rework/` for the design history.

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

[Unreleased]: https://github.com/dbknv/verborra/compare/v1.4.1...HEAD
[1.4.1]: https://github.com/dbknv/verborra/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/dbknv/verborra/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/dbknv/verborra/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/dbknv/verborra/compare/v1.0.0...v1.2.0
[1.0.0]: https://github.com/dbknv/verborra/releases/tag/v1.0.0
