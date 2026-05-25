# Data Model: Recording Floating Window Redesign

**Feature Branch**: `005-recording-window-redesign`
**Date**: 2026-03-15

## Overview of changes

The redesign affects in-memory data models (there is no persistent storage for session data). Main changes: addition of a chat model, expansion of states, new UI components.

## Entities

### ChatMessage (NEW)

A message in the chat within a recording session.

| Field | Type | Description | Constraints |
|------|-----|----------|-------------|
| `id` | `UUID` | Unique identifier | Auto-generated |
| `role` | `ChatMessageRole` | Sender role | enum: `.system`, `.user`, `.assistant`, `.transcription` |
| `content` | `String` | Text content (Markdown) | Non-empty for sent messages |
| `timestamp` | `Date` | Creation time | Automatic |
| `isCollapsed` | `Bool` | Whether the message is collapsed | For system/transcription — `true` by default |
| `isEditing` | `Bool` | Editing mode | Only for the last assistant message |
| `isStreaming` | `Bool` | Whether streaming is in progress | For assistant messages |

```swift
enum ChatMessageRole: String, Codable {
    case system         // System prompt (collapsed bubble)
    case transcription  // Voice transcription (collapsed, non-editable)
    case user           // User message (from input)
    case assistant      // LLM response (with Markdown rendering)
}
```

### ChatSession (NEW)

Chat session tied to the floating window lifecycle.

| Field | Type | Description | Constraints |
|------|-----|----------|-------------|
| `messages` | `[ChatMessage]` | Message history | Ordered by timestamp |
| `systemPrompt` | `SystemPrompt` | Selected system prompt | Locked after processing |
| `voiceLanguage` | `SupportedLanguage` | Input language | Locked after processing |
| `textLanguage` | `SupportedLanguage` | Output language | Locked after processing |
| `audioDevice` | `String?` | Selected microphone | Locked after processing |
| `audioData` | `Data?` | Audio data of the last recording | For retry on error |

**Lifecycle**:
1. Created on window opening (`showOverlay`)
2. Settings are locked on transition to state 2 (after the first processing)
3. Destroyed on window closing (`dismissOverlay`)
4. NOT persisted between sessions

**Key methods**:
```swift
@Observable
class ChatSession {
    // Add a message
    func addMessage(_ message: ChatMessage)

    // Get the last LLM message
    var lastAssistantMessage: ChatMessage? { ... }

    // Prepare the array of messages for the LLM API with context truncation
    // Budget = 80% of model limit − system prompt tokens
    // Token estimate: content.count / 3 (≈3 characters = 1 token)
    func prepareMessagesForLLM(
        maxTokenBudget: Int,
        systemPromptTokens: Int
    ) -> [(role: String, content: String)]

    // Update content of the last assistant message (for streaming)
    func updateLastAssistantContent(_ content: String)

    // Reset the session
    func reset()
}
```

**Context truncation logic** (FR-044a):
- Budget = 80% of model context limit − system prompt tokens
- System prompt is always preserved
- Messages are added from the end (most recent) while `totalTokens < maxTokenBudget`
- On exceeding — oldest user/assistant pairs are removed
- Token estimate: `content.count / 3` (≈3 characters = 1 token, conservative for Cyrillic)

### TokenEstimator (NEW)

Utility for heuristic token counting.

```swift
struct TokenEstimator {
    /// Conservative estimate: 1 token ≈ 3 characters
    static func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 3)
    }

    /// Context limit for a model
    static func contextLimit(for model: LLMModel) -> Int

    /// Budget = 80% of limit - system prompt
    static func messageBudget(for model: LLMModel, systemPromptTokens: Int) -> Int
}
```

### WindowPhase (NEW)

Window phase — determines the set of control elements.

```swift
enum WindowPhase: Equatable {
    case preProcessing   // State 1: settings, recording, waiting
    case postProcessing  // State 2: chat, input, copy
}
```

### RecordingState (MODIFY)

Extension of the existing enum for two-stage processing.

```swift
enum RecordingState: Equatable {
    case idle                                                          // Waiting
    case recording(duration: TimeInterval, remaining: TimeInterval)    // Recording with countdown
    case transcribing                                                  // Stage 1: "Transcribing"
    case formatting                                                    // Stage 2: "Formatting" (streaming)
    case error(RecordingError)                                         // Error
}
```

**Changes relative to current**:
- `recording` — added `remaining` (countdown for the timer)
- `processing` → split into `transcribing` + `formatting`
- `result(text:)` — removed (the result is stored in `ChatSession.messages`)

### InputRecordingState (NEW)

State of voice input into the input field (state 2).

