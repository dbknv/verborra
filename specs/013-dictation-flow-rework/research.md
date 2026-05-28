# Phase 0 Research: Dictation Flow Rework (v0.13)

**Date**: 2026-05-27
**Source**: [spec.md](spec.md), `## Clarifications` (5 questions resolved)

All `[NEEDS CLARIFICATION]` markers from the specification were resolved at the `/speckit.clarify` stage. This document records the applied technical decisions made by reviewing the app's source.

---

## R-001: Where to store `answerQuestionsInFirstMessage`

- **Decision**: Extend the existing `SystemPrompt` struct (in `Verborra/Models/SystemPrompt.swift`) with a boolean `answerQuestionsInFirstMessage`, default `false`. The field is serialized through `Codable` in the same JSON file `~/Library/Application Support/Verborra/system_prompts.json` already used by `PromptsStore`.
- **Rationale**:
  - A prompt is the only place in the system that persists per-prompt behavioral configuration. Storing it elsewhere (UserDefaults, a new JSON) would break the "everything for a prompt lives in one object" invariant already followed in the project.
  - The existing `PromptsStore` supports migrations (`currentDataVersion`), allowing schema updates without data loss.
  - The `false` default is fixed by the Q-Clarification: "off for every prompt."
- **Alternatives considered**:
  - Storing in UserDefaults (a single global setting) — rejected: breaks per-prompt semantics; the user couldn't tailor different prompts differently.
  - A separate table/file — rejected: unnecessary entity, violates Principle 3 (minimalism).
  - Encoded into the system prompts' `content` itself — rejected: then the setting wouldn't be user-manageable for user prompts.

---

## R-002: How to signal the LLM "do not answer questions"

- **Decision**: Inject the supplementary instruction as plain text **at the very end** of the final system message (after `PromptEnhancer`). For the first voice turn (`isFirstVoiceTurn == true && answerQuestionsInFirstMessage == false`), `RecordingViewModel.stopRecording` builds the system content manually:
  1. base prompt = `selectedPrompt.contentForLanguage(textLanguage)`
  2. `PromptEnhancer.enhance(...)` adds Response Language / Personal Preferences / Vocabulary sections
  3. the `## Critical Instruction` heading + the localized `DoNotAnswerInstruction.text(for: voiceLanguage)` is appended at the end
  4. the resulting prompt + transcription are sent through `streamingService.streamChat(messages:model:)` (NOT `streamFormat`, to avoid invoking `PromptEnhancer` twice).
- **Rationale**:
  - The OpenAI Chat Completions API has no structured "do not answer" flag. The only mechanism is a text instruction in the system role.
  - **End placement** is critical for small models (`gpt-4.1-nano`): empirically confirmed by a log where an instruction placed in the middle of the payload was ignored. The PromptEnhancer sections use "MUST" phrasing that outweighs a soft "do not answer" placed earlier.
  - **Wording** includes (see FR-003c): a priority marker ("CRITICAL INSTRUCTION — overrides any instruction above"), explicit "MUST NOT" prohibitions, and **a concrete example + counter-example**. The example (input: "how much is two plus two", correct output: "How much is two plus two?", wrong: "4") materially improves instruction-following on small models.
  - Does not require any URL/headers/payload format change.
  - Localization mirrors `contentForLanguage(voiceLanguage)`, so the system message never mixes languages.
- **Alternatives considered**:
  - Injecting BEFORE the PromptEnhancer sections (the first implementation iteration) — rejected: the model ignored it, confirmed by the log `verborra-2026-05-28T12.jsonl` (the model answered "6×3=88" while the checkbox was off).
  - Using only the bare wording without an example — rejected: the same logs showed this insufficient for `gpt-4.1-nano`.
  - Injecting the instruction into the user message in front of the transcription — rejected: contaminates user content and is harder to trace in logs.
  - Using `function_calling` or `response_format=json_schema` — rejected: too heavy for a simple behavior gate; introduces format-mismatch risk.
  - A second pass that strips the answer via a local post-filter — rejected: unreliable; parsing "question/answer" from text cannot be guaranteed.

