# Feature Specification: Dictation and Message-Processing Flow Rework (v0.13)

**Feature Branch**: `013-dictation-flow-rework`
**Created**: 2026-05-27
**Status**: Draft
**Input**: User description: "Rework the dictation flow. Add a toggle in prompt settings, 'Answer questions inside the text' (Yes/No), that applies only to the first message from voice. When set to 'No' the voice text is only formatted — no answers, no clarifying questions. When 'Yes' the model may answer, and the user continues the dialogue in the chat as usual. Fix the bug where a new chat message must take the whole prior conversation into account. Simplify the default `simple-voice-to-text` system prompt down to 'fix spelling errors and add punctuation'."

## Clarifications

### Session 2026-05-27

- Q: What should happen to the subsequent messages (assistant replies and later) in the history when the user edits an earlier user message? → A: Keep the whole subsequent history as-is; the payload carries the edited version of the earlier message and the unchanged later messages.
- Q: What should be done with the built-in `simple-voice-to-text` prompt content during migration (given that some users may have edited it manually)? → A: Force-overwrite to the new simplified phrasing in all locales. Additionally, the `simple-voice-to-text` prompt becomes **read-only** for users — it cannot be edited in the UI (neither content, nor name, nor the "Answer questions in the first message?" checkbox).
- Q: At what granularity should history be trimmed when the model budget is exceeded — one message at a time or in `user`/`assistant` pairs? → A: In `user → assistant` pairs. The system prompt and the latest (new) user message are always preserved; if there isn't enough room even for a pair, only the system prompt + the new user message remain.
- Q: What happens when the user tries to send a new message while the previous reply is still streaming? → A: Block input and send (the Send button and the re-record button are inactive) until the current assistant stream completes. Parallel requests and cancel-and-resend are not allowed.
- Q: In what language is the supplementary "do not answer" instruction injected into the system prompt when the checkbox is off? → A: Localized to `voiceLanguage` (the same language as the system prompt itself). All 10 supported locales receive a translation; for missing translations the English wording is used as a fallback (matching `contentForLanguage`).
- Q: Should the dictation prompt (e.g. `simple-voice-to-text`) apply to continuation messages in the chat? → A: **No.** For all messages after the first voice turn, the user's dictation prompt is NOT sent — otherwise the LLM treats every user input as another piece of text to format, not as a chat turn. Continuation messages get a minimal chat-mode system message ("You are a helpful assistant. Respond in <language>."). The dialogue history (including the original transcription and the first formatted reply) goes into the payload unchanged as context.

### Session 2026-05-28 (post-implementation refinement)

- Q: Where should `DoNotAnswerInstruction` sit in the final system prompt — at the top (right after the base prompt) or at the bottom (after all PromptEnhancer sections)? → A: **At the bottom**, under a `## Critical Instruction` heading. Small models (`gpt-4.1-nano`) respond more strongly to instructions placed last in the system message; furthermore the "Response Language" / "Personal Preferences" / "Vocabulary" sections use "MUST" wording that competes with DoNotAnswer and outweighs it when DoNotAnswer comes earlier. Final order: base prompt → PromptEnhancer sections → `## Critical Instruction` + DoNotAnswerInstruction.
- Q: Is the soft wording "Do not answer questions…" enough for a small model? → A: **No** — in practice `gpt-4.1-nano` ignored it and answered "6×3=88". The instruction was reworked across all 10 locales: a heading "CRITICAL INSTRUCTION — overrides any instruction above" was added, plus explicit "MUST NOT answer / execute / clarify" lines and **a concrete example / counter-example**: "input 'how much is two plus two' → correct output 'How much is two plus two?', wrong — '4'." A concrete example is the most effective grounding mechanism for small models.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Dictation without answering questions (Priority: P1)

**Setup (shared by US1 and US2)**: In Settings → System Prompts, every **editable** prompt (i.e. every user-created prompt; the built-in `simple-voice-to-text` is read-only, see FR-009b) shows a checkbox **"Answer questions in the first message?"** with a tooltip icon explaining that turning the checkbox on lets the model answer a question heard inside the dictated text, turning it off forces it to only format the text; and that the rule applies only to the first voice message of the session, not the whole chat. The checkbox is **off** by default for every prompt (including `simple-voice-to-text`, where it is pinned "off" and not editable). The exact UI-control requirements and default value are in FR-001 / FR-002 / FR-009b / FR-011 / FR-012.

