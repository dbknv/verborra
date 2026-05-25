# Specification: Conversation Recording Floating Window Redesign

**Feature Branch**: `005-recording-window-redesign`
**Created**: 2026-03-15
**Status**: Draft
**Input**: User description: "Conversation recording floating window redesign"

## User Scenarios and Testing *(mandatory)*

### Scenario 1 — Quick recording and getting the result (Priority: P1)

The user invokes the floating window via a system hotkey (`⌥Space`), starts voice recording, stops the recording, and receives processed text. They then copy or paste the result into the target application.

**Why this priority**: This is the main use case of the application — record voice, get processed text, use the result. Without this flow, all other features are meaningless.

**Independent test**: Can be fully tested by opening the window, recording voice, stopping the recording, waiting for processing, and pressing the "Copy" or "Paste" button. Delivers the core value — text from voice.

**Acceptance scenarios**:

1. **Given** the application is running and microphone access is granted, **When** the user presses `⌥Space`, **Then** a floating window of 800 × 250 px opens, horizontally centered with the bottom edge at 5% from the bottom of the visible work area
2. **Given** the floating window is open and auto-record is enabled, **When** the window appears, **Then** recording starts automatically with a visual indicator (equalizer) and countdown timer displayed
3. **Given** the floating window is open and auto-record is disabled, **When** the window appears, **Then** the content area displays the hint "To start recording, press Start or ⌥Space"
4. **Given** recording is active, **When** the user presses `⌥Space`, **Then** the recording stops and two-stage processing begins: "Transcribing" → "Formatting"
5. **Given** processing is complete, **Then** the result is displayed with Markdown rendering, the window expands upward (no more than half the screen), an input row appears, and "Copy" / "Paste" buttons appear in the bottom block
6. **Given** the result is displayed, **When** the user presses `⌥C`, **Then** the text of the last LLM message is copied with Markdown to the clipboard and the window closes
7. **Given** the result is displayed and Accessibility access is granted, **When** the user presses `⌥V`, **Then** the text is pasted into the previously active application (at the cursor position), copied to the clipboard, and the window closes

---

### Scenario 2 — Iterative refinement via chat (Priority: P2)

After receiving the initial result, the user refines the text via chat input: types text or speaks into the input, sends it, and the LLM returns a refined result.

**Why this priority**: Allows the user to iteratively improve the result without having to start recording again. Transforms the tool from a one-shot transcriber into an interactive workflow.

**Independent test**: After receiving a result, type a text query into the input, press Enter, and verify that the LLM returns a new message taking the context into account.

**Acceptance scenarios**:

1. **Given** processing is complete and the result is displayed, **Then** an input row appears above the bottom control block with 12 px padding at the bottom, left, and right
2. **Given** the input is active, **When** the user types text and presses `Enter`, **Then** the message is sent to the LLM with the full conversation history and the LLM returns a new message
3. **Given** the input is active, **When** the user presses `⌥Space`, **Then** voice recording starts inside the input with an equalizer and timer; after stopping and processing (with the default system prompt applied), the text is inserted into the input field
4. **Given** the input already contains text, **When** the user records a new voice fragment, **Then** the recognized text is appended to the existing text
5. **Given** a request is being processed, **Then** the "Send" button is inactive until the result is received
6. **Given** the input has focus, **Then** simple hotkeys (`1`, `2`, `3`) are inactive, standard macOS commands (`⌘C`, `⌘V`, `⌘A`, `⌘Z`, `⌘⇧Z`, `⌘X`) work normally, and hotkeys with modifiers (`⌥Space`, `⌥C`, `⌥V`, `Escape`) continue to work
7. **Given** a chat result has been received, **When** the user presses `⌥C`/`⌥V`, **Then** the text of the **last** LLM message is copied/pasted

---

### Scenario 3 — Configuring recording parameters (Priority: P2)

Before starting recording, the user selects the audio source, input language, output language, and system prompt.

**Why this priority**: Multilingual support and prompt selection are critical for the target audience. Without language selection, the user cannot control transcription quality and output format.

**Independent test**: Open the window, change the input/output language, record voice, and verify that the result matches the selected languages.

**Acceptance scenarios**:

