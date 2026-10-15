# Verborra

macOS voice-input app (Swift / SwiftUI). Features are developed with [GitHub Spec Kit](https://github.com/github/spec-kit) v1.2.0.

## Spec Kit Workflow

```
constitution → specify → [clarify] → plan → [checklist] → tasks → [analyze] → implement → [converge]
```

| Skill                     | Purpose                                              |
| ------------------------- | ---------------------------------------------------- |
| `/speckit-constitution`   | Create/update project principles                     |
| `/speckit-specify`        | Create feature spec from description                 |
| `/speckit-clarify`        | Ask clarifying questions, update spec (optional)     |
| `/speckit-plan`           | Generate technical plan + research                   |
| `/speckit-checklist`      | Generate requirement quality checklists (optional)   |
| `/speckit-tasks`          | Break plan into actionable tasks                     |
| `/speckit-analyze`        | Cross-artifact consistency check (optional)          |
| `/speckit-implement`      | Execute tasks from tasks.md                          |
| `/speckit-converge`       | Assess codebase and append remaining work as tasks   |
| `/speckit-taskstoissues`  | Convert tasks to GitHub issues                       |

- Skills: `.claude/skills/speckit-*/`
- Scripts, templates, workflows: `.specify/`
- Project principles: `.specify/memory/constitution.md`
- Feature specs: `specs/NNN-feature-name/` (branch naming `NNN-short-name`)

## Active Technologies
- SwiftUI, AppKit (NSPanel), AVFoundation (AVAudioEngine), Security (Keychain), ServiceManagement (SMAppService), swift-markdown (swiftlang), KeyboardShortcuts (sindresorhus) (001-voice-input)
- UserDefaults (simple settings), macOS Keychain (API key), JSON in Application Support (named prompts) (001-voice-input)
- Swift 5.9+ + SwiftUI, AVFoundation (AVCaptureDevice), AppKit (AXIsProcessTrusted, NSWorkspace), Observation framework (004-permissions-rework)
- UserDefaults / @AppStorage (settings), macOS Keychain (API key) (004-permissions-rework)
- Swift 5.9+ (Xcode 15+) + SwiftUI, AppKit (NSPanel, NSWindow, NSAlert), AVFoundation (AVCaptureDevice), Accessibility API (AXIsProcessTrusted) (004-permissions-rework)
- Swift 5.9+ (Xcode 15+) + os.Logger (Unified Logging System), Foundation (FileHandle, DispatchQueue) (007-diagnostic-logging)
- JSONL files in ~/Library/Application Support/Verborra/Logs/; UserDefaults for level configuration (007-diagnostic-logging)
- Swift 5.9+ (Xcode 15+) + AVFoundation (AVAudioEngine), CoreAudio (AudioObjectPropertyListenerBlock), swift-atomics (NEW — apple/swift-atomics 1.2.0+), swift-markdown (0.4.0+), KeyboardShortcuts (2.0.0+) (008-fix-async-concurrency)
- N/A (in-memory audio buffers, UserDefaults for settings) (008-fix-async-concurrency)
- Swift 5.9+ (Xcode 15+) + SwiftUI, AVFoundation, swift-markdown (0.4.0+), KeyboardShortcuts (2.0.0+), swift-atomics (1.2.0+) (012-vocabularies)
- JSON files in `~/Library/Application Support/Verborra/` (vocabularies.json); UserDefaults / @AppStorage (personal preferences text) (012-vocabularies)
- Swift 5.9+ (Xcode 15+) + SwiftUI, AppKit (NSPanel, NSAlert), AVFoundation (AVAudioEngine — уже используется), swift-markdown (4.0+ — уже используется для рендеринга), KeyboardShortcuts (sindresorhus — уже используется), swift-atomics (1.2+ — уже используется в стриминге) (013-dictation-flow-rework)
- JSON файл `~/Library/Application Support/Verborra/system_prompts.json` (через существующий `PromptsStore`); UserDefaults для `promptsDataVersion` (013-dictation-flow-rework)
- Swift 5.9+ (Xcode 15+) + SwiftUI, AppKit (NSPanel), AVFoundation (AVAudioEngine), swift-markdown (4.0+), KeyboardShortcuts (sindresorhus), swift-atomics (1.2+) — all already in the project; no additions. (014-voice-level-and-language)
- UserDefaults / `@AppStorage` (Settings default for response language — existing `AppSettings.globalTextLanguage`). The floating-window override is in-memory only on `RecordingViewModel`. The new structured language-resolution event is logged via the existing JSONL diagnostic logging system (spec 007, `~/Library/Application Support/Verborra/Logs/`). (014-voice-level-and-language)
- Swift 5.9+ + ServiceManagement (SMAppService status), CoreGraphics CGEventTap (Fn hotkey, background thread), Carbon (RegisterEventHotKey/CopySymbolicHotKeys), one Objective-C NSException shim; storage UserDefaults (`globalShortcut.v1`, `launchAtLogin` intent, `selectedSTTModelRawValue`/`selectedLLMModelRawValue`); OpenAI model catalog with per-model request options (no new dependencies) (015-reliability-shortcuts-models)

## Recent Changes
- 001-voice-input: Added SwiftUI, AppKit (NSPanel), AVFoundation (AVAudioEngine), Security (Keychain), ServiceManagement (SMAppService), swift-markdown (swiftlang), KeyboardShortcuts (sindresorhus)