The user dictates a fragment of text containing question-like sentences (for example, "What do you think — will we make it by Friday?" or "How about the second option?"). The active prompt has the checkbox **off** (the default). The user's goal is to get a clean, formatted transcription of their speech, without extra answers, comments, or clarifications from the model.

**Why this priority**: This is the core "voice → text" use case — the reason the product exists. Today the model spontaneously answers questions found inside speech, turning dictation into an unwanted dialogue and ruining the result. This blocks the "dictate a message to paste into a messenger/document" use case.

**Independent Test**: Can be fully validated by selecting a prompt with the "Answer questions in the first message?" checkbox off, dictating a fragment containing two or three questions, and verifying that the result window contains only the formatted user text — no answers, no follow-up questions, no "Q:/A:" markers.

**Acceptance Scenarios**:

1. **Given** the active prompt has the "Answer questions in the first message?" checkbox off, **When** the user dictates a phrase containing one or more questions, **Then** the result window shows only the formatted transcription with no model answers.
2. **Given** the active prompt has the checkbox off, **When** the transcribed text contains ambiguous or incomplete phrasing, **Then** the model does not ask clarifying questions but formats what was said as-is.
3. **Given** the active prompt has the checkbox off, **When** the user — after the first result — sends a text chat message "And what do you think?", **Then** the model answers this explicit chat question, since the "do not answer" restriction applied only to the first voice message.

---

### User Story 2 — Dictation with an answer and continued dialogue (Priority: P1)

The user dictates a question or task addressed to the model (for example, "Explain how SwiftUI Observable works"). The active prompt has the "Answer questions in the first message?" checkbox **on**. After receiving the answer the user continues the dialogue in the result window: clarifying, asking for rewordings, posing follow-ups. Every subsequent message takes the whole prior conversation into account.

**Why this priority**: This is the second key mode — "voice assistant in the result window." Without full chat history, follow-ups lose meaning (the model has no context), which is the baseline expectation for any modern LLM chat.

**Independent Test**: Choose a prompt with the "Answer questions in the first message?" checkbox on, dictate a question to the model, receive the answer, send a chat follow-up "Can you go deeper on the second point?" — and confirm the model's answer leans on what was said earlier rather than interpreting the follow-up out of context.

**Acceptance Scenarios**:

1. **Given** the active prompt has the "Answer questions in the first message?" checkbox on, **When** the user dictates a question, **Then** the model substantively answers it, and the question text (formatted) and the model's answer both remain in the chat history.
2. **Given** the result window already contains a pair "voice user request ↔ model answer", **When** the user sends another text or voice message in the same window, **Then** the model receives the full current conversation history (system prompt + every prior message + the new one) and answers with context.
3. **Given** the dialogue in the result window already has several messages, **When** the user asks "rewrite the previous answer shorter", **Then** the model relies on its own previous answer in the history and returns a shorter version of it.

---

### User Story 3 — Full current-chat history with edits and model limits (Priority: P1)

The user has already had several exchanges in the result window (dictation → answer → text follow-up → answer → another follow-up). Some messages may have been edited in the floating window (the existing message-edit UI). When the next message is sent, the model must receive **only this current chat session's history** (no messages from other sessions, no empty starts), **in its current form** (with all edits the user made in the result window), and **trimmed against the model's limit** (if the total exceeds the budget — the oldest messages from the start of the history are dropped until the new message fits).

Today the chat has a path where the message being sent does not consider the full current conversation, and the model responds "from scratch" or without taking its own earlier replies into account.

**Why this priority**: This is an undeniable bug breaking the basic chat functionality. Any subsequent message in the result window should by default behave like a regular multi-turn chat — both the UX standard and the user's expectation.