---

## R-003: Where the "first voice message of the session" lives

- **Decision**: Introduce a private flag in `RecordingViewModel`: `private var didConsumeFirstVoiceTurn: Bool = false`. The flag is reset to `false` when a new `ChatSession` is created (in `startRecording` / `reset`), and flipped to `true` immediately after the first voice request is dispatched to the LLM. `ChatSession.prepareMessagesForLLM` gets a new `isFirstVoiceTurn: Bool` parameter, which the ViewModel computes as `!didConsumeFirstVoiceTurn && isVoiceInitiated`.
- **Rationale**:
  - "First voice message" is a session-lifecycle concept, which is the ViewModel's responsibility.
  - Not stored inside `ChatSession`, because `ChatSession` doesn't know how a message originated (voice vs. typed chat input).
  - Reset on session reset/recreate naturally follows ViewModel reinitialization.
- **Alternatives considered**:
  - Storing the flag in `ChatSession` — rejected: mixes message source (voice/text) with content.
  - Detecting by the role of the first message in `messages` (`role == .transcription`) — rejected: transcription is not a distinct role for the second-and-onwards voice recording, and `.transcription` already maps to `user` in the API request; the signal is unreliable.

---

## R-004: History truncation in `user`/`assistant` pairs

- **Decision**: Rework the algorithm in `ChatSession.prepareMessagesForLLM`:
  1. The system prompt is always first, always preserved.
  2. The latest `user` message is always preserved.
  3. Walking `messages` from the end, accumulate them into `selected` (in reverse) while `totalTokens + nextMessage.tokens <= availableBudget`.
  4. When the next message doesn't fit — drop a whole pair: the current oldest + its neighbor (usually the `assistant` paired with the user in the later position). Implementation: when dropping, check whether the next element in `selected` is an "orphaned" `assistant` without a matching user — if so, drop it too.
  5. The final payload is collected in chronological order: `[system, ...selected, lastUserMessage]`.
- **Rationale**:
  - Preserves conversational coherence (an assistant reply always has its user question nearby).
  - Satisfies SC-008 ("the oldest are dropped").
- **Alternatives considered**:
  - Drop one at a time from the start — rejected: clarification Q3 = pairs.
  - Drop in semantic "turns" while keeping the last pair — rejected: extra complexity with no visible benefit.

---

## R-005: `simple-voice-to-text` — content and read-only

- **Decision**:
  - All 10 locales of `SystemPromptDefinition.simpleVoiceToText` are rewritten to the short phrasing. Design strings (one per language):
    - en: `"Fix spelling errors and add punctuation. Return only the corrected text."`
    - ru: `"Исправь орфографические ошибки и расставь знаки препинания. Верни только исправленный текст."`
    - es: `"Corrige los errores ortográficos y añade puntuación. Devuelve solo el texto corregido."`
    - fr: `"Corrige les fautes d'orthographe et ajoute la ponctuation. Renvoie uniquement le texte corrigé."`
    - de: `"Korrigiere Rechtschreibfehler und füge Satzzeichen ein. Gib nur den korrigierten Text zurück."`
    - pt: `"Corrija os erros de ortografia e adicione a pontuação. Devolva apenas o texto corrigido."`
    - zh: `"纠正拼写错误并添加标点符号。仅返回修正后的文本。"`
    - ja: `"スペルミスを修正し、句読点を追加してください。修正されたテキストのみを返してください。"`
    - ko: `"맞춤법 오류를 수정하고 구두점을 추가하세요. 수정된 텍스트만 반환하세요."`
    - it: `"Correggi gli errori di ortografia e aggiungi la punteggiatura. Restituisci solo il testo corretto."`
  - For `simple-voice-to-text`, the `answerQuestionsInFirstMessage` checkbox is pinned at `false`.
  - `SystemPrompt` gains a computed property `var isReadOnly: Bool { isSystem && systemId == "simple-voice-to-text" }`. This is a code-side rule; it does not need a new Codable field.
  - In `PromptsStore.migrateIfNeeded` (`currentDataVersion = 3`), after loading, a force sync is performed: for every prompt with `isSystem && systemId == "simple-voice-to-text"`, `content` and `name` are rewritten from `SystemPromptDefinition.simpleVoiceToText`. After migration, `dataVersion` is set to `3`.
