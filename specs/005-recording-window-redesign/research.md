# Research: Recording Floating Window Redesign

**Feature Branch**: `005-recording-window-redesign`
**Date**: 2026-03-15

## R-001: SSE Streaming for LLM responses

**Decision**: Use `URLSession.bytes(for:)` for streaming OpenAI Chat Completions API responses

**Rationale**: The specification requires (FR-035) streaming output of LLM responses — token by token. The current implementation (`FormattingService`) uses a regular HTTP request and returns the full response. For streaming, we need to:
- Add the `"stream": true` parameter to the OpenAI API request
- Parse the SSE format: `data: {"choices":[{"delta":{"content":"token"}}]}`
- Detect end of stream: `data: [DONE]`
- Update the `@Observable` property on `@MainActor` via `AsyncThrowingStream`

**Implementation pattern**:
```swift
func streamFormat(...) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        Task {
            let (bytes, response) = try await session.bytes(for: request)
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let json = String(line.dropFirst(6))
                if json == "[DONE]" { continuation.finish(); return }
                // parse delta.content, yield token
                continuation.yield(token)
            }
            continuation.finish()
        }
    }
}
```

**Alternatives**: WebSocket — overkill, OpenAI does not support; Combine Publisher — outdated pattern for macOS 15+; EventSource libraries (LDSwiftEventSource) — violate Principle 2 (minimum dependencies).

---

## R-002: Global hotkey (`⌥Space`)

**Decision**: Keep the current approach with `KeyboardShortcuts` (sindresorhus) with the default hotkey `⌥Space` (Option+Space)

**Rationale**: The `Fn` key on macOS has special status:
- `NSEvent.ModifierFlags.function` exists, but Fn physically remaps keys (Fn+Space = Spotlight/Dictation in macOS 15+)
- `KeyboardShortcuts` library does NOT support Fn as a modifier
- Apple uses Fn+Space for system dictation starting with macOS 15

The current default hotkey `⌥Space` is already correct and matches the specification (FR-005).

**Alternatives**: `CGEventTapCreate` for intercepting Fn — unsafe, requires Accessibility, conflicts with Apple's system hotkeys.

---

## R-003: Icons — SF Symbols

**Decision**: Use system SF Symbols (FR-058)

**Rationale**: The specification explicitly requires SF Symbols. This is Apple's native icon set, requiring no additional resources — available via `Image(systemName:)` in SwiftUI. Supports automatic scaling, tinting, and conforms to Human Interface Guidelines (Principle 1).

**Icon mapping** (all icons — filled variants):

| Function | SF Symbol | Usage |
|---------|-----------|---------------|
| Microphone | `mic.fill` | Audio source selection (button `1`) |
| Input language | `waveform.circle.fill` | Input language button (`2`) |
| Output language | `text.bubble.fill` | Output language button (`3`) |
| Start | `play.fill` | Start recording |
| Stop | `stop.fill` | Stop recording |
| Copy | `doc.on.doc.fill` | Copy text (`⌥C`) |
| Paste | `doc.on.clipboard.fill` | Paste text (`⌥V`) |
| Edit | `pencil.circle.fill` | Edit last LLM message |
| Confirm | `checkmark.circle.fill` | Confirm edit |
| Cancel | `xmark.circle.fill` | Cancel edit |
| Close | `rectangle.portrait.and.arrow.right.fill` | Exit button (`Escape`) |
| Expand | `chevron.down.circle.fill` | Expand collapsed bubble |
| Collapse | `chevron.up.circle.fill` | Collapse bubble |
| Send | `arrow.up.circle.fill` | Send message from input |
| Retry | `arrow.clockwise.circle.fill` | Retry on error |
| Question | `questionmark.circle.fill` | Icon for Accessibility (`?`) |
| Stop input recording | `stop.circle.fill` | Replaces mic/send during voice input |
| Settings | `gearshape.fill` | Navigate to settings |
| System prompt | `sparkles.rectangle.stack.fill` | Prompt icon |

**Alternatives**: Tabler Icons SVG in Asset Catalog — additional resources, violates Principle 1 (native experience).