1. **Given** the floating window is open (state 1), **Then** the bottom control block displays three buttons on the left: microphone (hotkey `1`), input language (hotkey `2`), output language (hotkey `3`)
2. **Given** state 1, **When** the user presses `2`, **Then** the input language cycles (without opening a dropdown); when the last element is reached — wraps to the first
3. **Given** the user has changed the output language, **When** the recording is processed, **Then** the result is returned in the selected output language, regardless of language instructions in the system prompt
4. **Given** processing is complete (state 2), **Then** the language/microphone selection buttons are hidden, hotkeys `1`, `2`, `3` are inactive, and settings are locked for the entire session
5. **Given** the user changed settings during a session and closed the window, **When** they open the window again, **Then** default values from the application settings are loaded

---

### Scenario 4 — Selecting and switching the system prompt (Priority: P3)

The user selects a system prompt from a list of ready prompts in the content area. They can change the prompt before and during recording.

**Why this priority**: Expands tool flexibility. The default prompt covers the main scenario; custom prompts are additional value.

**Independent test**: Open the window, click the prompt name, select a different one from the dropdown, record voice, and verify that the result was processed with the selected prompt.

**Acceptance scenarios**:

1. **Given** the window is open, **Then** the name of the current system prompt is displayed in the center of the content area (truncated with `…` on overflow)
2. **Given** the window is open, **When** the user clicks the prompt name, **Then** a dropdown opens with a list of available prompts
3. **Given** recording is active, **When** the user changes the prompt via click, **Then** the new prompt is applied during processing after the recording stops
4. **Given** the default system prompt, **Then** it cannot be modified or deleted
5. **Given** a result has been received, **Then** the chat first displays a collapsed system prompt bubble with an "Expand" icon, which shows the full text on click

---

### Scenario 5 — Manual editing of the result (Priority: P3)

The user manually edits the last LLM message and can continue working with the edited text.

**Why this priority**: Provides control over the final text without needing another LLM call.

**Independent test**: Get a result, click the "Edit" icon on the last LLM message, make edits, confirm, and copy.

**Acceptance scenarios**:

1. **Given** the result is displayed, **Then** the "Edit" icon is visible only on the last LLM message, and the "Copy" icon is on all messages
2. **Given** the "Edit" icon is pressed, **Then** the text becomes editable
3. **Given** edit mode is active, **When** the user presses the "Edit" icon again, **Then** the changes are applied
4. **Given** edit mode is active, **When** the user presses the "Cross" icon, **Then** the changes are discarded
5. **Given** the user edited a message and sends a new request, **Then** the edits are taken into account in the conversation context for the LLM

---

### Scenario 6 — Copying and pasting with/without Markdown (Priority: P3)

The user copies or pastes text in two modes: with Markdown formatting and without (plain text).

**Why this priority**: Different target applications require different text formats (Markdown editors vs. plain text fields).

**Independent test**: Get a result with Markdown formatting, press `⌥C` (with Markdown), paste into a Markdown editor — formatting is preserved. Press `⌥⇧C` (without Markdown), paste into a plain field — plain text.

**Acceptance scenarios**:

1. **Given** the result is displayed, **When** `⌥C` is pressed, **Then** the text of the last LLM message with Markdown is copied and the window closes
2. **Given** the result is displayed, **When** `⌥⇧C` is pressed, **Then** the text without Markdown is copied and the window closes
3. **Given** the result is displayed and Accessibility access is granted, **When** `⌥V` is pressed, **Then** the text with Markdown is pasted into the previously active application and the window closes
4. **Given** the result is displayed and Accessibility access is granted, **When** `⌥⇧V` is pressed, **Then** plain text is pasted into the previously active application and the window closes
5. **Given** there is no Accessibility access, **Then** the "Paste" buttons are inactive with a `?` icon and explanation

---

### Scenario 7 — Handling error states (Priority: P4)

The application correctly handles missing microphone access and missing API key.

**Why this priority**: Provides user-friendly onboarding and eliminates "dead" interface states.

**Independent test**: Revoke microphone access, open the window — the message with a button to navigate to settings is visible.

**Acceptance scenarios**:

1. **Given** there is no microphone access, **When** the user opens the floating window, **Then** the content area displays the message "Microphone access is required for the application to work" and a button to navigate to settings
2. **Given** the microphone error is displayed, **When** the user presses the button, **Then** the application settings open on the permissions tab and the floating window closes
3. **Given** the API key is not provided, **When** the user opens the floating window, **Then** the content area displays the message "An API key is required for the application to work" and a button to navigate to settings
4. **Given** the API key error is displayed, **When** the user presses the button, **Then** the settings open on the API key input tab and the window closes