- **Rationale**:
  - The phrasings follow Clarification Q2 ("force-rewrite").
  - Using a computed `isReadOnly` instead of a new Codable field avoids the file/code drift risk: the rule lives in a single place.
  - The migration is targeted: only the specific prompt by `systemId` is touched.
- **Alternatives considered**:
  - Add a Codable `isReadOnly: Bool` to `SystemPrompt` — rejected: extra entity, duplicates the semantics of `isSystem`.
  - Delete and recreate the `simple-voice-to-text` record during migration — rejected: the UUID would change and references (e.g. `isDefault` set on this record) would break.

---

## R-006: Unifying the streaming path in `RecordingViewModel`

- **Decision**: Both LLM send paths use **`streamingService.streamChat(messages:model:)`** with an explicitly built `messages` array.
  - **Continuation (`sendMessage`)**: the non-streaming branch (`formattingService.format(...)`) is removed. The array is built via `ChatSession.prepareMessagesForLLM(isFirstVoiceTurn: false, ...)` → chat-mode system + full history + new user message (see R-012).
  - **First voice turn (`stopRecording`)**: no longer uses `streamFormat`. Instead, `RecordingViewModel` builds the system content manually: `PromptEnhancer.enhance(...)` + (optionally) `"\n\n## Critical Instruction\n\n" + DoNotAnswerInstruction.text(...)` → handed to `streamChat`. This gives explicit control over the DoNotAnswer position (see R-002) — `streamFormat` ran `PromptEnhancer` internally, making "after" injection impossible.
  - If `streamingService == nil` — `sendMessage` throws `RecordingError.formattingFailed("Streaming service unavailable")` (the F3 fix).
- **Rationale**:
  - The old non-streaming branch of `sendMessage` sent only one `text` without history — that's the original bug (US3 / FR-005 / FR-008).
  - Using `streamChat` directly for the first turn gives explicit control over the DoNotAnswerInstruction position (R-002) — critical for small models.
  - `streamChat` already accepts a `[(role, content)]` array correctly.
  - A unified path simplifies maintenance: FR-006 (edited), FR-007 (truncate), FR-006 (chain) live in `prepareMessagesForLLM` for continuation, while the first turn lives in `RecordingViewModel.stopRecording`.
- **Alternatives considered**:
  - Use `streamFormat` for the first turn as well — rejected: there is no way to insert DoNotAnswer AFTER `PromptEnhancer` (see R-002).
  - Extend `streamFormat` with `additionalSystemSuffix: String?` — rejected: an API surface enlargement for a single call site; explicit composition in RecordingViewModel is cleaner.
  - Keep both branches in `sendMessage` — rejected: duplication, risk of formatting divergence.

---

## R-007: Disabled state of Send and the re-record voice button during streaming

- **Decision**:
  - In `OverlayContentView`, propagate `isStreaming: Bool` (computed as `chatSession?.lastAssistantMessage?.isStreaming == true`) to `InputBar` and the voice-input overlay buttons.
  - On the SwiftUI Toggle — `.disabled(isStreaming)`; the re-record button — `.disabled(isStreaming || ...)` (combined with the existing state checks for `.idle`).
  - Additionally a defensive guard in `sendMessage`: if `lastAssistantMessage?.isStreaming == true` — `return`.
- **Rationale**:
  - Matches Clarification Q4 (blocking strategy).
  - SwiftUI `.disabled` is idiomatic; no new state machine needed.