---

## R-004: Dynamic NSPanel height with animation

**Decision**: Use `NSAnimationContext` for smooth NSPanel frame changes with fixed bottom edge

**Rationale**: The specification requires (FR-004, FR-036) upward window expansion on transition to postProcessing:
- Initial size: 800×250 px
- On transition to state 2 (postProcessing): immediate expansion up to 50% of screen height
- Bottom edge is fixed, top rises
- When content overflows: scroll inside the content area

**Key observation**: In macOS the coordinate system has the origin in the lower-left corner. `frame.origin.y` — this is the bottom edge of the window. Therefore, to expand upward it is enough to increase `frame.size.height`, leaving `origin.y` unchanged — the window grows upward automatically.

**Implementation pattern**:
```swift
func updatePanelHeight(to newHeight: CGFloat) {
    guard let panel = panel, let screen = panel.screen else { return }
    let maxHeight = screen.visibleFrame.height * 0.5
    let height = min(newHeight, maxHeight)
    var newFrame = panel.frame
    newFrame.size.height = height
    // origin.y stays unchanged → window grows up (macOS coords)
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.25
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        panel.animator().setFrame(newFrame, display: true, animate: true)
    }
}
```

**Synchronization mechanism**: SwiftUI content reports required size via `onGeometryChange` (macOS 15+). OverlayManager receives the callback and calls `updatePanelHeight`. Debounce 50 ms to prevent excessive updates during streaming.

**Important**: `withAnimation {}` in SwiftUI does NOT affect NSPanel frame — for window animation only `NSAnimationContext` is used.

**Alternatives**:
- `window.contentMinSize`/`contentMaxSize` — gives no control over expansion direction
- SwiftUI `.frame()` with a fixed window — no window frame animation
- GeometryReader + PreferenceKey — works, but `onGeometryChange` is recommended by Apple for macOS 15+

---

## R-005: Target application tracking

**Decision**: Use `NSWorkspace.shared.notificationCenter` + `didActivateApplicationNotification` for dynamic tracking

**Rationale**: The specification requires (FR-056a-c) dynamic tracking of the active application:
- On window opening — capture the current application
- On change of active application in the background — update the target
- Exclude the floating window itself from tracking

**Pattern**:
```swift
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, ...
) { notification in
    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
          app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
    self.targetPID = app.processIdentifier
}
```

The current implementation captures the PID only on `show()` — it is necessary to extract this into a separate `TargetAppTracker` with notification subscription.

**Alternatives**: Polling via `NSWorkspace.shared.frontmostApplication` — less efficient, battery drain.

---

## R-006: Chat model and context management

**Decision**: New `ChatMessage` + `ChatSession` model with token-oriented truncation

**Rationale**: The current `TranscriptionResult` stores a single result. The specification requires (Scenario 2, FR-044a):
- Multiple messages (system prompt, transcription, LLM responses, user messages)
- Iterative refinement via chat
- Truncation of old messages when approaching the context limit (80% of the provider limit)

**Token counting**: Heuristic `~3 characters ≈ 1 token` (conservative for mixed Russian/English text). Without external libraries (SwiftTiktoken and similar — heavy dependencies, ~4MB of data).

**Context limits by model**:
| Model | Context | 80% budget |
|--------|----------|------------|
| gpt-4.1-nano | 1M tokens | 800K |
| gpt-4o-mini | 128K tokens | 102K |
| gpt-4.1-mini | 1M tokens | 800K |
| gpt-5-nano | 1M tokens | 800K |
| gpt-5-mini | 1M tokens | 800K |

**Truncation strategy**: remove old user/assistant pairs, preserving the system prompt and the last N messages, until total tokens fit within the budget.

**Alternatives**:
- Summarization (summarizing old messages) — more complex, adds an API call
- Fixed window (last 10 messages) — does not fully utilize the available context

---

## R-007: Markdown rendering in chat bubbles

**Decision**: Use the existing `MarkdownEditorView` (NSTextView + swift-markdown) with adaptation for read-only mode