---

### Edge cases

- What happens when the recording reaches maximum duration (timer = 0)? Recording automatically stops and processing begins
- What happens when `Escape` / `⌘W` is pressed during active recording? Recording stops immediately, the window closes without processing, without a confirmation dialog
- What happens when `Escape` / `⌘W` is pressed during processing (transcribing/formatting)? Processing is interrupted, the window closes
- What happens on API call failure (network error, timeout, LLM error)? An error message is displayed in the content area with a "Retry" button; the audio recording is preserved until successful processing
- What happens with an empty transcription result (silence, unintelligible speech)? The window stays in state 1, an error "Failed to recognize text or get transcription. Please retry." is displayed with an active "Start" button and hotkey
- What happens when the result text exceeds half the screen height? A scroll appears
- What happens when trying to assign a hotkey without a modifier? Warning, the hotkey is not saved
- What happens when trying to assign `⌘C` as a custom hotkey? Warning about conflict with a system command, the hotkey is not saved
- What happens when the user presses `⌥Space` with the window open but recording not started? Recording starts
- What happens when trying to send a message from the input while a previous request is still being processed? The "Send" button is inactive, `Enter` is ignored
- What happens with voice input in the input when text is already present? The new text is appended to the existing text
- What happens when pressing `⌥Space` in state 2? Voice input into the input is started (not a new recording session); the text is added to the existing input but is NOT sent automatically
- What happens when the input exceeds 5 lines? A vertical scroll appears
- What happens on a click outside the floating window? The window remains visible (always-on-top), recording continues, clicking the window returns focus
- What happens when the microphone is disconnected/unavailable during active recording? Recording stops immediately, audio is discarded, the content area displays an error message indicating the microphone problem with a button to navigate to settings
- What happens when trying to stop recording before 2 seconds? The "Stop" button (`⌥Space`) is blocked, the hotkey is ignored; after 2 seconds, recording can be stopped normally

## Requirements *(mandatory)*

### Functional requirements

#### Window and positioning

- **FR-001**: The system MUST display a floating window with default size 800 × 250 px
- **FR-002**: The system MUST position the window horizontally centered, with the bottom edge at 5% from the bottom of the visible work area (accounting for the Dock). With multiple monitors, the window MUST appear on the screen containing the active window or mouse cursor. The user MAY drag the window to another position; on reopen, the window MUST return to the default position
- **FR-002a**: The floating window MUST be displayed in always-on-top mode — always above all applications on the regular desktop, never going to the background. The window MUST NOT appear over full-screen applications (fullscreen spaces) — it opens on the regular desktop
- **FR-003**: The system MUST apply 16 px corner rounding, with no border and no shadow around the window. Color palette:
  - Window background: `#E9E9E9`
  - Bottom control block background: `#F4F4F4`
  - Button background in bottom block: `#DCDCDC`
  - Button text: `#2C2C2C`
  - Shortcut badge background in buttons: `#F4F4F4`
  - Icons in bottom block: `#B6B6B6`
  - Timer text: `#9A9A9A` (gray), `#D94040` when < 30 sec
  - Text bubble background: `#F4F4F4`
  - Bubble text: `#2F2F2F`
  - Equalizer: `#9A9A9A`
  - Button hover: `#D0D0D0`
  - Button disabled: background `#EBEBEB`, text `#ACACAC` (opacity ~50%)
  - Timer < 30 sec: `#D94040` (red)
- **FR-004**: The system MUST provide smooth animation for all window size changes (expansion upward, input appearance)

#### Hotkeys and control