- **Alternatives considered**:
  - Cancel-and-resend — rejected: clarification Q4.
  - Queue — rejected: clarification Q4.

---

## R-008: Placing the checkbox and tooltip in Settings → System Prompts

- **Decision**:
  - In `SettingsView`, inside the prompt-editor section (below the `content` field), add a horizontal `HStack`:
    - `Toggle("answer_in_first_message_label".localized, isOn: $prompt.answerQuestionsInFirstMessage).disabled(prompt.isReadOnly)`
    - `Button(action: { showHelp = true }) { Image(systemName: "questionmark.circle") }.popover(isPresented: $showHelp) { Text(helpText) }`
  - Localization keys:
    - `answer_in_first_message_label` = "Answer questions in the first message?" (en), "Отвечать на вопросы в первом сообщении?" (ru), and analogous for the other 8 locales.
    - `answer_in_first_message_help` = "When ON the model may answer questions heard in the first voice message. When OFF it only formats the text. Applies to the first message of the session only."
  - For `simple-voice-to-text` (read-only): content/name/toggle controls are shown disabled; the Delete button is hidden (`.disabled(prompt.isReadOnly)` + a conditional `.hidden()` for Delete).
- **Rationale**:
  - Uses the project's existing localization pattern (`Localizable.xcstrings`).
  - Introduces no new window/sheet — a popover next to an info icon is a macOS standard.
- **Alternatives considered**:
  - Inline description under the Toggle — rejected: visually overloads the editor form.
  - A separate "Advanced" pane — rejected: overkill for one setting.

---

## R-009: Logging (Principle 6)

- **Decision**: INFO/DEBUG-level logs added:
  - **INFO** on `prepareMessagesForLLM`: `prepareMessagesForLLM done` with metadata: `messageCount`, `droppedPairs`, `isFirstVoiceTurn`, `answerQuestionsInFirstMessage`, `injectedDoNotAnswer` (bool).
  - **INFO** on the `PromptsStore` v2 → v3 migration: `Migrated simple-voice-to-text content` with metadata: `previousContentHash` (hash only, not the content), `language`.
  - **DEBUG** on the `do-not-answer` injection: the full system prompt (with `privacy: .private`) for debugging.
  - **DEBUG** on truncation: indices of the dropped messages and the resulting `totalTokens`.
  - Chat message and transcription content are **never logged at INFO**; at DEBUG — with `\(text, privacy: .private)` (native macOS masking).
- **Rationale**: matches Principle 6 and the existing pattern in `ChatSession` / `ProcessingRouter`.

---

## R-010: Testing (Principle 5)

Tested layers and mocking strategy:

- **`SystemPromptTests`**: tests on `Codable` round-trip with/without the `answerQuestionsInFirstMessage` field (legacy file format migration); `isReadOnly` computed property for `simple-voice-to-text` vs. custom prompts.
- **`ChatSessionTests`** (new / extended): unit tests for `prepareMessagesForLLM`:
  - When the history fits the budget — all messages go through.
  - When it does not — pairs are dropped from the start; an orphaned `assistant` at the head is dropped too.
  - The system prompt and the latest user message are always preserved.
  - With `isFirstVoiceTurn=true, answerQuestionsInFirstMessage=false` — the system message gains the "do not answer" instruction in `voiceLanguage`.
  - With `isFirstVoiceTurn=false` — the instruction is absent.
  - Edited message: after updating `message.content`, the payload contains the new text.
- **`PromptsStoreTests`** (new / extended): v2 → v3 migration test on a fake JSON file; force-rewriting `simple-voice-to-text` content from any custom form → the new phrasing.
- **`RecordingViewModelTests`** (minimal, if mock infrastructure already exists): unit test that `sendMessage` actually calls `streamingService.streamChat` with an array starting with the system prompt and the latest user message at the end.

Mocking: the API is already protocol-based (`StreamingFormattingServiceProtocol`, `TranscriptionServiceProtocol`); no new mocks needed.

