# Internal Contracts: Recording Floating Window Redesign

**Feature**: 005-recording-window-redesign
**Date**: 2026-03-15

> macOS application without external APIs - contracts define internal protocols and interfaces between components.

## Service Protocols

### StreamingFormattingServiceProtocol (NEW)

Extension of `FormattingServiceProtocol` for streaming responses.

```swift
protocol StreamingFormattingServiceProtocol: FormattingServiceProtocol {
    /// Streaming text formatting via LLM.
    /// Returns AsyncThrowingStream with tokens.
    func streamFormat(
        text: String,
        systemPrompt: String,
        textLanguage: SupportedLanguage,
        model: LLMModel
    ) -> AsyncThrowingStream<String, Error>

    /// Streaming chat with message history.
    /// Returns AsyncThrowingStream with tokens.
    func streamChat(
        messages: [(role: String, content: String)],
        model: LLMModel
    ) -> AsyncThrowingStream<String, Error>

    /// Cancel the current streaming request.
    func cancelStream()
}
```

**Contract**:
- `streamFormat`: sends a request with `"stream": true`, returns tokens as they are received
- `streamChat`: sends the full message history, returns tokens
- `cancelStream`: cancels the URLSession task, terminates the stream
- On error: throws the error into the stream, does not block future requests

### ChatSessionProtocol (NEW)

Chat session management. Implementation - `@Observable class ChatSession` (reference semantics for SwiftUI binding).

```swift
protocol ChatSessionProtocol {
    var messages: [ChatMessage] { get }

    /// Add a message to the history.
    func addMessage(_ message: ChatMessage)

    /// Update the contents of the last assistant message (for streaming).
    func updateLastAssistantContent(_ content: String)

    /// Prepare the array of messages to be sent to the LLM
    /// taking context truncation into account.
    func prepareMessagesForLLM(
        maxTokenBudget: Int,
        systemPromptTokens: Int
    ) -> [(role: String, content: String)]

    /// Get the text of the last assistant message.
    var lastAssistantMessage: ChatMessage? { get }

    /// Reset the session.
    func reset()
}
```

**Truncation contract** (FR-044a):
- Input: `maxTokenBudget` = 80% of the model's limit
- The system prompt is always included first
- Messages are added from the end (most recent) while `totalTokens < maxTokenBudget`
- Token estimation: `content.count / 3` (conservative, ~3 characters = 1 token for Cyrillic)
- Returns an array of `[{role, content}]` for the OpenAI API

### PasteServiceProtocol (EXTENSION)

```swift
protocol PasteServiceProtocol {
    func pasteText(_ text: String) async throws
    func copyToClipboard(_ text: String)

    /// NEW: Copy plain text (without Markdown markup) to the clipboard.
    func copyPlainTextToClipboard(_ markdownText: String)

    /// NEW: Paste plain text (without Markdown) into the target application.
    func pastePlainText(_ markdownText: String) async throws
}
```

### OverlayPanelProtocol (NEW)

```swift
protocol OverlayPanelSizing {
    /// Update the panel height with animation.
    /// The bottom edge is fixed, expansion goes upward.
    func updateHeight(to newHeight: CGFloat, animated: Bool)

    /// Maximum allowed height (50% of the screen).
    var maxAllowedHeight: CGFloat { get }

    /// Current height.
    var currentHeight: CGFloat { get }
}
```

## View Component Interfaces

### ControlBarView

```swift
// Input data
struct ControlBarView: View {
    let windowPhase: WindowPhase
    let recordingState: RecordingState
    let inputRecordingState: InputRecordingState
    let hasAccessibility: Bool

    // Callbacks
    let onMicrophoneSelect: (String) -> Void      // deviceID
    let onInputLanguageSelect: (SupportedLanguage) -> Void
    let onOutputLanguageSelect: (SupportedLanguage) -> Void
    let onStartStop: () -> Void
    let onExit: () -> Void
    let onCopy: (Bool) -> Void                     // withMarkdown
    let onPaste: (Bool) -> Void                     // withMarkdown
}
```