- **FR-005**: The system MUST open the floating window on `⌥Space` press (global hotkey, configurable via Overlay settings). The window MUST receive focus and become active immediately upon appearance (`becomesKeyOnlyIfNeeded = false`). Pressing `⌥Space` again with the window open does NOT close the window, but controls recording (start/stop in state 1, voice input in state 2)
- **FR-005a**: Microphone, input language, and output language settings in the floating window MUST be session-scoped — changes apply only to the current session. On a new window opening, the values from global application settings MUST be applied
- **FR-006**: In state 1, the system MUST start/stop recording on repeated `⌥Space` press. In state 2, pressing `⌥Space` MUST start voice input into the input field — the recognized text is added to the existing text in the input but is NOT sent automatically (the user sends explicitly via `Enter` or the "Send" button)
- **FR-007**: The system MUST close the window on `Escape`, `⌘W`, or the "Exit" button without a confirmation dialog, immediately stopping recording
- **FR-008**: Hotkeys `1`, `2`, `3` MUST be active only in state 1 (before processing): `1` cycles microphones, `2` cycles input language, `3` cycles output language. When the last element of the list is reached, switching restarts from the first
- **FR-009**: Hotkeys `⌥C`, `⌥V`, `⌥⇧C`, `⌥⇧V`, `Enter` MUST be active only in state 2 (after processing)
- **FR-010**: Hotkeys `⌥Space`, `Escape`, `⌘W` MUST work in both states
- **FR-011**: All floating window hotkeys MUST work regardless of focus (input, button, any component) — via application-level interception (`NSEvent.addLocalMonitorForEvents`). When the input has focus, simple hotkeys (`1`, `2`, `3`) MUST be disabled, standard macOS commands (`⌘C`, `⌘V`, `⌘A`, `⌘X`, `⌘Z`, `⌘⇧Z`) MUST work normally, and application hotkeys with the `⌥` modifier (`⌥C`, `⌥V`, `⌥⇧C`, `⌥⇧V`, `⌥Space`) MUST be intercepted by the application (macOS symbols `ç`, `√`, etc. are unavailable)

#### Bottom control block

- **FR-016**: The bottom block MUST occupy the bottom, left, and right edges of the window (without margins), with `#F4F4F4` background, ~16 px bottom corner rounding, and straight top corners. All elements (microphone, language selectors, action buttons) MUST be visually identical buttons with a unified style
- **FR-017**: Each block element MUST be designed as a button with action text and a hotkey badge (`#DCDCDC` background); clicking performs the same action as the hotkey
- **FR-018**: For displaying modifiers in hotkey badges, the symbols MUST be used: `⌘`, `⌥`, `⌃`, `⇧`
- **FR-019**: In state 1, the left side MUST contain the buttons: microphone (hotkey `1`), input language (hotkey `2`), output language (hotkey `3`); the right side — "Start"/"Stop" (`⌥Space`) and "Exit" (`Escape`)
- **FR-020**: In state 2, the left side MUST contain the buttons: "Copy" (`⌥C`) and "Paste" (`⌥V`); the right side — "Start"/"Stop" (`⌥Space`) and "Exit" (`Escape`). The "Start/Stop" button in state 2 MUST initiate voice input into the input (behavior identical to `⌥Space` in state 2)

#### Recording settings (source, languages)

- **FR-021**: Microphone, input language, and output language buttons MUST open a dropdown with selection
- **FR-022**: On window opening, settings MUST be loaded from default values in application settings
- **FR-023**: After recording processing (transition to state 2), settings MUST be locked for the entire session without the possibility of change
- **FR-024**: After the window is closed, changed settings MUST NOT be saved
- **FR-025**: The output language selected in the floating window MUST have the highest priority and override language instructions in the system prompt

#### System prompt

- **FR-026**: The system prompt name MUST be displayed in the center of the content area, truncated with `…` on overflow
- **FR-027**: Clicking the name MUST open a dropdown with selection of another prompt
- **FR-028**: Changing the prompt MUST be available both before and during recording
- **FR-029**: The default system prompt (text correction) MUST NOT be available for modification or deletion
- **FR-030**: For voice input into the input, transcription MUST be processed through the LLM with the default system prompt (correction of recognition errors, punctuation, capitalization) before insertion into the input field, regardless of the selected main prompt

#### Recording and indication

- **FR-031**: During active recording, a visual indicator (equalizer, color `#9A9A9A`) MUST be displayed across the full width of the content area
- **FR-032**: The countdown timer MUST show remaining time in `MM:SS` format, color `#9A9A9A` (gray), changing to `#D94040` (red) when remaining < 30 seconds
- **FR-033**: When the timer reaches 0, recording MUST automatically stop
- **FR-033a**: Minimum recording duration for processing — 2 seconds. The "Stop" button (`⌥Space`) and stop hotkey MUST be blocked until the threshold is reached. After 2 seconds, the button is unblocked and stopping with subsequent processing is available. This restriction applies to both recording types: main recording (state 1) and voice input into the input (state 2)
- **FR-034**: If auto-record is enabled, recording MUST start automatically when the window opens. Default value — enabled
- **FR-034a**: When the microphone is disconnected or unavailable during active recording, the system MUST immediately stop recording, discard audio, and display an error message in the content area with a button to navigate to settings