```swift
enum InputRecordingState: Equatable {
    case idle                                                          // Input is ready for text entry
    case recording(duration: TimeInterval, remaining: TimeInterval)    // Voice recording into the input
    case processing                                                    // Voice processing via LLM (default prompt)
}
```

### ControlButton (NEW)

Bottom control block button model.

```swift
struct ControlButton: Identifiable {
    let id: String
    let title: String
    let sfSymbol: String       // SF Symbol filled-variant name (e.g., "mic.fill", "doc.on.doc.fill")
    let hotkeyLabel: String    // Displayed badge (e.g., "⌥Space", "1")
    let isEnabled: Bool
    let action: () -> Void
    var hasDropdown: Bool      // For microphone, languages — opens a dropdown
}
```

## Changes in existing entities

### TranscriptionResult → simplification

The current `TranscriptionResult` is kept as an intermediate structure for passing data between services, but the UI works through `ChatMessage`:

| Field | Change | Reason |
|------|-----------|---------|
| `formattedText` | Remove | The result is stored in ChatMessage.content |
| `rawText` | Keep | Needed for building ChatMessage.transcription |
| `audioData` | Move to ChatSession | For retry |
| `voiceLanguage` | Remove | Stored in ChatSession |
| `textLanguage` | Remove | Stored in ChatSession |

### OverlayPanel → extension

| Property | Current | New |
|----------|---------|-------|
| `fixedSize` | `480×400` | `initialSize = 800×250` |
| Positioning | 5% from bottom | 5% from bottom (FR-002) |
| Rounding | 16px (SwiftUI) | 16px (FR-003), no shadow, no border/stroke |
| Height | Fixed | Dynamic (immediately 50% of screen on postProcessing) |
| `targetPID` | Static (on show) | Dynamic (TargetAppTracker) |
| `becomesKeyOnlyIfNeeded` | — | `false` (focus immediately on appearance) |

### OverlayManager → extension

New fields and methods:

| Field/Method | Type | Description |
|------------|-----|----------|
| `currentHeight` | `CGFloat` | Current window height |
| `maxHeight` | `CGFloat` | 50% of screen height (computed) |
| `updateHeight(_:)` | `(CGFloat) -> Void` | Upward expansion animation |
| `resetToInitialSize()` | `() -> Void` | Return to 800×250 |

## State transition diagram

```
                    ┌──────────────────────────────────────────────────────┐
                    │              WindowPhase.preProcessing               │
                    │                                                      │
   showOverlay() ──▶│  idle ──▶ recording ──▶ transcribing ──▶ formatting  │
                    │   ▲          │  ▲           │                │       │
                    │   │          │  │           │                │       │
                    │   │     Esc/⌘W │      error ◀──────── error │       │
                    │   │          │  │           │                │       │
                    │   └── silence/empty ────────┘                │       │
                    │              │                                │       │
                    │         min 2 sec                             │       │
                    └──────────────────────────────────────────────┼───────┘
                                                                   │
                                                             success│
                                                                   ▼
                    ┌──────────────────────────────────────────────────────┐
                    │              WindowPhase.postProcessing              │
                    │                                                      │
                    │  chat ◀──▶ inputRecording ──▶ inputProcessing        │
                    │   │                                                  │
                    │   ├── ⌥C / ⌥⇧C → copy → close window               │
                    │   ├── ⌥V / ⌥⇧V → paste → close window              │
                    │   ├── Enter → send → LLM streaming                  │
                    │   ├── ⌥Space → voice input into the input           │
                    │   └── Escape / ⌘W → close window                    │
                    └──────────────────────────────────────────────────────┘
```

## Entity relationships

```
RecordingViewModel (rework)
├── chatSession: ChatSession (NEW) — replaces result: TranscriptionResult?
├── windowPhase: WindowPhase (NEW)
├── recordingState: RecordingState (modify)
├── inputRecordingState: InputRecordingState (NEW)
├── inputText: String (NEW) — text in the input field
├── overlayManager: OverlayManager (modify)
├── targetAppTracker: TargetAppTracker (NEW)
├── streamingService: StreamingFormattingService (NEW)
├── settings: AppSettings (no changes)
└── promptsStore: PromptsStore (no changes)

OverlayPanel (modify)
├── initialSize: NSSize (800×250)
└── dynamic height via OverlayManager

ChatSession (NEW)
├── messages: [ChatMessage]
├── systemPrompt: SystemPrompt
├── voiceLanguage: SupportedLanguage
├── textLanguage: SupportedLanguage
└── audioData: Data?

TargetAppTracker (NEW)
├── targetPID: pid_t
└── observation: NSObjectProtocol?
```