---

## R-011: Compatibility and rollback

- **Decision**: The migration `currentDataVersion = 3` is strictly forward-only. Rolling back to a previous app version reads the file cleanly (an unknown `answerQuestionsInFirstMessage` field is ignored — the standard `Codable.decodeIfPresent` behavior already applied in `SystemPrompt.init(from:)`). The rewritten `simple-voice-to-text` content in the old version is interpreted as a user customization, but visually matches the same text — no errors.
- **Rationale**: provides safe rollback to the previous build without data loss.

---

## R-012: Continuation system message (chat-mode override)

- **Decision**: For every session message **after the first voice turn**, `ChatSession.prepareMessagesForLLM` substitutes a **minimal chat-mode system message** in place of the user's dictation prompt. Content: `"You are a helpful assistant. Respond in <textLanguage.displayName>."`. The dialogue history (including the first voice transcription and the first formatted reply) is kept in the payload unchanged — the model uses it as context. This override fires when `isFirstVoiceTurn == false` (i.e. always for `sendMessage`).
- **Rationale**:
  - **Empirically confirmed bug**: when the dictation prompt (`Fix spelling errors and add punctuation. Return only the corrected text.`) was left in place, the LLM treated every continuation message as another piece of text to format. To "What did I forget — where were we running?" it returned the same question with proper punctuation, instead of replying in chat style.
  - **Source vs. first message**: user feedback confirmed that the user distinguishes "dictation → formatting" from "chat → conversation". Continuation messages belong to the second category by default.
  - **Language pin**: keep the `Respond in <lang>` directive so the model doesn't switch to the chat input's language.
  - **Context preserved**: the entire history (including transcription) is passed as regular chat history, so the model sees that the user dictated X, it was formatted into Y, and now they're asking Z.
- **Alternatives considered**:
  - Keep the dictation prompt + add a conditional hint like "if the last message is a question, reply conversationally, otherwise format" — rejected: the user explicitly said that having the model "figure it out" is unreliable; an explicit architectural split is better.
  - A per-prompt "applies only to first message" flag — rejected: extra UI complexity; for every current use case the dictation prompt is intrinsically applicable only to the first turn.
  - Distinguishing the message source (voice vs. text) and applying the dictation prompt to voice-2+, chat-mode to text — rejected as over-engineering. The current implementation already handles it: a repeated voice recording appends the transcription to `inputText`, which then goes through `sendMessage` as a normal continuation.

---

## Summary of resolved questions

| Source | Question | Decision |
|----------|--------|---------|
| Spec (Q1) | Edit cascade behavior | Keep subsequent history as-is |
| Spec (Q2) | `simple-voice-to-text` migration + editability | Force-rewrite + read-only |
| Spec (Q3) | Truncation granularity | Pairs user/assistant |
| Spec (Q4) | Send while streaming | Block (disable controls) |
| Spec (Q5) | Language of "do-not-answer" instruction | Localized to voiceLanguage + English fallback |
| Spec (Q6, 05-28) | Dictation prompt in continuation messages? | **No** — chat-mode override |
| Spec (Q7, 05-28) | DoNotAnswer position in system message | **End**, under `## Critical Instruction` |
| Spec (Q8, 05-28) | DoNotAnswer wording strength | Strengthened with explicit example/counter-example |
| Plan (R-001) | Where to store the new toggle | In `SystemPrompt`, Codable |
| Plan (R-003) | Where to track "first voice turn" | In `RecordingViewModel`, ephemeral |
| Plan (R-006) | Streaming vs non-streaming branches | Unify to streamChat (both first turn + continuation) |
| Plan (R-008) | UI placement | Inline `Toggle` + `?` icon popover under content field |
| Plan (R-012, 05-28) | Continuation system message | Chat-mode override (`"You are a helpful assistant. Respond in <lang>."`) |

All `[NEEDS CLARIFICATION]` markers are resolved.
