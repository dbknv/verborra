# Tasks: Recording Floating Window Redesign

**Input**: Design artifacts from `specs/005-recording-window-redesign/`
**Prerequisites**: plan.md, spec.md, data-model.md, research.md, quickstart.md

**Tests**: Included for critical components (Constitution Principle 5: business logic MUST be covered by unit tests).

**Organization**: Tasks are grouped by user scenarios for independent implementation and testing of each scenario.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can be done in parallel (different files, no dependencies)
- **[Story]**: Which user scenario the task belongs to (US1, US2, ..., US7)
- All file paths relative to project root

---

## Phase 1: Setup (Shared infrastructure)

**Goal**: Create new data models and services required by all scenarios

- [X] T001 [P] Create ChatMessage model (roles, content, isCollapsed, isEditing, isStreaming) in Verborra/Models/ChatMessage.swift
- [X] T002 [P] Create TokenEstimator (heuristic ~3 chars/token, model limits, 80% budget) in Verborra/Models/TokenEstimator.swift
- [X] T003 [P] Create enum WindowPhase (.preProcessing, .postProcessing) in Verborra/Models/WindowPhase.swift
- [X] T004 [P] Create enum InputRecordingState (.idle, .recording, .processing) in Verborra/Models/InputRecordingState.swift
- [X] T005 Create @Observable class ChatSession implementing ChatSessionProtocol (contracts/internal-api.md) (messages, systemPrompt, languages, audioData, addMessage/lastAssistantMessage/prepareMessagesForLLM/updateLastAssistantContent/reset methods with context truncation via TokenEstimator, estimate: content.count / 3) in Verborra/Models/ChatSession.swift
- [X] T006 Modify RecordingState: replace .processing with .transcribing + .formatting, add remaining in .recording, remove .result(text:) in Verborra/Models/RecordingState.swift. Also simplify TranscriptionResult: remove formattedText, voiceLanguage, textLanguage (moved to ChatSession) in Verborra/Models/TranscriptionResult.swift. **WARNING: Find and update all references to removed fields in existing code (RecordingViewModel, FormattingService, etc.)**
- [X] T007 [P] Create StreamingFormattingServiceProtocol and StreamingFormattingService (URLSession.bytes SSE streaming, parsing data:/[DONE], AsyncThrowingStream<String, Error>, timeout 60s, retry before stream starts; protocol for mocking in tests — Constitution Principle 5) in Verborra/Services/StreamingFormattingService.swift
- [X] T008 [P] Create TargetAppTracker (NSWorkspace.didActivateApplicationNotification, excluding own bundleIdentifier, start/stopTracking, targetPID) in Verborra/Services/TargetAppTracker.swift
- [X] T009 [P] Create MarkdownStripper (swift-markdown MarkupWalker for extracting plain text from Markdown) in Verborra/Services/MarkdownStripper.swift
- [X] T008a [P] Unit test TargetAppTracker: subscription to NSWorkspace.didActivateApplicationNotification, exclusion of own bundleIdentifier, updating targetPID on active app change, start/stopTracking in VerborraTests/Services/TargetAppTrackerTests.swift
- [X] T009a [P] Unit test MarkdownStripper: headings, bold/italic, lists, links, code blocks, nested Markdown → clean plain text in VerborraTests/Services/MarkdownStripperTests.swift

---

## Phase 2: Foundational (Blocking prerequisites)

**Goal**: Rework OverlayPanel and OverlayManager — the base window infrastructure that all scenarios depend on

**WARNING — CRITICAL**: Work on scenarios cannot begin until this phase is complete