**Rationale**:
- The `swift-markdown` library is already connected and used in `ResultView`
- The current `MarkdownEditorView` supports styling (headings, bold, italic, code, lists)
- For chat bubbles a read-only variant is needed (without editable)
- For the last LLM message — an editable variant (FR-041)

**Changes**: Extract common Markdown rendering into a separate `MarkdownTextView` component with an `isEditable: Bool` parameter.

**Alternatives**:
- AttributedString (SwiftUI native) — limited Markdown support
- WKWebView — violates Principle 1 (native macOS experience)

---

## R-008: Removing Markdown formatting for plain text copy

**Decision**: Use `swift-markdown` for parsing and extracting plain text via a custom `MarkupWalker`

**Rationale**: The specification requires (FR-053) two copy modes:
- `⌥C` — source Markdown text
- `⌥⇧C` — plain text without formatting characters

**Pattern**:
```swift
struct PlainTextExtractor: MarkupWalker {
    var result = ""
    mutating func visitText(_ text: Text) { result += text.string }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { result += " " }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { result += "\n" }
    mutating func visitParagraph(_ paragraph: Paragraph) -> () {
        descendInto(paragraph)
        result += "\n\n"
    }
}
```

**Alternatives**: Regex replacement (`**`, `_`, `#`, etc.) — a fragile solution, does not cover all Markdown edge cases.

---

## R-009: Window state architecture

**Decision**: Two-level model — `WindowPhase` (state 1 / state 2) + `RecordingState` (idle / recording / transcribing / formatting)

**Rationale**: The specification defines two main window states with different button and hotkey sets:
- **State 1** (preProcessing): settings, recording, prompt — buttons: microphone, languages, Start/Stop, Exit
- **State 2** (postProcessing): chat, input, copy/paste — buttons: Copy, Paste, Start/Stop, Exit

The current `RecordingState` mixes window states and the recording process state. Splitting into `WindowPhase` and `RecordingState` simplifies the logic of displaying buttons and handling hotkeys.

Additionally, `InputRecordingState` for voice input into the input (state 2) — separate from the main recording.

`processing` is split into `transcribing` and `formatting` for the two-stage indicator (FR-035).

**Alternatives**: Leave a single enum — complicates the logic of transitions and display conditions.

---

## R-010: 16px corner rounding

**Decision**: SwiftUI `.clipShape(RoundedRectangle(cornerRadius: 16))` for the main content and `UnevenRoundedRectangle` for the bottom block

**Rationale**: The current implementation already uses `.clipShape(RoundedRectangle(cornerRadius: 16))`. NSPanel with `borderless` style and a transparent background allows full shape control via SwiftUI content.

For the bottom control block — `UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)` (straight top corners, rounded bottom).

---

## R-011: Minimum recording duration (2 seconds)

**Decision**: Block the Stop button and `⌥Space` hotkey (stop) until the 2-second threshold is reached

**Rationale**: FR-033a requires a minimum of 2 seconds before stopping. Applies to both recording types (main and voice input into the input).

**Pattern**: In `RecordingViewModel`, check `duration >= 2.0` before calling `stopRecording()`. In the UI, the Stop button is displayed as disabled until the threshold is reached.

---

## R-012: Bottom control block design

**Decision**: A `ControlBarView` component with two configurations depending on `WindowPhase`

**Rationale**: The bottom block changes drastically between states:
- **State 1**: [Microphone `1`] [Input language `2`] [Output language `3`] ... [Start/Stop `⌥Space`] [Exit `Esc`]
- **State 2**: [Copy `⌥C`] [Paste `⌥V`] ... [Start/Stop `⌥Space`] [Exit `Esc`]

Each button is a `ControlButton` with action text and hotkey badge. Clicking performs the same action as the hotkey (FR-017).

**Visual parameters** (FR-003, FR-016):
- Block background: `#F4F4F4`
- Button background: `#DCDCDC`
- Button text: `#2C2C2C`
- Shortcut badge background: `#F4F4F4`
- Hover: `#D0D0D0`
- Disabled: background `#EBEBEB`, text `#ACACAC`
- Rounding: bottom corners 16px, top straight
