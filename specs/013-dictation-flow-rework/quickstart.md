# Quickstart: validating feature 013 locally

**Date**: 2026-05-27
**Goal**: in ~10 minutes, confirm that the feature's 5 key scenarios work on a locally built version.

This document is a guide **for the tester / developer**, not the end user. It describes hands-on validation complementing the formal `/speckit.verify`.

---

## Setup

1. Build the feature branch:
   ```bash
   git checkout 013-dictation-flow-rework
   xcodebuild -project Verborra.xcodeproj -scheme Verborra -configuration Debug build
   ```
2. Launch the app from Xcode (Cmd+R) or via `open builds/Verborra.app`.
3. In Settings → API, confirm the OpenAI key is stored in the Keychain.
4. In Settings → System Prompts, confirm the built-in `Simple Voice To Text` / `Речь в текст` (depending on UI language) is present.
5. Make sure the user has the `Simple Voice To Text` default prompt selected.

---

## Scenario 1 (US1): dictation without answering questions

**Steps**:

1. Open Settings → System Prompts.
2. Select the default `Simple Voice To Text`. **Expected**: the "Answer questions in the first message?" checkbox is shown **disabled** and **unchecked**. The name/content fields for this prompt are also disabled.
3. Close Settings.
4. Trigger recording via the global hotkey.
5. Say: "Hey what do you think will we make it by Friday?"
6. Stop the recording.

**Expected**:

- The result window shows a formatted transcription like: "Hey, what do you think — will we make it by Friday?"
- **NO** model answer follows the transcription.
- **NO** clarifying back-and-forth.

**If it fails**: verify that the checkbox is actually `false` for the selected prompt; check the diagnostic log (`Console.app`, filter subsystem `Verborra`, INFO level — there should be a `prepareMessagesForLLM done | injectedDoNotAnswer=true` record).

---

## Scenario 2 (US2): dictation with an answer and continued dialogue

**Steps**:

1. Open Settings → System Prompts → create a new user prompt "Q&A" with content `"Answer the user's question in full."` Set its "Answer questions in the first message?" checkbox to **on**.
2. Make "Q&A" the default.
3. Close Settings.
4. Trigger recording, say: "Explain how SwiftUI Observable works."
5. Receive the model's answer in the result window.
6. In the text input at the bottom of the result window, type: "Can you go deeper on the second point?"
7. Press Send.

**Expected**:

- After step 5 the model provides a substantive answer.
- After step 7 the model answers with context (it mentions the "second point" from its previous reply). This confirms the full session history is being sent.

**If it fails**: check Console.app DEBUG log `prepareMessagesForLLM` — `messageCount` should be ≥3 (system + user₁ + assistant₁ + user₂). If it's only 2 — the streaming/non-streaming unification didn't take (see plan.md R-006).

---

## Scenario 3 (US3 — bug fix): full chat history

**Steps**:

1. In the result window (any session with the checkbox on or with a user prompt where the model does answer): dictate "Remember the number 42."
2. Receive the response.
3. In the text input: "What number did I ask you to remember?"
4. Send.

**Expected**: the model answers "42."

**Regression check against `main`**: on the `main` branch (without the feature) the model in step 4 responds "I don't know" / asks for clarification, confirming the bug exists there.

---

## Scenario 4 (US3 — edited messages): message editing

**Steps**:

1. In a result window with an active dialogue (as in Scenario 3): after step 2 click "Edit" (or trigger the existing edit UI) on the first user message.
2. Change "42" to "99" and confirm the edit.
3. In the text input: "What number did I ask you to remember?"
4. Send.

**Expected**: the model answers "99" (not 42).

**If it fails**: that means `prepareMessagesForLLM` is reading a stale message text. Check the Console.app DEBUG log for `prepareMessagesForLLM` — the edited content must be visible there (under `privacy: .private`, so as a developer use `log stream --info`).

---

## Scenario 5 (US3 — pair truncation): budget overflow

**Steps**:

1. In the result window, drive an artificially long dialogue (e.g. 20+ exchanges with long answers) so the total exceeds the chosen model's token budget (`gpt-4.1-nano` has a relatively small budget — convenient).
2. Send another message.

**Expected**:

- The request does not fail with a context-overflow error.
- The Console.app INFO log `prepareMessagesForLLM done | droppedPairs=N` shows N>0 pairs were dropped.
- The DEBUG log confirms the earliest messages are the ones dropped (by timestamp/index).
- The system prompt and the latest user message are present in the payload.

---

## Scenario 6 (FR-015): blocking during streaming

**Steps**:

1. In the result window send a long message (or ask for "write a very long text").
2. While the assistant's reply is still streaming, try:
   - Typing in the input and pressing Send;
   - Pressing the re-record voice button.

**Expected**: both buttons are in their disabled state. No parallel requests are issued.

---

## Scenario 7 (FR-009/FR-009a/FR-009b): migration and read-only

**Steps**:

1. First install the **old** version of the app (from `main`). Open Settings → System Prompts → edit `Simple Voice To Text`, replacing the content with anything (e.g. "test-content").
2. Save and quit the app.
3. Install the **new** version (branch 013). Launch the app.
4. Open Settings → System Prompts → select `Simple Voice To Text`.

**Expected**:

- The prompt content is **reset** to the new simplified phrasing "Fix spelling errors and add punctuation. Return only the corrected text." (or its equivalent in the current UI locale). The user edit "test-content" is **wiped**.
- The name/content/Toggle fields are shown disabled (read-only).
- The Delete button for this prompt is hidden or disabled.

The Console.app log should contain `Migrated simple-voice-to-text content | language=ru | previousContentHash=...`.

---

## Aggregate test check

```bash
xcodebuild test -project Verborra.xcodeproj -scheme Verborra \
  -only-testing:VerborraTests/ChatSessionTests \
  -only-testing:VerborraTests/SystemPromptTests \
  -only-testing:VerborraTests/PromptsStoreTests
```

**Expected**: all tests green. The `xcodebuild` report contains no failed cases prefixed `test_FR_*` or `test_SC_*`.

---

## Rollback (if needed)

1. `git checkout main`.
2. Delete `~/Library/Application Support/Verborra/system_prompts.json` (keep a backup nearby) — or just leave it: the old version will read it and save it back with `dataVersion = 2`. The `simple-voice-to-text` content will be shown as the (already migrated) plain text.

---

## Where to look for logs

- **Console.app**: filter by subsystem `verborra` or process `Verborra`. INFO level for the main events; for DEBUG-level payloads switch the level in Verborra → Settings → Advanced → Logging Level.
- **Files**: `~/Library/Application Support/Verborra/Logs/*.jsonl` (hourly rotation, 24-hour retention).