**Independent Test**: Open a result window, run 3–4 messages with a known context (e.g. ask "remember the number 42"), then send "what number did I ask you to remember?". If the model answers "42" — the bug is fixed; if it asks for clarification or answers without context — it isn't. Additionally: edit one of the earlier sent messages to "remember the number 99", send the same follow-up — the model must answer "99", confirming the edited version is what went into the history.

**Acceptance Scenarios**:

1. **Given** the result window already has at least one user message and one model reply, **When** the user sends a new message, **Then** the model receives the system prompt + the full sequence of messages from **only this chat session** (in role/order) + the new user message.
2. **Given** the user edited the content of one or more earlier visible messages in the floating window (through the existing edit UI), **When** they send the next message, **Then** the request to the model carries the edited version (the current on-screen text), not the original content.
3. **Given** the chat has accumulated many messages and their total exceeds the chosen model's token budget, **When** the user sends a new message, **Then** the system drops messages **from the very start of the history in `user → assistant` pairs** (one pair per iteration), until the request fits the budget; an orphaned assistant at the head is also dropped; the system prompt and the new user message are always preserved. Messages from the middle or tail of the history are not dropped.
4. **Given** the latest user message was sent by voice (a re-recording in the result window), **When** it reaches the model, **Then** it behaves like a regular `user` message in an ongoing dialogue — the "Answer questions in the first message?" setting **no longer** applies to it, since it isn't the first.

---

### User Story 4 — Simplifying the default `Simple Voice To Text` prompt (Priority: P2)

The default built-in `simple-voice-to-text` prompt is simplified to a minimalistic phrasing: "Fix spelling errors and add punctuation. Return only the corrected text." The goal is to obtain a result as close to the original as possible — without "improvements", rewordings, or paragraph splitting unless explicitly asked.

**Why this priority**: The current phrasing also asks the model to split into paragraphs by meaning, which is overkill for short voice messages and sometimes produces unwanted structuring. It is a one-line change across all locales, but improves the default experience.

**Independent Test**: Compare the formatting result of the same voice recording with the previous and new prompt content. The new result must be shorter, without inserted paragraph breaks and without rephrased sentences.

**Acceptance Scenarios**:

1. **Given** the user uses the default `simple-voice-to-text` prompt, **When** they dictate a simple 1–2-sentence phrase, **Then** the result differs from the raw transcription only in capitalization, punctuation, and corrected recognition typos — without paragraph splits or rephrasing.
2. **Given** the updated `simple-voice-to-text` prompt, **When** it is shown in Settings → System Prompts, **Then** its content in every supported language is shortened to a single short instruction "fix spelling and add punctuation, return only the corrected text."

---

### Edge Cases