**Visual contract** (FR-016..FR-020):
- Background: `#F4F4F4`
- Bottom corners: 16px rounding
- Top corners: straight
- No padding from window edges (left, bottom, right)
- No shadow or border around the window
- All buttons (selectors and actions) MUST use a single visual style via the shared ControlBarButtonLabel
- Buttons: background `#DCDCDC`, text `#2C2C2C`, badges `#F4F4F4`
- Hover: `#D0D0D0`
- Disabled: background `#EBEBEB`, text `#ACACAC`
- Icons: SF Symbols filled variants

### ChatView

```swift
struct ChatView: View {
    let messages: [ChatMessage]
    let onToggleCollapse: (UUID) -> Void
    let onEditMessage: (UUID) -> Void
    let onCancelEdit: (UUID) -> Void
    let onConfirmEdit: (UUID, String) -> Void
    let onCopyMessage: (UUID) -> Void
}
```

**Visual contract**:
- Background of all bubbles: `#F4F4F4`
- Bubble text: `#2F2F2F`
- No scrolling inside bubbles - height adapts to the content
- System bubbles: full width, collapsed, chevron.down.circle.fill/chevron.up.circle.fill icon
- Transcription/User bubbles: 70% width, right-aligned; Transcription collapsed
- Assistant bubbles: 70% width, left-aligned
- Last assistant bubble: pencil.circle.fill (Edit) + doc.on.doc.fill (Copy) icons
- Other bubbles: only the doc.on.doc.fill (Copy) icon
- Container scrolls on overflow

### InputFieldView

```swift
struct InputFieldView: View {
    @Binding var text: String
    let inputRecordingState: InputRecordingState
    let audioLevel: Float
    let isEnabled: Bool                // Disabled during processing

    let onSend: () -> Void
    let onStartVoice: () -> Void
    let onStopVoice: () -> Void
}
```

**Visual contract** (FR-045..FR-050):
- Padding: 12px bottom, left, right
- Initial height: 1 line
- Maximum height: 5 lines (scrolling beyond)
- During voice input: equalizer + timer inside the field
- Icons: microphone + send -> "Stop" button while recording

## Hotkey Contract

### Hotkey mapping by state

```
Hotkey         | State 1            | State 2            | Focus on input
─────────────────────────────────────────────────────────────────────────────
Option+Space*  | Start/Stop          | Voice to input     | Voice to input
Escape         | Close window       | Close window       | Close window
Cmd+W          | Close window       | Close window       | Close window
1              | Cycle microphone   | -                  | Type character
2              | Cycle input lang   | -                  | Type character
3              | Cycle output lang  | -                  | Type character
Option+C*      | -                  | Copy MD            | Copy MD
Option+V*      | -                  | Paste MD           | Paste MD
Option+Shift+C*| -                  | Copy plain         | Copy plain
Option+Shift+V*| -                  | Paste plain        | Paste plain
Enter          | -                  | Send from input    | Send
Shift+Enter    | -                  | -                  | New line
Cmd+C/V/A/X    | -                  | -                  | macOS system
Cmd+Z/Shift+Z  | -                  | -                  | Undo/Redo in input
```

*`Option+Space` - default hotkey (Option+Space, see research.md Decision 2). Same applies to Option+C/Option+V.

## LLM Context Limits by Model

| Model | Context limit (tokens) | 80% budget |
|--------|-------------------------|------------|
| gpt-4.1-nano | 1,048,576 | 838,860 |
| gpt-4o-mini | 128,000 | 102,400 |
| gpt-4.1-mini | 1,048,576 | 838,860 |
| gpt-5-nano | 1,048,576 | 838,860 |
| gpt-5-mini | 1,048,576 | 838,860 |
| gpt-5.1 | 1,048,576 | 838,860 |
| gpt-5.2 | 1,048,576 | 838,860 |
| gpt-5.3 | 1,048,576 | 838,860 |
