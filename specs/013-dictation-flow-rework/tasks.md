---
description: "Task list for feature 013 — Dictation and Message-Processing Flow Rework (v0.13)"
---

# Tasks: Dictation and Message-Processing Flow Rework (v0.13)

**Input**: Design documents from `/specs/013-dictation-flow-rework/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/llm-payload.md](contracts/llm-payload.md)

**Tests**: Included — required by Principle 5 of the constitution (business logic MUST be covered by unit tests) and by the "Test surface" section in data-model.md.

**Organization**: Tasks are grouped by user story; each story is independently testable. There is no `ui/*.md` folder for this feature (changes are localized to Settings and the overlay), so no separate UI-component tasks are generated.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no blocking dependencies).
- **[Story]**: Which user story the task belongs to (US1, US2, US3, US4).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Branch preparation and shared localization resources.

- [ ] T001 Verify that the `013-dictation-flow-rework` branch is clean (`git status`) and run the baseline `xcodebuild test -project Verborra.xcodeproj -scheme Verborra -only-testing:VerborraTests` — every existing test MUST be green before starting work.
- [X] T002 [P] Add the localized strings `answer_in_first_message_label` and `answer_in_first_message_help` for 10 locales (en, ru, es, fr, de, pt, zh, ja, ko, it) in `Verborra/Localizable.xcstrings`. Strings: see research.md R-008.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Domain changes in models/services that ALL user stories depend on. Without this phase no story can be implemented.

**⚠️ CRITICAL**: No user-story work can begin until this phase is complete.

- [X] T003 Extend `SystemPrompt` in `Verborra/Models/SystemPrompt.swift`: add `var answerQuestionsInFirstMessage: Bool` (default `false`), add the case to `CodingKeys`, use `decodeIfPresent(...) ?? false` in `init(from decoder:)`, always write in `encode(to:)`. Add the computed `var isReadOnly: Bool { isSystem && systemId == "simple-voice-to-text" }`. Update `makeDefault()` to set `answerQuestionsInFirstMessage = false`. Maps to FR-001, FR-009b, FR-010, FR-011, FR-012.
- [X] T004 Rework `Verborra/Models/SystemPromptDefinition.swift`: (a) rewrite `simpleVoiceToText.translations` for all 10 locales to the simplified phrasing (exact strings: research.md R-005); (b) add a new `DoNotAnswerInstruction` struct with `static let translations: [SupportedLanguage: String]` (10 locales, texts in data-model.md) and a static `text(for: SupportedLanguage) -> String` with English fallback. Maps to FR-003a, FR-009.
- [X] T005 [P] Extend `VerborraTests/SystemPromptTests.swift` with tests: (a) Codable round-trip with the `answerQuestionsInFirstMessage` field; (b) decoding old JSON WITHOUT the field yields `false`; (c) `isReadOnly == true` only for `simple-voice-to-text`, `false` for every other system / user prompt; (d) assert the simplified content of `SystemPromptDefinition.simpleVoiceToText` in all 10 locales — absence of substrings "абзац", "параграф", "paragraph", "paragraphes", "paragrafo", "Absätze", "段落", etc. Maps to SC-005.
- [X] T006 Rework `Verborra/Models/ChatSession.swift`, method `prepareMessagesForLLM`: (a) extend the signature with `isFirstVoiceTurn: Bool`, `answerQuestionsInFirstMessage: Bool`; (b) when `isFirstVoiceTurn && !answerQuestionsInFirstMessage` — append, separated by `\n\n`, the localized `DoNotAnswerInstruction.text(for: voiceLanguage)` BEFORE the `"Язык ответа: ..."` block; (c) rework the truncation algorithm: on budget overflow drop **pairs** (`user → assistant`); a lone "orphan" `assistant` at the head of the resulting selection is also dropped; (d) honor invariants INV-3..INV-6 from data-model.md (system always first, latest user always preserved, text taken from the current `message.content`). Update `ChatSessionProtocol` accordingly. Maps to FR-003, FR-005, FR-006, FR-007.
- [X] T007 [P] Create/extend `VerborraTests/ChatSessionTests.swift` with unit tests: (a) payload does not contain `DoNotAnswerInstruction` when `isFirstVoiceTurn == false`; (b) payload contains `DoNotAnswerInstruction` in `voiceLanguage` when `isFirstVoiceTurn == true && answerQuestionsInFirstMessage == false`; (c) payload does NOT contain the instruction when `answerQuestionsInFirstMessage == true`; (d) when over budget — pair truncation from the start, the latest user message is preserved (test on 5+ messages); (e) a lone orphan assistant at the head is dropped; (f) when `message.content` changes the payload contains the updated text. Maps to CON-1..CON-7, SC-002, SC-007, SC-008.
- [X] T008 Rework `Verborra/ViewModels/RecordingViewModel.swift`: (a) add the private state `private var didConsumeFirstVoiceTurn: Bool = false`; (b) when a new `ChatSession` is created (in `processRecording` and on `reset`) — clear the flag; (c) in `sendMessage` (chat text input) remove the non-streaming branch (the `formattingService.format(...)` call), keep only `streamingService.streamChat(messages: messagesForAPI, model: ...)`; pass `isFirstVoiceTurn: false` and `answerQuestionsInFirstMessage: selectedPrompt.answerQuestionsInFirstMessage` to `prepareMessagesForLLM`; (d) in the first voice send path (after transcription in `processRecording`) pass `isFirstVoiceTurn: !didConsumeFirstVoiceTurn` and set `didConsumeFirstVoiceTurn = true` after a successful send; (e) defensive guard: if `chatSession?.lastAssistantMessage?.isStreaming == true` — `sendMessage` `return`s immediately. Maps to FR-004, FR-008, FR-013, FR-014, FR-015.

**Checkpoint**: Foundation is ready. After T003–T008 (with green T005, T007) user-story work can start in parallel.

---

## Phase 3: User Story 1 — Dictation without answering questions (Priority: P1) 🎯 MVP

**Goal**: The default "voice → text" scenario: the user dictates with questions inside, and with the checkbox off (default) the model only formats — no answers, no follow-ups.

**Independent Test**: Pick a prompt with the "Answer questions in the first message?" checkbox off, dictate text with two or three questions in it; the result window contains only the formatted transcription, no model answers. (See Scenario 1 in quickstart.md.)

### Implementation for User Story 1

- [X] T009 [US1] In `Verborra/Views/SettingsView.swift`, in the prompt editor (`PromptEditorView` or equivalent), add a horizontal `HStack` below the `content` field with `Toggle("answer_in_first_message_label".localized, isOn: $editedPrompt.answerQuestionsInFirstMessage)` and `Button(action: { showHelpPopover.toggle() }) { Image(systemName: "questionmark.circle") }.popover(isPresented: $showHelpPopover) { Text("answer_in_first_message_help".localized).padding().frame(maxWidth: 320) }`. Apply `.disabled(editedPrompt.isReadOnly)` to the `Toggle`. Maps to FR-002.
- [X] T010 [P] [US1] Extend `VerborraTests/RecordingViewModelTests.swift` (create the file if missing) with an integration test: create `RecordingViewModel` with a mock `StreamingFormattingService`, pick a prompt with `answerQuestionsInFirstMessage = false`, drive the first voice send path (via the transcription handler), capture the passed `messages` array, assert that `messages[0].content` contains the substring "Do not answer" (en) or its `voiceLanguage` equivalent. Maps to SC-001.

**Checkpoint**: US1 is fully functional and independently testable.

---

## Phase 4: User Story 2 — Dictation with answer and continued dialogue (Priority: P1)

**Goal**: The user dictates a question to the model, the checkbox is on, the user receives the answer and continues the dialogue with the full context history.

**Independent Test**: Turn the checkbox on for a prompt; dictate a question; receive a substantive answer; send a clarification in the text input referencing the previous answer; confirm the model keeps context. (See Scenario 2 in quickstart.md.)

### Implementation for User Story 2

US2 needs no new UI or service tasks — the toggle is already added in US1 (T009), and the history wiring + unified streaming path is already in foundational T006/T008.

- [X] T011 [P] [US2] Add to `VerborraTests/RecordingViewModelTests.swift` an integration test: create a session with a prompt where `answerQuestionsInFirstMessage = true`, dictate a first voice (mock returns an answer), then call `sendMessage("clarification")`, capture the second `streamChat` call, assert that the passed `messages` array contains four elements in order `[system, user₁ (transcription), assistant₁ (answer), user₂ (clarification)]`, and that `messages[0].content` does NOT contain `DoNotAnswerInstruction`. Maps to CON-4, SC-006.

**Checkpoint**: US2 is functional. US1 + US2 work independently from one another through the same setting (the checkbox value).

---

## Phase 5: User Story 3 — Full current-chat history with edits and limits (Priority: P1)

**Goal**: Every subsequent message in the result window is sent with the full current-session history in the current (edited) form; when over budget the history is trimmed in pairs from the start; while streaming, input and re-recording are blocked.

**Independent Test**: 1) "remember the number 42" → answer → "what number did I ask?" → answer "42". 2) Edit "42" to "99" → same follow-up question → answer "99". 3) Synthetic long session (>budget) → the next send goes through, INFO log shows `droppedPairs>0`. (See Scenarios 3–6 in quickstart.md.)

### Implementation for User Story 3

Most of US3 is implemented in foundational (T006: pair truncation + edited content; T008: unified streaming path + guard). What remains is the UI block and extended tests.

- [X] T012 [US3] In `Verborra/Views/OverlayContentView.swift`, derive and pass `let isAssistantStreaming = viewModel.chatSession?.lastAssistantMessage?.isStreaming == true` into the child `InputBar` and the re-record voice button. On the input Send button: `.disabled(isAssistantStreaming || inputText.trimmed.isEmpty)`. On the overlay re-record button: combine `isAssistantStreaming` into the existing `.disabled(...)`. Maps to FR-015.
- [X] T013 [P] [US3] Extend `VerborraTests/ChatSessionTests.swift` with pair-truncation edge cases: (a) simulate a session of 6+ messages (3 user/assistant pairs) + a new user; artificially set a very small `maxTokenBudget`; assert that the result is `[system, ...lastPair, user_new]` and `[system, user_new]` for an extremely small budget; (b) simulate a session that starts with an orphan assistant and confirm it is dropped. Maps to SC-008.
- [X] T014 [P] [US3] Extend `VerborraTests/RecordingViewModelTests.swift` with a test: after `sendMessage` with `isStreaming = true` on the last assistant message, a repeated `sendMessage` MUST NOT initiate a new `streamChat` (asserted via mock invocation counter). Maps to FR-015, CON-8.
- [X] T015 [P] [US3] Extend `VerborraTests/RecordingViewModelTests.swift` with an edited-message test: create a session, add a user message "remember 42", add an assistant reply, programmatically change `messages[0].content` to "remember 99" (mimicking `onConfirmEdit`), send a new `sendMessage`, assert that the passed `messages[1].content == "remember 99"`. Maps to FR-006, SC-007.

**Checkpoint**: US3 is functional — the history fix applies uniformly, edited messages reach the payload in their current form, the model limit is handled in pairs, and during streaming the input is blocked.

---

## Phase 6: User Story 4 — Simplifying and locking the built-in `simple-voice-to-text` (Priority: P2)

**Goal**: The built-in `simple-voice-to-text` prompt is force-rewritten to the simplified phrasing in all 10 locales and becomes read-only in the Settings UI.

**Independent Test**: 1) First, on the old version (`main`), edit `simple-voice-to-text` content to "test-content". 2) Launch the new version (013). 3) Open Settings → System Prompts → select `simple-voice-to-text`. **Expected**: the content is reset to the new phrasing, controls (name, content, Toggle) are disabled, the Delete button is hidden/disabled. (See Scenario 7 in quickstart.md.)

### Implementation for User Story 4

The prompt content was already updated in foundational T004. What remains is the migration and the UI read-only handling.

- [X] T016 [US4] In `Verborra/Services/PromptsStore.swift`: (a) bump `currentDataVersion` from `2` to `3`; (b) extend `migrateIfNeeded()` with a block run when `version < 3`: find the prompt with `isSystem && systemId == "simple-voice-to-text"`; if found — force-rewrite `name` and `content` from `SystemPromptDefinition.simpleVoiceToText` (via `LocalizationManager.shared.currentLanguage`), set `answerQuestionsInFirstMessage = false`; if not found — add it via `ensureSystemPrompts()`; (c) save the file and write `UserDefaults.standard.set(3, forKey: Self.dataVersionKey)`. Maps to FR-009a.
- [X] T017 [US4] In `Verborra/Views/SettingsView.swift` (both in the prompt editor and in the prompt list): for entries with `prompt.isReadOnly == true` — render every editable field (`name`, `content`, `Toggle`) with `.disabled(true)`; hide the Delete button via a conditional `if !prompt.isReadOnly { Button("Delete") { ... } }` or render it disabled. Maps to FR-009b.
- [X] T018 [P] [US4] Create/extend `VerborraTests/PromptsStoreTests.swift` with a v2 → v3 migration test: prepare a temporary JSON file mimicking the v2 format with a custom `simple-voice-to-text` content; initialize `PromptsStore` against that file; call `migrateIfNeeded()`; assert that after the migration (1) the prompt's `content` equals `SystemPromptDefinition.simpleVoiceToText.content(for: .ru)` (or the current locale), (2) `answerQuestionsInFirstMessage == false`, (3) `UserDefaults` holds `dataVersion = 3`. Maps to FR-009a.

**Checkpoint**: US4 is functional. All four user stories are independently testable.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Logging, manual smoke validation per quickstart, final quality checks.

- [X] T019 Add INFO/DEBUG logs in `Verborra/Models/ChatSession.swift` (`prepareMessagesForLLM`): INFO with metadata `["messageCount", "droppedPairs", "isFirstVoiceTurn", "answerQuestionsInFirstMessage", "injectedDoNotAnswer"]`; at DEBUG — the full system prompt via `\(systemContent, privacy: .private)`. And in `Verborra/Services/PromptsStore.swift` (`migrateIfNeeded`): INFO `Migrated simple-voice-to-text content to v3 | language=...`. Use the existing `DiagnosticLogger`. Maps to Principle 6, R-009.
- [ ] T020 Run all 7 scenarios from `specs/013-dictation-flow-rework/quickstart.md` manually on the local build; record any deviations in `specs/013-dictation-flow-rework/verification/issues.md` (create the file if needed).
- [ ] T021 [P] Run `xcodebuild test -project Verborra.xcodeproj -scheme Verborra -only-testing:VerborraTests` in full and confirm every test (including existing ones) is green. Fix any regressions in existing tests inside the same branch.
- [ ] T022 [P] Run SwiftLint (`swiftlint --strict` or the existing config) over modified files; resolve any new warnings/errors. Maps to Principle 5.

---

## Phase 8: Post-Implementation Refinement (2026-05-28)

**Purpose**: Fixes uncovered during manual Xcode verification after Phase 7. They update behavior captured in new FR-003b / FR-003c / FR-005a (see spec.md, Session 2026-05-28).

- [X] T023 [US3] In `Verborra/Models/ChatSession.swift` (`prepareMessagesForLLM`): for continuation messages (`isFirstVoiceTurn == false`), substitute a **chat-mode system message** `"You are a helpful assistant. Respond in <textLanguage.displayName>."` in place of `systemPrompt.contentForLanguage(...)`. The full session history (including the first voice's transcription and the first formatted reply) remains in the payload as context. Maps to FR-005a / R-012. Empirically confirmed: without this fix the LLM treated every continuation message as another piece of text to format.
- [X] T024 [US1] In `Verborra/Models/SystemPromptDefinition.swift` rework `DoNotAnswerInstruction` for all 10 locales: add the "CRITICAL INSTRUCTION — overrides any instruction above" heading, explicit "MUST NOT answer / execute / clarify" lines, and **a concrete example + counter-example** (input: "how much is two plus two", correct output: "How much is two plus two?", wrong: "4"). Maps to FR-003c. Empirically: the soft "do not answer" phrasing was not followed by `gpt-4.1-nano` (log: "6×3=88" with the checkbox off).
- [X] T025 [US1] In `Verborra/ViewModels/RecordingViewModel.swift` (`stopRecording`): the first voice turn no longer uses `streamFormat`. Instead: (a) explicitly call `PromptEnhancer().enhance(...)` to append Response Language / Personal Preferences / Vocabulary sections; (b) append at the end `\n\n## Critical Instruction\n\n + DoNotAnswerInstruction.text(for: voiceLanguage)` when `isFirstVoiceTurn && !answerQuestionsInFirstMessage`; (c) send via `streamingService.streamChat(messages: [(system, ...), (user, rawText)], model: ...)`. Maps to FR-003b / R-002 / R-006. The goal is to place DoNotAnswer **after** every `MUST` section from PromptEnhancer, since small models weight instructions at the end of the system message more strongly.
- [X] T026 [US1/US3] Remove `Package.swift` and root `Package.resolved` — they generated a duplicate SPM scheme (lowercase `verborra`) that built an executable without `.app` or `Localizable.strings`/`Assets.car`. All 3 packages (swift-markdown, KeyboardShortcuts, swift-atomics) are already statically linked in `Verborra.xcodeproj` (confirmed via `otool -L`). Update README.md and CONTRIBUTING.md — remove the Package.swift mentions.
- [X] T027 Extend `VerborraTests/SystemPromptTests.swift`: a test for the new `DoNotAnswerInstruction` wording — the RU instruction must contain "Пример", the EN one must contain "Example input", and they must respectively contain "не должен отвечать" / "must not answer".
- [X] T028 Extend `VerborraTests/ChatSessionTests.swift`: a `testContinuation_dropsDictationPrompt_keepsChatMode` test — the system message does NOT contain substrings of the user's dictation prompt, but DOES contain "helpful assistant" and the response-language name. Maps to FR-005a.

**Checkpoint**: Phase 8 closes the gap between the formal implementation and real model behavior on small LLMs (`gpt-4.1-nano`). Every fix was empirically validated by the user on a running build.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: depends only on the branch and build state. T001 precedes everything.
- **Foundational (Phase 2)**: depends on Setup. Inside: T003 → T005 (SystemPrompt tests), T004 is independent of T003 (can [P] across different files); T006 does not depend on T003/T004 structurally, but logically uses `DoNotAnswerInstruction` from T004 → place T004 before T006; T008 uses T006 (the new `prepareMessagesForLLM` signature) → T008 after T006.
- **User Stories (Phases 3–6)**: ALL depend on Foundational (Phase 2). After Phase 2 they can run in parallel with enough engineers:
  - US1, US2, US3, US4 are independent at the implementation level (shared changes already in foundational).
  - In tests US2 / T011 uses the same Toggle as US1 / T009 — but the unit tests set the prompt state programmatically, so technical independence is preserved.
- **Polish (Phase 7)**: runs after all desired user stories.

### Detailed Within-Phase Order

Phase 2 (Foundational):
1. T003 (SystemPrompt) — can run in parallel with T004 (different files)
2. T004 (SystemPromptDefinition) — can run in parallel with T003
3. T005 (SystemPromptTests) — after T003 and T004
4. T006 (ChatSession) — after T004 (needs `DoNotAnswerInstruction`)
5. T007 (ChatSessionTests) — after T006
6. T008 (RecordingViewModel) — after T006

Phase 3 (US1):
1. T009 (Settings UI) — independent, can start right after Phase 2
2. T010 (US1 integration test) — after T008 (needs RecordingViewModel mocks)

Phase 4 (US2):
- T011 — after T008 (same as US1)

Phase 5 (US3):
- T012 (Overlay disabled) — after T008
- T013, T014, T015 — after T006/T008, parallel to one another ([P])

Phase 6 (US4):
- T016 (PromptsStore migration) — after T003
- T017 (Settings read-only UI) — after T003 (needs `isReadOnly`), structurally independent of T009 (different sub-sections of SettingsView, but may merge-conflict — execute sequentially)
- T018 — after T016

Phase 7 (Polish):
- T019 — after T006 and T016
- T020 — after every US (3–6)
- T021, T022 — after everything

### Parallel Opportunities

- T003 and T004 — different files → [P]
- T005 and T007 — different test files → can run [P] after their impl tasks
- After foundational, in Phases 3–6 almost every task can run in parallel by different developers/branches.
- T013, T014, T015 — three separate test files → [P]
- T021 and T022 — independent checks → [P]

---

## Parallel Example: Phase 2 Foundational

```bash
# After T001 run T003 and T004 in parallel (different files):
Task T003: "Extend SystemPrompt in Verborra/Models/SystemPrompt.swift"
Task T004: "Rework SystemPromptDefinition in Verborra/Models/SystemPromptDefinition.swift"

# After T003+T004 finish — run T005 in parallel with (T006 → T007 → T008):
Task T005: "Extend SystemPromptTests"
Task T006: "Rework ChatSession.prepareMessagesForLLM"
Then Task T007: "ChatSession tests"
Then Task T008: "Rework RecordingViewModel"
```

## Parallel Example: After Foundational

```bash
# After Phase 2 — three developers pick US in parallel:
Dev A: T009 (US1 UI) → T010 (US1 test)
Dev B: T011 (US2 test) and T012, T013, T014, T015 (US3) sequentially
Dev C: T016 (US4 migration) → T017 (US4 UI) → T018 (US4 tests)
```

---

## Implementation Strategy

### MVP First (US1 + foundational)

1. T001, T002 (Setup)
2. T003 → T004 → T005 → T006 → T007 → T008 (Foundational)
3. T009 → T010 (US1)
4. **STOP and VALIDATE**: quickstart.md Scenario 1 — dictation without answers works on defaults.
5. That's already a working MVP — the core product use case is delivered.

### Incremental Delivery

1. Setup + Foundational → infrastructure ready.
2. + US1 → MVP (dictation without answers).
3. + US2 → second scenario (voice-assistant with continued dialogue).
4. + US3 → chat reliability (history, edits, limits, streaming block) — the bug is fixed.
5. + US4 → the built-in prompt is simplified and locked.
6. + Polish → logs, smoke test, SwiftLint.

### Parallel Team Strategy

- Phase 2 (Foundational) is ALWAYS owned by a single person or a tightly coordinated pair — otherwise merge conflicts in `ChatSession` / `RecordingViewModel`.
- After Phase 2 three or four developers can run US1/US2/US3/US4 in parallel.
- Phase 7 — a fifth developer or someone who has just finished.

---

## Notes

- **Tests included**: required by Principle 5 (P5) of the constitution — business logic MUST be covered by unit tests. The concrete list is synchronized with the "Test surface" section in [data-model.md](data-model.md).
- **Mocking**: the API is already protocol-based (`StreamingFormattingServiceProtocol`, `TranscriptionServiceProtocol`, `FormattingServiceProtocol`). No new mocks need to be written — reuse the ones already in `VerborraTests/`.
- **Files under change** (full list, for merge planning):
  - `Verborra/Models/SystemPrompt.swift` (T003)
  - `Verborra/Models/SystemPromptDefinition.swift` (T004)
  - `Verborra/Models/ChatSession.swift` (T006, T019)
  - `Verborra/ViewModels/RecordingViewModel.swift` (T008)
  - `Verborra/Services/PromptsStore.swift` (T016, T019)
  - `Verborra/Views/SettingsView.swift` (T009, T017)
  - `Verborra/Views/OverlayContentView.swift` (T012)
  - `Verborra/Localizable.xcstrings` (T002)
  - `VerborraTests/SystemPromptTests.swift` (T005)
  - `VerborraTests/ChatSessionTests.swift` (T007, T013) — possibly a new file
  - `VerborraTests/RecordingViewModelTests.swift` (T010, T011, T014, T015) — possibly a new file
  - `VerborraTests/PromptsStoreTests.swift` (T018) — possibly a new file
- **Commit strategy**: one commit per task or logical group (e.g. T003+T005 "SystemPrompt + tests", T006+T007 "ChatSession refactor + tests").
- **Stop point**: after Phase 3 (MVP US1) it is safe to stop, deploy, and evaluate the value before continuing.
