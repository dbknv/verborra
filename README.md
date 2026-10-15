# Verborra

![Verborra demo](media/verborra-demo.gif)

Voice text input for macOS. Press a global hotkey, speak, get clean Markdown-formatted text inserted into the focused app.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue) ![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange) ![License: MIT](https://img.shields.io/badge/License-MIT-green)

## What it does

1. You put the cursor in any text field — browser, terminal, IDE, chat, anywhere.
2. You press your configured global hotkey. A compact overlay appears above all windows and starts recording.
3. You speak. A live waveform shows the audio level.
4. You stop (Space or the Stop button). The audio is sent to OpenAI for speech-to-text, then formatted by an LLM using a configurable system prompt.
5. The result appears in the overlay as live, editable Markdown.
6. You press Enter (or Cmd+V) — the text is pasted into the original field via the clipboard + Cmd+V simulation.

The whole loop is designed to feel like Alfred / Raycast: instant, transient, never in your way. The app lives in the menu bar (no Dock icon).


## Features

- **Global hotkey** — configurable in Settings → Hotkeys: click the field and press the shortcut; held modifiers show up live. Shortcuts can include **Fn / 🌐︎** (e.g. `🌐︎ Space`). 🌐︎ shortcuts need Accessibility access; if you use one, set System Settings → Keyboard → "Press 🌐︎ key to" → **Do Nothing** so macOS doesn't also open the emoji picker or dictation.
- **OpenAI STT + LLM formatting** — speech-to-text with **GPT Transcribe** (`gpt-transcribe`), formatting with one of ten text models: GPT-5.2, GPT-5.4 Mini, GPT-5.4, GPT-5.5, GPT-5.6 Terra, GPT-5.6 Sol, GPT-6 Luna, GPT-6 Sol, GPT-6.1 Sol, GPT-6 Astra. Prices per 1M tokens are shown in Settings → LLM. Defaults: **GPT Transcribe** and **GPT-6 Luna**. If you had a model that OpenAI retired, Verborra switches you to the default automatically.
- **Named system prompts** — keep multiple prompts (one is the default), switch between them in the overlay's bottom bar; switching re-runs the formatting pass on the same audio. Each prompt has a per-prompt **"Answer questions in the first message?"** toggle: off (the default) makes the model format your dictation and stay silent on questions inside it; on lets the first voice message become a chat exchange that you can then continue in the result window.
- **WYSIWYG Markdown editor** in the overlay — real-time formatting while you edit.
- **Vocabularies** — teach the app proper spellings of names, products, jargon and their phonetic alt-spellings (so "git hub" gets recognized as "GitHub").
- **Personal preferences** — free-form context that's injected into every formatting prompt.
- **Multilingual** — choose your speech language and the response language independently; UI follows the system locale.
- **Audio device selection** — pick a specific input device or follow the system default; Bluetooth profile changes (HFP↔A2DP) are handled gracefully.
- **Permissions UX** — explicit, in-settings checks for Microphone and Accessibility, with one-click prompts when missing.
- **Diagnostic logging** — opt-in structured JSONL logs in `~/Library/Application Support/Verborra/Logs/` for debugging.
- **Floating-window keys** — **1** microphone, **2** output language, **3** prompt (the same order as the bottom bar; each menu starts with a title saying what it sets). They work before and during recording; **Esc** closes.
- **Switch microphones while recording** — pick another microphone with **1** or the menu: recording restarts on it (what you said before the switch is discarded). Closing the window during a switch turns the microphone off.
- **Prompt names** are up to 30 characters, so they fit in the bottom bar.
- **Auto-launch at login** — asked once at the end of onboarding (on by default). Settings shows the real state from macOS, including "needs approval" with a button to open Login Items.
- **Native** — pure SwiftUI + AppKit. No Electron, no web view.

## Requirements

- macOS 15 (Sequoia) or newer
- An [OpenAI API key](https://platform.openai.com/api-keys) — stored in the macOS Keychain
- Microphone permission
- Accessibility permission (for `Cmd+V` simulation into the active app)

You are billed by OpenAI directly per request. Typical cost with the default models is a fraction of a cent per recording.

## Install

### From a release

Download the latest `Verborra.app.zip` from the [Releases](https://github.com/dbknv/verborra/releases) page, unzip, and move `Verborra.app` to `/Applications`. On first launch, right-click → Open (Gatekeeper).

### From source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/dbknv/verborra.git
cd verborra
xcodegen generate
open Verborra.xcodeproj
```

Build & Run in Xcode (`⌘R`). Or, for a release build:

```bash
xcodebuild -project Verborra.xcodeproj -scheme Verborra -configuration Release
```

Builds are signed ad-hoc ("Sign to Run Locally", no Apple Developer account needed) with Hardened Runtime. Because an ad-hoc signature changes with every build, after installing a new build macOS may ask for Accessibility again, and launch at login may need re-approval in System Settings › General › Login Items (Settings shows this). Check a build with:

```bash
codesign -dv /Applications/Verborra.app   # expect flags=0x10002(adhoc,runtime)
```

You can also build the executable target via SwiftPM (`swift build`), but the macOS app bundle and entitlements come from the Xcode project.

## First-run setup

1. Launch the app — it appears in the menu bar.
2. Open **Settings** from the menu bar item.
3. **LLM tab** → paste your OpenAI API key. The app sends a tiny validation request and tells you immediately whether the key works.
4. **Hotkeys tab** → record the global hotkey you want to trigger the overlay (default `⌥ Space`).
5. **General tab** → grant Microphone and Accessibility permissions via the in-settings buttons.
6. **Prompts tab** → review the auto-created Default prompt or add your own.

That's it. Press your hotkey anywhere and start talking.

## Configuration

| Setting              | Where                | Notes                                                            |
| -------------------- | -------------------- | ---------------------------------------------------------------- |
| API key              | Keychain             | `kSecAttrAccessibleAfterFirstUnlock`, never written to disk      |
| Hotkey, audio device | `UserDefaults`       |                                                                  |
| Named prompts        | Application Support  | `~/Library/Application Support/Verborra/prompts.json`            |
| Vocabularies         | Application Support  | `~/Library/Application Support/Verborra/vocabularies.json`       |
| Logs (opt-in)        | Application Support  | `~/Library/Application Support/Verborra/Logs/*.jsonl`            |

The recording limit is configurable (1 / 5 / 10 / 20 minutes; capped at 25 MB per recording).

## Privacy

- Audio leaves your machine only to be sent to OpenAI's API for transcription and formatting.
- Recordings are **not stored** — once the overlay closes, the audio is gone.
- The API key sits in the system Keychain.
- No telemetry, no analytics, no third-party servers other than OpenAI.

## Tech stack

- **Swift 5.9+**, **SwiftUI**, **AppKit** (`NSPanel` for the overlay)
- **AVFoundation** (`AVAudioEngine`, `AVCaptureDevice`) for capture
- **CoreAudio** for device-change listeners and Bluetooth profile detection
- **Security** (Keychain) for secrets
- **ServiceManagement** (`SMAppService`) for login-item registration
- **Accessibility API** (`AXIsProcessTrusted`) for permission checks
- **os.Logger** (Unified Logging) for runtime logs

### Dependencies

- [swift-markdown](https://github.com/swiftlang/swift-markdown) — Markdown parsing for the WYSIWYG editor
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — global hotkey registration
- [swift-atomics](https://github.com/apple/swift-atomics) — lock-free SPSC ring buffer for audio

## Project layout

```
Verborra/
├── Verborra/                # App sources (Models, Views, ViewModels, Services)
├── VerborraTests/           # Unit tests
├── Verborra.xcodeproj/      # Generated by XcodeGen
├── project.yml              # XcodeGen spec
└── specs/                   # Per-feature design specs (internal, optional reading)
```

## Development

This project is built with [apeek-kit](https://github.com/apeekdev/apeek-kit) — a Spec-Driven Development toolkit. To keep the app's functionality stable and predictable, any further work on it should go through the same workflow: read up on apeek-kit and apply it. Every feature gets a detailed, structured specification up front — covering what is being done and why, who owns it and when — before any code is written. The per-feature artifacts live under [specs/](specs/).

## Contributing

Issues and pull requests are welcome. Please:

- Follow the apeek-kit workflow above — start from a spec, not from code.
- Run `xcodebuild test -project Verborra.xcodeproj -scheme Verborra` before opening a PR.
- Keep changes focused — one feature or fix per PR.
- For larger changes, open an issue first to discuss approach.

## License

[MIT](LICENSE)