- **The voice text contains no questions and the checkbox is off**: behavior is unchanged from the old one — the text is simply formatted. No regressions.
- **The voice text consists of a single question and the checkbox is off**: the model returns that question as plain text (formatted), without answering it. It must not return an empty string or a phrase like "you asked a question."
- **The user switches the prompt via the selector after receiving the first reply**: the new prompt's behavior applies to the next operation (re-send / new recording); already received messages are not rewritten retroactively.
- **The checkbox is on ("answer"), but the model decides the text has nothing to answer**: the model simply returns the formatted text as usual. Turning the checkbox on removes the prohibition but does not force the model to invent an answer.
- **A long conversation exceeds the model's context window**: history is trimmed **from the start in `user → assistant` pairs** (one pair per iteration) until the request fits the budget; an orphaned assistant at the head is also dropped; the system prompt and the new user message are always preserved. Middle and tail messages do not drop. (See FR-007.)
- **The user edited an old message that, after limit-trimming, would not be in the request anyway**: the edit is preserved in the session's local history (still visible in the window), but only the "tail" of the history that fits the budget goes to the model. This is the expected truncation behavior.
- **The user edited an old user message that already has an assistant reply later in the history**: the subsequent history (that assistant reply and any later messages) is **not deleted** and **not regenerated automatically**. The payload carries the edited version of the earlier message + the unchanged later messages. If the user wants a "fresh" answer with the edit in mind — they send a new chat message and the model reconciles the context itself. (See FR-006.)
- **Voice input is reused in an existing result window (a second recording in a row)**: the first message in the session is considered "the first voice" exactly once. Every subsequent voice message in the same session is treated like a regular chat message, and the "Answer questions in the first message?" setting does not apply to it.
- **The user resets the session (Reset)**: the "first voice message" counter is reset, and the prompt's rule applies again to the next recording.
- **Locales with no translation of the new system prompt**: the English phrasing is used as the fallback (the same way `contentForLanguage` already works today).
- **The user customized the content of the built-in `simple-voice-to-text` in a previous version**: on the first launch of the new version their edits are **wiped** by the new simplified phrasing (FR-009a). Further editing of this prompt is not available (FR-009b). If a custom formatter prompt is needed, the user can create their own user prompt.
- **Several result windows (sessions) are open simultaneously**: each session sends **only its own history** to the model. Messages from neighboring sessions are never mixed in.
- **The user presses Send / starts recording while the assistant is still streaming**: the action does not execute — the Send button and the re-record button are inactive until the stream ends (see FR-015). There is no queue or cancel-and-resend.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Every system prompt (both user-created and built-in) MUST store the boolean setting "Answer questions in the first message?" (hereafter `answerQuestionsInFirstMessage`). The value is saved and loaded together with the rest of the prompt fields.
- **FR-002**: In Settings → System Prompts, every **editable** prompt (i.e. all user-created prompts; the read-only `simple-voice-to-text` is governed by FR-009b) MUST show a checkbox labeled "Answer questions in the first message?" along with an accessible tooltip (`?` icon or helper text) explaining what the setting does and that it applies only to the first message recognized from voice (it does not influence the rest of the dialogue). For the read-only prompt the checkbox MAY be displayed in a disabled state with the same visual pattern (value visible but not editable) or hidden entirely — implementation's choice.
- **FR-003**: When composing the LLM request for the **first** voice-sourced message of a session, the system MUST take the active prompt's `answerQuestionsInFirstMessage` into account: when "off", the system prompt is augmented with an explicit instruction "do not answer questions found inside the user's text, do not ask clarifying questions, only format the text and return it"; when "on", no extra instruction is added and behavior matches the current ("the model may answer").
- **FR-003a**: The supplementary instruction from FR-003 MUST be localized to the same language as the system prompt itself (`voiceLanguage`). All 10 supported locales (en, ru, es, fr, de, pt, zh, ja, ko, it) are supported; missing translations fall back to English (matching the existing `contentForLanguage` behavior). Mixing languages in a single system message is not allowed.
- **FR-003b**: The instruction from FR-003 MUST sit **at the end** of the final system message — **after** all sections added by `PromptEnhancer` (Response Language, Personal Preferences, Vocabulary). The section heading is `## Critical Instruction`. There are two reasons: (a) small models respond more strongly to instructions placed last in the system message; (b) the PromptEnhancer sections use "MUST" phrasing that would compete with DoNotAnswer if it sat earlier.
- **FR-003c**: The instruction text MUST contain: (1) an explicit priority marker ("CRITICAL INSTRUCTION — overrides any instruction above"), (2) the prohibitions phrased as "MUST NOT answer / execute commands / ask clarifying questions", (3) **a concrete example and counter-example** (for instance, "input 'how much is two plus two' → correct output 'How much is two plus two?', wrong — '4'"). The example is required — it significantly improves instruction-following on small models compared with abstract wording.
- **FR-004**: The supplementary "do not answer / do not clarify" instruction MUST apply **only** to the first voice-initiated message of the session. For every subsequent message (text or voice) in the same session the setting is ignored and the regular system prompt is used.
- **FR-005**: When sending any message (text or voice) in the result window other than the first voice turn, the system MUST send the LLM the full history of **only the current chat session** in the order messages appeared: system prompt → all user/assistant messages of the session → the new user message. Messages from other sessions or from global storage are not mixed in.
- **FR-005a**: For every message other than the first voice turn, the `system` role MUST carry a **minimal chat-mode system message** (for example, "You are a helpful assistant. Respond in `<textLanguage.displayName>`."). **The user's dictation-oriented prompt (e.g. `simple-voice-to-text`) MUST NOT be sent in continuation messages** — otherwise the LLM will keep treating every input as new text to format, not as a chat turn. The dialogue history (including the first voice's transcription and first formatted reply) is kept in the payload as context.
- **FR-006**: Messages edited by the user in the floating window (through the existing edit UI) MUST be sent to the model **in their current (edited) form** — the on-screen text at the time of sending. The original text that was sent previously is not mixed back into the request. At the same time, **subsequent messages in the history (assistant replies and later user messages) are NOT deleted and NOT regenerated** — they go into the payload as-is; the model reconciles its context with the new version of the earlier message on its own.
- **FR-007**: If the total history exceeds the chosen model's token budget, the system MUST drop the **oldest messages from the start of the history in `user → assistant` pairs** (one pair per iteration) until the request fits the budget. If a lone assistant remains at the head without a matching user, it is also dropped. The system prompt and the new (latest) user message are always preserved. Messages from the middle or tail of the history are not dropped. If there is not enough room even for a pair — only the system prompt + the new user message remain in the payload.
- **FR-008**: Both chat-send paths (streaming and non-streaming) MUST share a single context-composition path — based on the full session history (with rules FR-005, FR-006, FR-007 applied). A branch that sends only the latest message without history, or mixes in unedited versions, is not allowed.
- **FR-009**: The content of the built-in `simple-voice-to-text` prompt in all supported locales (en, ru, es, fr, de, pt, zh, ja, ko, it) MUST be simplified to a short instruction equivalent to "fix spelling errors and add punctuation, return only the corrected text." References to splitting by meaning into paragraphs are removed.
- **FR-009a**: When a new app version is launched, the system MUST **force-overwrite** the stored content of the built-in `simple-voice-to-text` prompt with the new simplified phrasing — regardless of whether the user customized it in past versions. The old phrasing is not preserved.
- **FR-009b**: The built-in `simple-voice-to-text` prompt MUST be flagged as **read-only** in the system: in the Settings → System Prompts UI, its fields (name, content, "Answer questions in the first message?" checkbox) are non-editable; its Delete button is hidden or disabled. The content of this prompt can be changed only together with a new app version.
- **FR-010**: Existing user prompts loaded from disk MUST migrate cleanly to the new schema: when the `answerQuestionsInFirstMessage` field is missing, the default value "off" (do not answer) is substituted. Files in the old format open without errors.
- **FR-011**: When creating a new user prompt the `answerQuestionsInFirstMessage` value MUST be set to "off" by default, and the UI checkbox is rendered accordingly.
- **FR-012**: On first initialization of the built-in `simple-voice-to-text` prompt, the `answerQuestionsInFirstMessage` value MUST be set to "off".
- **FR-013**: A session reset (Reset / a new recording after closing the window) MUST clear the "first voice message has been sent" flag, so the prompt's rule applies again to the first message of the next recording.
- **FR-014**: If the user changes the active prompt via the selector **before** sending the first voice message, the newly selected prompt's rule applies to the first message. If the user changes the prompt **after** the first message has already been sent, the change does not rewrite messages that were already sent but does affect subsequent re-sends / new recordings.
- **FR-015**: While the model's reply is streaming (the last assistant message is marked `isStreaming`), the system MUST block any new request in the same session: the text-input Send button and the re-record voice button are inactive. Parallel / competing LLM requests from one session are not allowed. Sending a new message becomes possible only after the stream fully completes (successfully or with an error).

