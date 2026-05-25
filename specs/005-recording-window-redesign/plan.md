# Implementation Plan: Recording Floating Window Redesign

**Branch**: `005-recording-window-redesign` | **Date**: 2026-03-15 | **Spec**: [spec.md](spec.md)
**Input**: Specification from `specs/005-recording-window-redesign/spec.md`

## Summary

Complete rework of the recording floating window from a single-screen widget (480×400, static result) into a two-state chat interface (800×250 → dynamic height, streaming LLM, iterative refinement). Affects data models, the UI layer, formatting services (adding SSE streaming), hotkey management, and the copy/paste system.

## Technical context

**Language/Version**: Swift 5.9+ (Xcode 15+)
**Main dependencies**: SwiftUI, AppKit (NSPanel), AVFoundation (AVAudioEngine), swift-markdown (swiftlang, 0.4.0+), KeyboardShortcuts (sindresorhus, 2.0.0+)
**Storage**: UserDefaults/@AppStorage (settings), macOS Keychain (API key), in-memory (chat session)
**Testing**: XCTest / Swift Testing
**Target platform**: macOS 15 (Sequoia), macOS 26 (Tahoe) and above
**Project type**: macOS desktop app (single target)
**Performance goals**: <300 ms from hotkey to window readiness (Principle 3), 60 fps animations, streaming LLM token-by-token
**Constraints**: Max window height = 50% of screen, max input = 5 lines, min recording = 2 sec, max recording = 20 min by default (1/5/10/20/60 min), light theme only
**Scale**: ~18 unique files to modify/create + 4 test files (8 new models/services, 5 new views, 4 modifications, 1 deletion), ~4800 lines of existing code

## Constitution check

*GATE: Check before Phase 0. Recheck after Phase 1.*

| Principle | Status | Comment |
|---------|--------|-------------|
| 1. Native macOS experience | PASS | SwiftUI + NSPanel, SF Symbols (FR-058), native paste mechanisms |
| 2. Swift-first development | PASS | All code in Swift 5.9+, MVVM + @Observable, URLSession async/await for streaming |
| 3. Minimalism and simplicity | PASS | No new dependencies, swift-markdown and KeyboardShortcuts are reused |
| 4. Security and privacy | PASS | Audio in-memory, API key in Keychain, chat not persisted |
| 5. Code quality and testing | PASS | Unit tests for ChatSession, streaming, context truncation |

**All gates passed. No violations.**

## Project structure

### Documentation (this feature)

```text
specs/005-recording-window-redesign/
├── spec.md              # Specification (59 FR, 7 scenarios)
├── plan.md              # This file
├── research.md          # Research on technical decisions
├── data-model.md        # Data model (in-memory)
├── quickstart.md        # Brief overview of changes
├── contracts/
│   └── internal-api.md  # Internal contracts between components
└── tasks.md             # Generated via /speckit.tasks
```

### Source code (repository root)

```text
Verborra/
├── Models/
│   ├── ChatMessage.swift           # NEW: chat message model
│   ├── ChatSession.swift           # NEW: chat session with context truncation
│   ├── WindowPhase.swift           # NEW: window phase enum (state 1/2)
│   ├── InputRecordingState.swift   # NEW: voice input recording state in input
│   ├── TokenEstimator.swift        # NEW: token counting heuristic
│   ├── RecordingState.swift        # MODIFY: transcribing/formatting instead of processing
│   ├── TranscriptionResult.swift   # MODIFY: simplification (formattedText → ChatMessage)
│   ├── AppSettings.swift           # NO CHANGES
│   ├── SystemPrompt.swift          # NO CHANGES
│   ├── SupportedLanguage.swift     # NO CHANGES
│   ├── LLMModel.swift              # NO CHANGES
│   └── ...
├── Services/
│   ├── StreamingFormattingService.swift  # NEW: SSE streaming for Chat Completions
│   ├── TargetAppTracker.swift           # NEW: tracking the active application
│   ├── MarkdownStripper.swift           # NEW: plain text from Markdown
│   ├── FormattingService.swift          # NO CHANGES (fallback for non-streaming, voice input in input)
│   ├── PasteService.swift               # MODIFY: Markdown/plain text modes, close-on-action
│   ├── AudioCaptureService.swift        # NO CHANGES
│   ├── TranscriptionService.swift       # NO CHANGES
│   ├── HotkeyService.swift              # NO CHANGES
│   ├── PermissionManager.swift          # NO CHANGES
│   └── ...
├── ViewModels/
│   └── RecordingViewModel.swift    # REWORK: two-phase logic, chat, streaming, input
├── Views/
│   ├── OverlayPanel.swift          # REWORK: 800×250, dynamic height, 16px corners, no shadow/border
│   ├── OverlayContentView.swift    # REWORK: new structure with ControlBar
│   ├── RecordingView.swift         # REWORK: new state design
│   ├── ResultView.swift            # REMOVED → replaced by ChatView
│   ├── ChatView.swift              # NEW: chat bubble container with ScrollView
│   ├── ChatBubbleView.swift        # NEW: message bubble (system — full width; transcription/user — 70% right; assistant — 70% left; no internal scroll, height by content)
│   ├── ControlBarView.swift        # NEW: bottom control block (state 1/2 configurations)
│   ├── InputFieldView.swift        # NEW: text/voice input field
│   ├── Components/
│   │   ├── MarkdownTextView.swift  # NEW: read-only Markdown rendering for bubbles
│   │   ├── AudioWaveformView.swift # MODIFY: color #9A9A9A, full width, 12px bar rounding
│   │   ├── PromptSelectorView.swift# REWORK: dropdown in content area
│   │   ├── LanguageSelectorView.swift # REWORK: buttons in bottom block
│   │   ├── MicrophoneSelectorButton.swift # NEW: microphone selector button in bottom block
│   │   └── HotkeyRecorder.swift    # NO CHANGES
│   └── ...
└── VerborraApp.swift               # MODIFY: update ViewModel initialization

VerborraTests/
├── Models/
│   ├── ChatSessionTests.swift      # NEW: tests for context truncation
│   └── TokenEstimatorTests.swift   # NEW: tests for token heuristic
├── Services/
│   └── StreamingFormattingServiceTests.swift  # NEW: tests for SSE parsing
└── ViewModels/
    └── RecordingViewModelTests.swift  # MODIFY: new scenarios
```