#### Processing and result display

- **FR-035**: After recording stops, the system MUST display two sequential processing stages: "Transcribing" → "Formatting". The LLM response in the formatting stage MUST be displayed via streaming — token by token in real time. Similarly for chat message responses. During processing, the bottom block MUST display state 1 buttons (microphone, languages, Start/Stop, Exit), all disabled except "Exit" (`Escape`)
- **FR-035a**: On API call failure (network error, timeout, LLM error), the system MUST display an error message in the content area with a "Retry" button; the audio recording MUST be preserved until successful processing
- **FR-035b**: On empty transcription result (silence, unintelligible speech), the system MUST remain in state 1, display the message "Failed to recognize text or get transcription. Please retry." with an active "Start" button and hotkey for re-recording
- **FR-036**: On transition to state 2 (postProcessing), the window MUST immediately expand upward up to 50% of screen height (the bottom edge remains in place). When content exceeds available height — scroll
- **FR-036a**: Text bubbles MUST NOT contain internal scroll — the bubble height adapts to the content. System messages MUST occupy the full width. Transcription and user bubbles MUST occupy 70% of width with right alignment. Assistant bubbles MUST occupy 70% of width with left alignment. Background of all bubbles: `#F4F4F4`
- **FR-037**: All text bubbles (prompt, transcription, LLM responses, user messages) MUST support Markdown rendering
- **FR-038**: Logical chat structure (top to bottom): system prompt bubble → transcription bubble → LLM response → iterative messages
- **FR-039**: The system prompt bubble MUST be collapsed to one line with an "Expand"/"Collapse" icon
- **FR-040**: The transcription bubble MUST be collapsed to one line with an "Expand"/"Collapse" icon, without editing capability

#### Editing the result

- **FR-041**: The "Edit" icon MUST be available only for the last LLM message
- **FR-042**: The "Copy" icon MUST be available for all messages, copying the block text without closing the window
- **FR-043**: In editing mode, pressing the "Edit" icon again MUST confirm changes; pressing "Cross" — discards them
- **FR-044**: Edited text MUST be considered in the conversation context for subsequent requests to the LLM
- **FR-044a**: When approaching the LLM provider's context limit, the system MUST truncate old messages by token-oriented principle: preserve the system prompt and as many recent messages as fit within 80% of the provider's context limit (minus the system prompt). The user MUST NOT receive a context-limit-exceeded error

#### Input row

- **FR-045**: The input MUST appear after recording is processed, above the bottom block, with 12 px padding (bottom, left, right)
- **FR-046**: The input field MUST start at 1-line height, expanding to 5 lines, then — vertical scroll
- **FR-047**: `Enter` MUST send the message (without modifiers), `Shift+Enter` MUST insert a line break. Focus stays on the input
- **FR-048**: For voice input in the input, the equalizer and timer MUST be displayed inside the input field. Maximum recording duration — the same setting from application settings as for the main recording
- **FR-049**: During voice recording, the "Microphone" and "Send" icons MUST be replaced by a "Stop" button
- **FR-050**: System "Copy" and "Paste" buttons MUST be inactive during recording/processing in the input

#### System copy/paste buttons

- **FR-051**: "Copy" and "Paste" buttons MUST operate on the last received LLM message
- **FR-052**: After pressing any system copy/paste button, the window MUST close
- **FR-053**: `⌥C`/`⌥V` — copy/paste source Markdown text (e.g., `**bold**`, `- list`); `⌥⇧C`/`⌥⇧V` — plain text without Markdown formatting characters
- **FR-054**: The "Paste" button MUST additionally copy the text to the clipboard (in case the paste fails)
- **FR-055**: "Paste" buttons MUST require Accessibility access; if absent — inactive with a `?` icon and explanation

#### Tracking the target application for paste

- **FR-060**: When the floating window opens, the system MUST capture the application that was active immediately before the window appeared as the initial target application for paste
- **FR-061**: The system MUST dynamically track the change of the active background application (excluding the floating window itself) and update the target application for paste. If the active application changes in the background while the window is open — the most recent active one becomes the target
- **FR-062**: When "Paste" is pressed (`⌥V`/`⌥⇧V`), the text MUST be pasted into the last tracked active application