### Key Entities

- **SystemPrompt**: extended with the boolean field `answerQuestionsInFirstMessage` (default "off"). Semantics: applies only to the first voice message of the session. Previously serialized prompts decode with the "off" default.
- **ChatSession**: remains the source of truth for the full history of **this** session. The method that composes the LLM request is responsible for building the payload uniformly for all send types (first voice turn, text, re-recording), with: (a) messages taken from the session's local history, (b) their current (edited) text, (c) trimming from the start when over budget.
- **VoiceTurnPolicy** (a conceptual entity, not necessarily a dedicated type): the rule describing how the system prompt is modified depending on the `answerQuestionsInFirstMessage` value and whether the current message is the first voice turn. Possible states: "no modification" (on, or not the first voice turn), "add the no-answer / no-clarification block" (off and first voice turn).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a set of 10 typical voice recordings each containing at least one rhetorical or model-directed question, with the "Answer questions in the first message?" checkbox off, 100% of the resulting texts contain no model answer lines and no follow-up questions.
- **SC-002**: In dialogue-continuation mode (after the first voice message), 100% of subsequent sends deliver the **current session's history** to the model in its **current (edited) form** — checked by snapshotting the request payload (compared to what is displayed in the window at the time of sending).
- **SC-003**: Regression check: with the checkbox on, the average quality of the model's answer to a voice question (subjective "useful/irrelevant" scale on 5 control queries) does not degrade compared with current behavior.
- **SC-004**: Time from end-of-recording to the first visible answer (or formatted text) does not increase by more than 5% over the current baseline — adding the "do not answer" instruction must not noticeably increase latency.
- **SC-005**: All 10 locales of the built-in `simple-voice-to-text` prompt are updated and preserve a consistent meaning "fix spelling and add punctuation." Verified by an automated test of the presence/absence of key phrases (e.g. absence of "абзацы", "paragraphs", "параграф" in the new content).
- **SC-006**: The chat-history-loss bug reproduces on current `main` (pre-feature) and does not reproduce on the feature branch: in the "dictation → answer → text 'what number did I ask you to remember?'" scenario, the model answers with the correct number in 100% of repetitions.
- **SC-007**: In the edit scenario: the user dictates "remember the number 42", receives an answer, edits their message to "remember the number 99", asks "what number did I ask you to remember?" — in 100% of repetitions the model answers "99", confirming the edited version went into the payload.
- **SC-008**: In the budget-overflow scenario: with an artificially generated session exceeding the context budget by ~50%, the next send completes successfully, the request contains **only the tail** of the session, the oldest messages are correctly dropped from the start, and no middle messages drop (verified via payload snapshot).