**Structure decision**: Single project (single target), the existing Models/Services/ViewModels/Views structure is preserved. New files are added to existing directories by type.

## Complexity tracking

No constitution violations detected. Table not filled.

## Key architectural decisions

### 1. Two-phase state model

The current `RecordingState` (5 cases) is replaced by a two-level system:
- `WindowPhase`: `.preProcessing` (state 1) / `.postProcessing` (state 2) — determines the set of buttons and available hotkeys
- `RecordingState`: `.idle` / `.recording` / `.transcribing` / `.formatting` / `.error` — determines the content area contents
- `InputRecordingState`: `.idle` / `.recording` / `.processing` — voice input state in input

### 1a. Session-scoped window settings

Microphone, input language, and output language settings are stored in `RecordingViewModel` as session-scoped properties (`selectedAudioDeviceID`, `selectedVoiceLanguage`, `selectedTextLanguage`). On window opening, they are initialized from the global `AppSettings`. Changes within the session are not persisted — on closing and reopening, they reset to global values. The window receives focus immediately (`becomesKeyOnlyIfNeeded = false`).

### 2. Streaming LLM via SSE

The new `StreamingFormattingService` uses `URLSession.bytes(for:)` for line-by-line reading of SSE. Returns `AsyncThrowingStream<String, Error>`. The ViewModel subscribes and updates `ChatMessage.content` on `@MainActor` as tokens arrive.

### 3. Chat session with context truncation

`ChatSession` stores `[ChatMessage]` in memory. When sending to LLM:
1. The system prompt is always included
2. Token estimation: ~3 characters ≈ 1 token (conservative for Cyrillic)
3. Budget = 80% of model limit − system prompt tokens
4. If total tokens exceed the budget — old user/assistant pairs are removed

### 4. Dynamic window height

`OverlayPanel` starts at 800×250. On transition to postProcessing (state 2), the window immediately expands up to 50% of screen height (the bottom edge is fixed). Synchronization: SwiftUI `onGeometryChange` → `OverlayManager.updateHeight()` → `NSAnimationContext` frame animation. Maximum = 50% `visibleFrame.height`.

### 5. Target application tracking

`TargetAppTracker` subscribes to `NSWorkspace.didActivateApplicationNotification`. On window opening, captures the current application. On change of active application (except Verborra), updates `targetPID`. Used with `⌥V`/`⌥⇧V` for pasting.

### 6. Copy: Markdown vs Plain Text

- `⌥C`: copies source Markdown text of the last LLM message → closes window
- `⌥⇧C`: copies plain text (Markdown stripped via swift-markdown MarkupWalker) → closes window
- `⌥V`/`⌥⇧V`: similar, but with paste via Accessibility API into the target application

### 7. Icons

FR-058 requires SF Symbols. All icons MUST use filled variants:
- `mic.fill` — microphone
- `waveform.circle.fill` — input language
- `text.bubble.fill` — output language
- `play.fill` / `stop.fill` — Start/Stop
- `xmark.circle.fill` — Exit
- `doc.on.doc.fill` — copy
- `doc.on.clipboard.fill` — paste
- `pencil.circle.fill` — edit
- `checkmark.circle.fill` — confirm edit
- `chevron.down.circle.fill` / `chevron.up.circle.fill` — collapse/expand
- `arrow.clockwise.circle.fill` — retry
- `questionmark.circle.fill` — Accessibility ?
- `rectangle.portrait.and.arrow.right.fill` — Exit (alt.)
- `sparkles.rectangle.stack.fill` — system prompt
- `gearshape.fill` — settings

## Component dependencies

```
ChatMessage, ChatSession, WindowPhase, InputRecordingState, TokenEstimator
    ↓ (models — no dependencies)
StreamingFormattingService, TargetAppTracker, MarkdownStripper
    ↓ (services — depend on models)
RecordingViewModel (rework)
    ↓ (depends on models + services)
OverlayPanel, ControlBarView, ChatView, ChatBubbleView, InputFieldView, MarkdownTextView
    ↓ (UI — depends on ViewModel)
OverlayContentView (composition)
    ↓
VerborraApp (entry point)
```

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|---------|-----------|
| NSPanel frame animation does not sync with SwiftUI layout | Medium | Medium | Throttle updates via 50ms debounce |
| SSE parsing fragile on non-standard OpenAI responses | Low | High | Fallback to non-streaming on parsing error |
| Hotkeys `⌥C`/`⌥V` conflict with macOS symbols when focus is on NSTextView | High | High | Interception via `NSEvent.addLocalMonitorForEvents` at the application level — works regardless of focus, blocking of `ç`/`√` symbols |
| Token counting heuristic is inaccurate | Low | Low | Conservative estimate (3 chars/token), the user does not get an error |