#### Accessibility

- **FR-056**: On window launch, the system MUST check for Accessibility access
- **FR-057**: If there is no Accessibility access — the "Copy" button works, the "Paste" button is inactive with a `?` icon and a redirect to application settings

#### Icons

- **FR-058**: SF Symbols icons MUST be used throughout the application. All icons MUST use filled variants (e.g., `mic.fill`, `doc.on.doc.fill`, `xmark.circle.fill`, `checkmark.circle.fill`, `pencil.circle.fill`, `waveform.circle.fill`, `text.bubble.fill`, `doc.on.clipboard.fill`, `arrow.clockwise.circle.fill`, `questionmark.circle.fill`, `chevron.down.circle.fill`/`chevron.up.circle.fill`, `gearshape.fill`, `sparkles.rectangle.stack.fill`, `rectangle.portrait.and.arrow.right.fill`)

#### Hint when auto-record is disabled

- **FR-059**: If auto-record is disabled, the content area MUST display a hint with text and the current hotkey (text color `#8C8C8C`, standard system font); the hint disappears after recording begins

### Key entities

- **Floating Window**: The main UI container of the application for recording. Has two states (before processing, after processing), contains the content area and the bottom control block
- **Session**: The lifecycle from opening to closing the floating window. Stores temporary settings (audio source, languages, prompt) and chat message history. Number of messages is unlimited. When the window closes, the entire history is deleted and not preserved between sessions
- **System Prompt**: A preset instruction for the LLM. Comes in two types: main (selected by the user for recording processing) and default (applied to voice input into the input)
- **Chat Message**: An element of the conversation in the content area. Types: system prompt (collapsed), transcription (collapsed, non-editable), LLM response (with Markdown), user message
- **Hotkey**: A keyboard combination. Comes in two kinds: system (non-reassignable: `Escape`, `⌘W`, `1`, `2`, `3`) and user (reassignable with validation)

## Success criteria *(mandatory)*

### Measurable outcomes

- **SC-001**: The user can complete the full cycle (open window → record voice → get result → copy/paste) in less than 60 seconds (not counting recording time)
- **SC-002**: All transitions between window states (expansion, input appearance, button changes) happen smoothly, without visual jumps
- **SC-003**: The user can perform 3 or more iterations of text refinement via chat without restarting the session
- **SC-004**: The selected output language is guaranteed to be applied to the result in 100% of cases, regardless of prompt instructions
- **SC-005**: All hotkeys with modifiers work correctly when focus is on the input, with no conflicts with system macOS commands
- **SC-006**: When Accessibility access, microphone, or API key is missing, the user receives a clear message with the ability to navigate to settings

## Clarifications

### Session 2026-03-15 (clarify)

- Q: What happens when the microphone is disconnected/unavailable during active recording? → A: Recording stops immediately, audio is discarded, an error with a button to navigate to settings is displayed
- Q: Is a minimum recording duration threshold required before sending for processing? → A: Minimum 2 seconds — the "Stop" button (`⌥Space`) is blocked until the threshold is reached; after unblocking, stopping and processing is available

### Session 2026-03-15 (hotkey update)

- Q: When focus is on the input, `⌥C`/`⌥V` conflict with input of macOS symbols (`ç`, `√`) — which takes precedence? → A: Application hotkeys are always intercepted (`⌥C` = copy, `⌥V` = paste); macOS symbols are unavailable when the input has focus

### Session 2026-03-15