- [X] T010 Rework OverlayPanel: size 800×250, positioning at 5% from bottom of visibleFrame, 16px rounding, no border, no shadow, no stroke/border, background #E9E9E9, .fullScreenAuxiliary (not over fullscreen), becomesKeyOnlyIfNeeded = false (focus immediately on appearance) in Verborra/Views/OverlayPanel.swift
- [X] T011 Extend OverlayManager: dynamic height (updateHeight via NSAnimationContext, max 50% screen, debounce 50ms), resetToInitialSize, integration with TargetAppTracker in Verborra/Views/OverlayPanel.swift
- [X] T012 Rework OverlayContentView: new structure — content area + slot for InputFieldView (conditionally visible only in postProcessing with withAnimation for smooth appearance/disappearance — FR-004, the InputFieldView itself is created in T028) + ControlBarView (configuration change with transition — FR-004), 16px rounding, background #E9E9E9, onGeometryChange → OverlayManager.updateHeight, hotkeys via NSEvent.addLocalMonitorForEvents (work regardless of focus) in Verborra/Views/OverlayContentView.swift
- [X] T013 Create ControlButton model (id, title, sfSymbol, hotkeyLabel, isEnabled, action, hasDropdown) and ControlBarView: three configurations (preProcessing / processing / postProcessing), background #F4F4F4, bottom corner rounding 16px, buttons with hotkey badges (background #DCDCDC, text #2C2C2C, badge #F4F4F4), hover #D0D0D0, disabled #EBEBEB/#ACACAC, SF Symbols (filled variants). All selector buttons (microphone, languages) MUST use the same visual style (shared ControlBarButtonLabel) as the action buttons (Start/Stop, Exit, Copy, Paste). **Configuration processing** (FR-035): state 1 buttons (microphone, languages, Start/Stop, Exit), all disabled except "Exit" (Escape) — used between stopping recording and the result appearing in Verborra/Views/ControlBarView.swift
- [X] T014 Modify PasteService: add copyMarkdown/copyPlainText/pasteMarkdown/pastePlainText methods, integration with MarkdownStripper, close-on-action. paste* methods MUST pre-copy text to clipboard as fallback (FR-054). Use targetPID from TargetAppTracker for pasting into the target application (FR-060—FR-062) in Verborra/Services/PasteService.swift
- [X] T014a [P] Unit test PasteService: copyMarkdown/copyPlainText correctly place text in clipboard, pasteMarkdown/pastePlainText copy text before pasting (FR-054), integration with MarkdownStripper in VerborraTests/Services/PasteServiceTests.swift

**Checkpoint**: Window opens with new size and style, ControlBar is displayed, dynamic height works

---

## Phase 3: Scenario 1 — Quick recording and getting the result (P1) MVP

**Goal**: Full cycle: open window → record voice → get streaming result → copy/paste

**Independent test**: Open window via hotkey, record voice, stop, wait for streaming result, press ⌥C — text is in clipboard

### Tests for Scenario 1

- [X] T015 [P] [US1] Unit test ChatSession: addMessage, lastAssistantMessage, updateLastAssistantContent, prepareMessagesForLLM with context truncation (including integration test: create session with 20+ messages, call prepareMessagesForLLM, verify that the system prompt is preserved, old messages are removed, total tokens ≤ 80% of the limit) in VerborraTests/Models/ChatSessionTests.swift
- [X] T016 [P] [US1] Unit test TokenEstimator: estimateTokens, contextLimit, messageBudget in VerborraTests/Models/TokenEstimatorTests.swift
- [X] T017 [P] [US1] Unit test StreamingFormattingService: parsing SSE data:, handling [DONE], HTTP errors in VerborraTests/Services/StreamingFormattingServiceTests.swift

### Implementation of Scenario 1

