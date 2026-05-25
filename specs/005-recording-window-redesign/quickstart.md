# Quickstart: Recording Floating Window Redesign

**Feature Branch**: `005-recording-window-redesign`
**Date**: 2026-03-15

## What changes

Complete rework of the recording floating window from a single-screen widget into a two-state chat interface:

- **Window**: 480×400 (fixed) → 800×250 (dynamic height, upward expansion)
- **Process**: record → result → copy → record → chat → iterations → copy
- **Output**: static text → streaming (token by token)
- **Visual**: NSVisualEffect blur → custom design with color palette, SF Symbols filled variants (FR-058), 16px corners, no shadow and no border
- **Controls**: simple buttons → bottom block with hotkey badges, dropdowns
- **Hotkeys**: `⌥C`/`⌥V` (Markdown), `⌥⇧C`/`⌥⇧V` (plain text), `⌥Space` (recording)

## Key files to modify

### Full rework (rewrite)

| File | Reason |
|------|---------|
| `Views/OverlayPanel.swift` | New size 800×250, dynamic height (immediately 50% on postProcessing), 16px corners, no shadow/border, 5% from bottom |
| `Views/OverlayContentView.swift` | New structure: content area + ControlBar + InputField |
| `Views/RecordingView.swift` | New design: full-width equalizer, countdown timer, two processing stages |
| `Views/ResultView.swift` | Replaced by `ChatView` with message bubbles |
| `ViewModels/RecordingViewModel.swift` | Two-phase model, chat session, streaming, input, new hotkeys |
| `Models/RecordingState.swift` | New states: transcribing, formatting; result(text:) removed |

### New files

| File | Purpose |
|------|------------|
| `Models/ChatMessage.swift` | Chat message model (role, content, isCollapsed, isEditing, isStreaming) |
| `Models/ChatSession.swift` | Chat session with token-based context truncation |
| `Models/WindowPhase.swift` | Window phase enum (preProcessing / postProcessing) |
| `Models/InputRecordingState.swift` | Voice input recording state in input |
| `Models/TokenEstimator.swift` | Token counting heuristic (~3 chars/token) |
| `Views/ChatView.swift` | ScrollView with LazyVStack for chat bubbles |
| `Views/ChatBubbleView.swift` | Message bubble (system, transcription, user, assistant) |
| `Views/ControlBarView.swift` | Bottom control block (two configurations: state 1/2) |
| `Views/InputFieldView.swift` | Input field: text + voice, 1-5 lines, Enter/Shift+Enter |
| `Views/Components/MarkdownTextView.swift` | Read-only Markdown rendering for bubbles |
| `Services/StreamingFormattingService.swift` | SSE streaming for Chat Completions API |
| `Services/TargetAppTracker.swift` | Dynamic tracking of the active application |
| `Services/MarkdownStripper.swift` | Extracting plain text from Markdown via swift-markdown |

### Modify (extend)

| File | Change |
|------|-----------|
| `Services/PasteService.swift` | Two modes: Markdown / plain text; close-on-action |
| `Views/Components/AudioWaveformView.swift` | Color `#9A9A9A`, full content area width |
| `Views/Components/PromptSelectorView.swift` | Dropdown in content area (on click on the name) |
| `Views/Components/LanguageSelectorView.swift` | Buttons in the bottom block with hotkeys `2`/`3` |
| `VerborraApp.swift` | Update ViewModel initialization (StreamingFormattingService, TargetAppTracker) |

### Not affected

| File | Reason |
|------|---------|
| `Services/AudioCaptureService.swift` | Reused as is |
| `Services/TranscriptionService.swift` | Reused as is |
| `Services/HotkeyService.swift` | `⌥Space` is already the default hotkey |
| `Services/PermissionManager.swift` | Reused as is |
| `Models/AppSettings.swift` | All settings are already covered |
| `Models/SystemPrompt.swift` | No changes |
| `Models/SupportedLanguage.swift` | No changes |
| `Models/LLMModel.swift` | No changes |

## Architectural decisions

1. **Streaming**: `URLSession.bytes(for:)` + `AsyncThrowingStream<String, Error>` → updating `ChatMessage.content` on `@MainActor`
2. **Dynamic height**: `onGeometryChange` (macOS 15+) → `OverlayManager.updateHeight()` → `NSAnimationContext`
3. **Chat**: `ChatSession` — in-memory `[ChatMessage]` with token-based truncation (80% of model context)
4. **Icons**: SF Symbols filled variants — Apple's native set, no extra resources
5. **Markdown plain text**: `swift-markdown` + `MarkupWalker` for extracting clean text
6. **Target app**: `NSWorkspace.didActivateApplicationNotification` — event-based approach, not polling
7. **Two-phase state**: `WindowPhase` (buttons/hotkeys) + `RecordingState` (content) + `InputRecordingState` (input)

## Implementation order

1. **Data models** — ChatMessage, ChatSession, WindowPhase, InputRecordingState, TokenEstimator, RecordingState (modify)
2. **StreamingFormattingService** — SSE streaming for OpenAI API
3. **TargetAppTracker** — tracking the active application
4. **MarkdownStripper** — plain text from Markdown
5. **OverlayPanel** — new size, dynamic height, 16px corners
6. **UI components** — ControlBarView, ChatBubbleView, MarkdownTextView, InputFieldView
7. **ChatView** — chat bubble container with autoscroll
8. **RecordingView** — new design idle/recording/transcribing/formatting
9. **RecordingViewModel** — two-phase logic, chat session, hotkeys, streaming
10. **Composition** — OverlayContentView integration
11. **Copy/Paste** — two modes (⌥C/⌥V and ⌥⇧C/⌥⇧V)
12. **Tests** — ChatSession, TokenEstimator, StreamingFormattingService, hotkeys