- Q: What happens when Start/⌥Space is pressed in state 2 (after the result is received)? → A: Voice input into the input field is started — text is added to the existing one but is not sent automatically. The user sends via Enter or the button
- Q: How does the user insert a line break in the input? → A: Shift+Enter inserts a line break (standard chat application behavior)
- Q: Can the user drag the floating window? → A: Yes, dragging is available; on reopening, the window returns to the default position
- Q: Is macOS dark theme support needed? → A: No, only the light theme with the specified color palette is used
- Q: Is the Start/Stop button in state 2 an analog of ⌥Space (voice input into the input)? → A: Yes, behavior is identical: in state 1 — initial recording, in state 2 — recording for insertion into the input
- Q: What happens on API call failure (network error, timeout, LLM provider error) during processing? → A: An error message is displayed in the content area with a "Retry" button; the recording is preserved until successful processing
- Q: On which screen is the floating window displayed with multiple monitors? → A: On the screen with the active window or mouse cursor
- Q: Is there a limit on the number of messages in a chat session? → A: No limits within a single session; on overflow of the content area — scroll. Message history is deleted when the window closes and is not preserved between sessions
- Q: What happens with an empty transcription result (silence, unintelligible speech)? → A: The window stays in state 1, an error "Failed to recognize text or get transcription. Please retry." is displayed with an active "Start" button and hotkey for re-recording
- Q: Does the floating window stay on top of all windows (always-on-top)? → A: Yes, always-on-top — the window is always above all applications, never going to the background
- Q: What does "copy with Markdown" mean — source Markdown text or rich text? → A: Source Markdown text (`**bold**`, `- list`) — pasted as plain text with formatting characters
- Q: Does the LLM response appear in full or via streaming? → A: Streaming — the text appears token by token in real time
- Q: How does the window behave with an active full-screen application (fullscreen space)? → A: The window opens on the regular desktop (not over fullscreen). After copying/pasting, the user returns to the full-screen application on their own
- Q: What strategy should be used to send chat history to the LLM during iterative refinement? → A: Truncate old messages — when approaching the context limit, remove old messages while preserving the system prompt and as many recent messages as fit within 80% of the provider's context limit
- Q: How to determine the chat context truncation threshold? → A: Token-oriented approach — keep as many recent messages as fit within 80% of the provider's context limit (minus the system prompt)
- Q: How to handle voice input in the input — raw transcription or LLM processing? → A: Processing through the LLM with the default system prompt (error correction, punctuation, capitalization) before insertion into the input
- Q: What is the default value for the "auto-record on window opening" setting? → A: Enabled by default — recording starts immediately when the window opens
- Q: At what moment is the "previously active application" captured for paste? → A: Captured when the window opens + dynamic tracking: if the active application changes in the background, the most recent active one becomes the target (excluding the floating window itself)
- Q: What happens on a click outside the floating window? → A: The window remains visible (always-on-top), recording continues, clicking the window returns focus
- Q: What features are explicitly excluded from scope? → A: Preserving history between sessions, export/import, drag & drop audio, rich text (HTML) copying, voice commands for window control
- Q: Which buttons are displayed in the bottom block during processing (between stopping the recording and the result appearing)? → A: State 1 buttons (microphone, languages, Start/Stop, Exit), all disabled except "Exit" (Escape)
- Q: How to define dark theme colors? → A: Not applicable — only the light theme is used
- Q: Are the defined colors sufficient? → A: A full palette is specified: window background `#E9E9E9`, bottom block background `#F4F4F4`, button background `#DCDCDC`, button text `#2C2C2C`, shortcut badge background `#F4F4F4`, icons `#B6B6B6`, timer `#8C8C8C`, bubble background `#F4F4F4`, bubble text `#2F2F2F`. Derived states (hover, disabled) are defined at the implementation stage
- Q: What is the default value for maximum recording duration? → A: See the "Assumptions" section
- Q: What is the maximum recording duration for voice input in the input (state 2)? → A: The same setting from application settings — unified for main recording and voice input into the input

## Out of scope

- Preserving chat history between sessions (history is deleted when the window closes)
- Export/import of text or audio to files
- Drag & drop of audio files into the floating window
- Rich text (HTML) copying — only source Markdown and plain text
- Voice commands for window control
- Dark theme support

## Assumptions

- Maximum recording duration — 20 minutes by default (configurable in application settings: 1, 5, 10, 20, 60 minutes). The value is loaded when the floating window opens
- Window position takes into account the visible work area (excluding the Dock) via standard macOS APIs (`NSScreen.visibleFrame`)
- The list of available input/output languages is determined by the existing application configuration
- The list of available system prompts is managed via application settings (existing functionality)
- Insertion of text into the previously active application happens via the macOS Accessibility API (emulation of `⌘V`)
- Default system prompt: "Fix speech recognition errors, add punctuation and capitalization. Break into paragraphs by meaning. Return only the corrected text. Never ask the user anything additional if you have questions or need clarification. Always strictly return only the final corrected text."

## Constraints

- Max height of expanded window — no more than half the screen
- Max input height — 5 lines (then scroll)