## Assumptions

- The `answerQuestionsInFirstMessage` default for all new, migrated, and built-in prompts is **off** ("do not answer"). This is an intentional behavior change vs. current `main`: the product's primary use case is dictation, so the new default better matches the main scenario. A user who wants the previous behavior (the model answers questions in the first message) explicitly turns the checkbox on. (Locked in at the `/speckit.specify` stage.)
- "The first voice message of the session" is defined within a particular `ChatSession`: until its reset/recreate. Opening a new result window = a new session.
- "The first voice message" means the very message obtained from voice transcription when the session was created (not a re-recording inside an already-open window).
- When the checkbox is off, the supplementary instruction is expressed at the system-message level and does not require any change to the API request format (no new fields on the LLM provider). The implementation is a text injection in the system prompt. This decision can be revisited in the implementation plan.
- Localization of the UI label (label + tooltip/helper text) reuses the app's existing localization mechanism; concrete strings are finalized at the `/speckit.plan` stage.
- Migrating the prompt-storage format follows the principle: missing field = the default value ("off"), without force-rewriting the file until the user edits the prompt.
- "Model limit" in the history-trimming requirement means the token budget that the system already computes for the chosen LLM model (see the existing `TokenEstimator`). The concrete drop rule (see FR-007): while the request does not fit, drop the oldest `user → assistant` pair in full; an orphaned `assistant` at the head is also dropped. The minimum payload that is always preserved is the system prompt + the new user message.
- An "edited message" is a message whose text the user changed via the existing edit UI in the result window (the code already has `onConfirmEdit`). No new edit UI is added in this feature.

## Out of Scope

- Changing STT/LLM models or their parameters (temperature, top_p, and similar).
- Extending the "Answer questions" setting into per-voice-message rules within a single session (the feature is intentionally limited to the first message).
- Any new UI button / indicator in the result window itself showing "the model is forbidden to answer." The UX indication is limited to the Settings toggle.
- New built-in prompts beyond simplifying the existing `simple-voice-to-text`.
- Visual redesign of the result window and Settings → System Prompts (changes are purely functional, one control is added).