- [X] T018 [US1] Create MarkdownTextView — NSViewRepresentable wrapper for read-only Markdown rendering with swift-markdown, background #F4F4F4, text #2F2F2F in Verborra/Views/Components/MarkdownTextView.swift
- [X] T019 [US1] Create ChatBubbleView — message bubble: system (collapsed, chevron.down.circle.fill/chevron.up.circle.fill, full width), transcription (collapsed, non-editable, 70% width, right), user (70% width, right), assistant (70% width, left); background #F4F4F4, no internal scroll — height adapts to content. **Scope**: read-only display and collapse/expand only; doc.on.doc.fill (copy) and pencil.circle.fill (edit) icons are implemented in T041 and T038 respectively in Verborra/Views/ChatBubbleView.swift
- [X] T020 [US1] Create ChatView — ScrollView + LazyVStack + ScrollViewReader with autoscroll to the last message, logic: system prompt bubble → transcription bubble → LLM response → iterative messages in Verborra/Views/ChatView.swift
- [X] T021 [US1] Rework RecordingView: states idle (hint FR-059), recording (equalizer #9A9A9A full width + countdown timer format MM:SS, color #9A9A9A gray / #D94040 red when <30s), transcribing ("Transcribing"), formatting ("Formatting"), error (with "Retry" button and navigation to settings) in Verborra/Views/RecordingView.swift
- [X] T022 [US1] Modify AudioWaveformView: color #9A9A9A, full content area width, 12px bar rounding in Verborra/Views/Components/AudioWaveformView.swift
- [X] T023 [US1] Rework RecordingViewModel — Phase preProcessing: showOverlay (create ChatSession, load defaults from settings, check Accessibility access to determine "Paste" button availability — FR-056/FR-057), startRecording (API key check, min 2 sec), stopRecording (transcribing → formatting with streaming via StreamingFormattingService), transition to postProcessing on success, error handling (FR-034a, FR-035a, FR-035b), auto-record (FR-034), saving audioData for retry in Verborra/ViewModels/RecordingViewModel.swift
- [X] T024 [US1] Implement state 1 hotkey logic in RecordingViewModel: ⌥Space (start/stop recording), Escape/⌘W (dismissOverlay), handle min. 2 sec (block stop), automatic recording stop when timer reaches 0 (FR-033), transitions between idle↔recording↔transcribing↔formatting in Verborra/ViewModels/RecordingViewModel.swift
- [X] T025 [US1] VERIFIED Implement state 2 hotkey logic in RecordingViewModel: ⌥C (copyMarkdown + dismiss), ⌥V (pasteMarkdown + dismiss), button blocking during processing, handleKeyDown intercepts ⌥-combinations via NSEvent.addLocalMonitorForEvents (works regardless of focus). **Scope**: Markdown copy/paste mode only; plain text (⌥⇧C/⌥⇧V) and Accessibility check are implemented in T040 in Verborra/ViewModels/RecordingViewModel.swift
- [X] T026 [US1] Update VerborraApp: initialize StreamingFormattingService, TargetAppTracker, pass to RecordingViewModel, update AppController in Verborra/VerborraApp.swift
- [X] T027 [US1] Remove ResultView (replaced by ChatView) in Verborra/Views/ResultView.swift. **WARNING: Find and remove all references to ResultView (imports, usages in OverlayContentView, etc.)**

**Checkpoint**: Full cycle of recording → streaming result → copy works. MVP is ready.

---

## Phase 4: Scenario 2 — Iterative refinement via chat (P2)

**Goal**: Text and voice input in the input, send to LLM, receive streaming response with context

**Independent test**: Get a result, type text in the input, press Enter — the LLM returns a response taking context into account

### Implementation of Scenario 2

- [X] T028 [US2] Create InputFieldView: input field 1-5 lines (auto-expansion via intrinsicContentSize, when exceeding 5 lines — vertical scroll via ScrollView with maxHeight), Enter = send, Shift+Enter = line break, 12px padding, mic/send icons, states idle/recording/processing in Verborra/Views/InputFieldView.swift
- [X] T029 [US2] Implement text input logic in RecordingViewModel: sendMessage (adding user message to ChatSession, calling StreamingFormattingService with messagesForAPI, streaming into a new assistant message), block send during processing (FR-047), block system "Copy"/"Paste" buttons in ControlBar during input recording/processing (FR-050) in Verborra/ViewModels/RecordingViewModel.swift
- [X] T030 [US2] Implement voice input into the input in RecordingViewModel: ⌥Space in postProcessing → InputRecordingState.recording, min 2 sec, processing via LLM with default prompt (FR-030), appending to existing text in input, NOT auto-send in Verborra/ViewModels/RecordingViewModel.swift
- [X] T031 [US2] Implement voice input visuals in InputFieldView: equalizer + timer inside the field, replacing mic/send icons with stop.circle.fill (FR-048, FR-049) in Verborra/Views/InputFieldView.swift
- [X] T032 [US2] Implement hotkey handling when input has focus: blocking 1/2/3, standard macOS commands (⌘C/V/A/X/Z/⇧Z), intercepting application ⌥-hotkeys, blocking ç/√ symbols (FR-011) in Verborra/ViewModels/RecordingViewModel.swift

**Checkpoint**: Iterative text refinement via text and voice input works

---

## Phase 5: Scenario 3 — Configuring recording parameters (P2)

**Goal**: Selection of microphone, input language, output language via bottom block buttons

**Independent test**: Change the output language, record voice — result is in the selected language

### Implementation of Scenario 3

- [X] T033 [P] [US3] Rework LanguageSelectorView: two separate buttons in ControlBar (hotkeys 2/3 — cyclic switching without dropdown), SF Symbols filled (waveform.circle.fill/text.bubble.fill), unified style with other buttons via ControlBarButtonLabel, locking after transition to state 2 (FR-021—FR-025) in Verborra/Views/Components/LanguageSelectorView.swift
- [X] T034 [P] [US3] Create MicrophoneSelectorButton: button in ControlBar (hotkey 1 — cyclic switching without dropdown), SF Symbol mic.fill, unified style via ControlBarButtonLabel, device list from AudioCaptureService.availableInputDevices(), locking after transition to state 2 in Verborra/Views/Components/MicrophoneSelectorButton.swift
- [X] T035 [US3] Integrate microphone and language buttons into ControlBarView (unified visual style with other buttons), handling hotkeys 1/2/3 with cyclic switching in RecordingViewModel, session-scoped settings (not persisted) in Verborra/Views/ControlBarView.swift and Verborra/ViewModels/RecordingViewModel.swift. **Depends on T024/T025** (shared file RecordingViewModel)

**Checkpoint**: Microphone and language settings work, locked after processing

---

## Phase 6: Scenario 4 — Selecting and switching the system prompt (P3)

**Goal**: Prompt selection from dropdown in the content area, collapsed prompt bubble in chat

**Independent test**: Click the prompt name, select another, record — result is processed with the new prompt

### Implementation of Scenario 4

- [X] T036 [US4] Rework PromptSelectorView: display prompt name in the center of the content area with `…` truncation, dropdown on click, availability before and during recording (FR-026—FR-029) in Verborra/Views/Components/PromptSelectorView.swift
- [X] T037 [US4] Implement collapsed system prompt bubble in ChatBubbleView: chevron.down.circle.fill/chevron.up.circle.fill icon for expand/collapse, full prompt text in expanded state (FR-039), default prompt is not editable (FR-029) in Verborra/Views/ChatBubbleView.swift

**Checkpoint**: Prompt selection works, prompt bubble is displayed in chat

---

## Phase 7: Scenario 5 — Manual result editing (P3)

**Goal**: Editing the last LLM message, taking edits into account in the chat context

**Independent test**: Press pencil on the last LLM message, change text, confirm, send a new request — the LLM takes edits into account

### Implementation of Scenario 5

- [X] T038 [US5] Implement editing mode in ChatBubbleView: pencil.circle.fill icon only for the last assistant message, switch to editable MarkdownTextView, checkmark.circle.fill (confirm) / xmark.circle.fill (cancel) icons, updating ChatMessage.content (FR-041—FR-044) in Verborra/Views/ChatBubbleView.swift
- [X] T039 [US5] Update RecordingViewModel: save edited text in ChatSession to take into account in context for subsequent LLM requests (FR-044) in Verborra/ViewModels/RecordingViewModel.swift

**Checkpoint**: Editing of the last LLM message and accounting for edits in the context work

---

## Phase 8: Scenario 6 — Copy and paste with/without Markdown (P3)

**Goal**: Two copy/paste modes — Markdown and plain text, with window closing

**Independent test**: Get a result, press ⌥⇧C — plain text without Markdown is in clipboard

### Implementation of Scenario 6

- [X] T040 [US6] Implement in RecordingViewModel: ⌥⇧C (copyPlainText via MarkdownStripper + dismiss), ⌥⇧V (pastePlainText + dismiss), update buttons in ControlBarView (FR-053), Accessibility check for paste (FR-055, FR-057), questionmark.circle.fill icon when access is missing in Verborra/ViewModels/RecordingViewModel.swift and Verborra/Views/ControlBarView.swift
- [X] T041 [US6] Implement doc.on.doc.fill icon (copy) for all messages in ChatBubbleView: copying the text of a specific bubble without closing the window (FR-042) in Verborra/Views/ChatBubbleView.swift

**Checkpoint**: All 4 copy/paste modes work (⌥C, ⌥⇧C, ⌥V, ⌥⇧V)

---

## Phase 9: Scenario 7 — Handling error states (P4)

**Goal**: Correct handling of missing microphone, API key, Accessibility

**Independent test**: Revoke microphone, open window — message with button to navigate to settings is visible

### Implementation of Scenario 7

- [X] T042 [US7] Implement error states in RecordingView: no microphone (message + settings button, scenario 7 acceptance 1-2), no API key (message + settings button, FR-035a, scenario 7 acceptance 3-4), microphone disconnection during recording (FR-034a), empty transcription (FR-035b) in Verborra/Views/RecordingView.swift
- [X] T043 [US7] VERIFIED Implement API errors: message in content area + "Retry" button (arrow.clockwise.circle.fill), saving audioData until successful processing (FR-035a), fallback to non-streaming on SSE error in Verborra/ViewModels/RecordingViewModel.swift

**Checkpoint**: All error states are handled with clear messages and actions

---

## Phase 10: Polish & Cross-Cutting Concerns

**Goal**: Final touch-ups, animations, consistency

- [X] T044 [P] Implement and verify smooth animations for all transitions (FR-004, SC-002): immediate window expansion to 50% screen height on transition to postProcessing (FR-036), InputFieldView appearance/disappearance (withAnimation), ControlBar configuration change (transition), ChatView scroll animation on new messages. Ensure no visual jumps on all state changes in Verborra/Views/OverlayPanel.swift, Verborra/Views/OverlayContentView.swift, Verborra/Views/InputFieldView.swift
- [X] T045 [P] Check existing hotkey reassignment logic in settings and complete missing checks: modifier required (FR-012), prohibition of conflicting combinations with macOS (`⌘C`, `⌘V`, `⌘X`, `⌘Z`, `⌘A`, `Space`, `Enter`, `Backspace`, `Delete` — FR-013), uniqueness among all application hotkeys (FR-014), warning on attempt to assign a forbidden hotkey (FR-015). **Steps**: (1) find current hotkey validation code (HotkeyRecorder or settings), (2) compile list of missing checks, (3) implement missing
- [X] T046 [P] VERIFIED Unit tests RecordingViewModel: new scenarios (two-phase transitions, streaming, input, state 1/2 hotkeys) in VerborraTests/ViewModels/RecordingViewModelTests.swift
- [X] T047 Final verification of measurable criteria: SC-001 (full cycle < 60 sec — measure time from hotkey to copy), SC-002 (smooth transitions without jumps — visual check of all states), SC-003 (3+ chat iterations without restarting), SC-004 (output language applied regardless of prompt), SC-005 (hotkeys with ⌥ when focus is on input), SC-006 (messages on missing Accessibility/microphone/API key), FR-002 multi-monitor (window appears on screen with active window/cursor with multiple monitors)
- [X] T048 [P] Run SwiftLint and build without warnings (Constitution Principle 5: "Every PR MUST pass linting (SwiftLint) and build without warnings"), check use of SF Symbols in all views (FR-058), fix found violations

---

## Dependencies and execution order

### Phase dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (models + services) — BLOCKS all scenarios
- **Scenario 1 (Phase 3)**: Depends on Phase 2 — MVP, first priority
- **Scenario 2 (Phase 4)**: Depends on Phase 3 (needs ChatView and basic flow)
- **Scenario 3 (Phase 5)**: Depends on Phase 3 (T035 depends on T024/T025 — shared file RecordingViewModel) — can run in parallel with Phase 4
- **Scenario 4 (Phase 6)**: Depends on Phase 3 (needs ChatBubbleView)
- **Scenario 5 (Phase 7)**: Depends on Phase 6 (needs ChatBubbleView with bubbles)
- **Scenario 6 (Phase 8)**: Depends on Phase 3 (needs basic copy/paste flow)
- **Scenario 7 (Phase 9)**: Depends on Phase 2 — can run in parallel with others
- **Polish (Phase 10)**: Depends on completion of all scenarios

### Scenario dependencies

```
Phase 1 (Setup)
    ↓
Phase 2 (Foundational)
    ↓
Phase 3 (US1: Recording + result) ←── MVP
    ├── Phase 4 (US2: Chat iterations)
    ├── Phase 6 (US4: System prompt)
    │       └── Phase 7 (US5: Editing)
    └── Phase 8 (US6: Markdown/plain text)

Phase 3 ──→ Phase 5 (US3: Recording settings) [T035 depends on T024/T025]
Phase 2 ──→ Phase 9 (US7: Errors) [parallel to Phase 3+]
```

### Parallel opportunities

- **Phase 1**: T001, T002, T003, T004 — all in parallel (different files)
- **Phase 1**: T007, T008, T009 — all in parallel (different services)
- **Phase 3**: T015, T016, T017 — tests in parallel
- **Phase 5 + Phase 4**: Can run in parallel after Phase 3 (T035 depends on T024/T025)
- **Phase 9**: Can run in parallel with any phase after Phase 2

---

## Parallel example: Phase 1

```bash
# In parallel (different files, no dependencies):
T001: Create ChatMessage in Verborra/Models/ChatMessage.swift
T002: Create TokenEstimator in Verborra/Models/TokenEstimator.swift
T003: Create WindowPhase in Verborra/Models/WindowPhase.swift
T004: Create InputRecordingState in Verborra/Models/InputRecordingState.swift
T007: Create StreamingFormattingService in Verborra/Services/StreamingFormattingService.swift
T008: Create TargetAppTracker in Verborra/Services/TargetAppTracker.swift
T009: Create MarkdownStripper in Verborra/Services/MarkdownStripper.swift

# Sequential (depends on T001 + T002):
T005: Create ChatSession (depends on ChatMessage + TokenEstimator)
T006: Modify RecordingState
```

---

## Implementation strategy

### MVP First (Scenario 1 only)

1. Complete Phase 1: Setup (9 tasks)
2. Complete Phase 2: Foundational (5 tasks)
3. Complete Phase 3: Scenario 1 (13 tasks, including tests)
4. **STOP and VALIDATE**: Test the full cycle of recording → result → copy
5. Ready for demo/use

### Incremental delivery

1. Setup + Foundational → Infrastructure ready
2. Scenario 1 → Test → **MVP ready!** (core value)
3. Scenario 2 + 3 (in parallel) → Chat + Settings
4. Scenario 4 + 6 (in parallel) → Prompt + Markdown modes
5. Scenario 5 + 7 → Editing + Errors
6. Polish → Final touch-ups

---

## Notes

- [P] tasks = different files, no dependencies — can run in parallel
- [Story] mapping to user scenarios from spec.md
- Each scenario must be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate the scenario
- Avoid: vague tasks, file conflicts, cross-scenario dependencies

### WARNING — RecordingViewModel: strategy for working with a shared file

RecordingViewModel is modified in **10+ tasks** from different phases (T023—T025, T029—T030, T032, T035, T039—T040, T043). To prevent conflicts:

1. **Strictly sequential execution**: tasks touching RecordingViewModel are FORBIDDEN to run in parallel — even if they are marked [P] on other files
2. **Order**: T023 → T024 → T025 → T029 → T030 → T032 → T035 → T039 → T040 → T043
3. **Commit after each task**: commit RecordingViewModel changes before moving on to the next task
