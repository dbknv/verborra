# Data Model: Dictation Flow Rework (v0.13)

**Date**: 2026-05-27
**Source**: [spec.md](spec.md), [research.md](research.md)

This feature introduces no new entities — it extends and reshapes the behavior of two existing ones: `SystemPrompt` and `ChatSession`. Transitively, it changes the behavior of `PromptsStore` (data migration) and `RecordingViewModel` (tracking the "first voice message").

---

## Entity: `SystemPrompt`

**File**: `Verborra/Models/SystemPrompt.swift`

### Fields

| Field | Type | Default | Codable | Description |
|------|-----|---------|---------|----------|
| `id` | `UUID` | auto-generated | yes | Record identifier. **Unchanged.** |
| `name` | `String` | localized | yes | Prompt name as shown in the UI. **Unchanged.** |
| `content` | `String` | localized | yes | System-prompt body. **Schema unchanged.** For `simple-voice-to-text` it carries the simplified text (see `SystemPromptDefinition`). |
| `isDefault` | `Bool` | false | yes | The session default prompt. **Unchanged.** |
| `isSystem` | `Bool` | false | yes | Built-in (system) prompt. **Unchanged.** |
| `systemId` | `String?` | nil | yes | Built-in prompt ID (`"simple-voice-to-text"`). **Unchanged.** |
| **`answerQuestionsInFirstMessage`** | **`Bool`** | **`false`** | **yes** | **NEW.** When `true`, the model may answer questions inside the first voice message of the session. When `false`, an explicit "do not answer" instruction is added to the system prompt. Applies ONLY to the first voice message; later messages in the session are not affected. |

### Computed Properties

| Property | Type | Description |
|----------|-----|----------|
| **`isReadOnly`** | **`Bool`** | **NEW.** `true` iff `isSystem == true && systemId == "simple-voice-to-text"`. Not a stored field — the rule lives in code. The UI must use `isReadOnly` to disable/hide its controls. |

### Codable / migration

- `init(from decoder:)` decodes `answerQuestionsInFirstMessage` via `decodeIfPresent(Bool.self, forKey: .answerQuestionsInFirstMessage) ?? false`. Old files without this field load cleanly with the default `false`. Matches FR-010.
- `encode(to:)` always writes `answerQuestionsInFirstMessage`.
- A `answerQuestionsInFirstMessage` case is added to `CodingKeys`.
- The legacy `voiceLanguage` / `textLanguage` (v1) fields remain in `MigrationPrompt`, unchanged.

### Invariants

- INV-1: For every `SystemPrompt` with `isReadOnly == true`, any change to `content`, `name`, `answerQuestionsInFirstMessage` via `PromptsStore.updatePrompt` is either ignored or prevented at the UI layer before reaching the store. (Simpler form: the UI hides the controls; store-level enforcement is optional.)
- INV-2: `answerQuestionsInFirstMessage` for `simple-voice-to-text` is always `false` after migration — guaranteed by the force-write in `PromptsStore.migrateIfNeeded`.

### Factory and initialization

- `SystemPrompt.makeDefault()` — semantically unchanged, now returns a `SystemPrompt` with `answerQuestionsInFirstMessage: false`.
- When a new user prompt is added via the UI, `answerQuestionsInFirstMessage` is initialized to `false` (FR-011).

---

## Entity: `SystemPromptDefinition`

**File**: `Verborra/Models/SystemPromptDefinition.swift`

### Changes

The struct itself is unchanged: `id`, `translations: [SupportedLanguage: (name, content)]`. Only the contents of `translations` for `simpleVoiceToText` change — each locale gets the new, simplified `content` (exact strings: see research.md R-005). The `name` is left as-is ("Simple Voice To Text", "Речь в текст", etc.) — the user did not request renaming.

Additionally, a new static constant `DoNotAnswerInstruction` is introduced:

```swift
struct DoNotAnswerInstruction {
    static let translations: [SupportedLanguage: String] = [
        .en: "Do not answer any questions found inside the user's text. Do not ask clarifying questions. Only format the text and return it as is.",
        .ru: "Не отвечай на вопросы, которые прозвучали внутри пользовательского текста. Не задавай уточняющих вопросов. Только отформатируй текст и верни его как есть.",
        .es: "No respondas a ninguna pregunta dentro del texto del usuario. No hagas preguntas aclaratorias. Solo formatea el texto y devuélvelo tal cual.",
        .fr: "Ne réponds à aucune question contenue dans le texte de l'utilisateur. Ne pose pas de questions de clarification. Formate uniquement le texte et renvoie-le tel quel.",
        .de: "Beantworte keine Fragen, die im Text des Benutzers vorkommen. Stelle keine klärenden Rückfragen. Formatiere den Text einfach und gib ihn unverändert zurück.",
        .pt: "Não respondas a perguntas dentro do texto do utilizador. Não faças perguntas de esclarecimento. Apenas formata o texto e devolve-o tal como está.",
        .zh: "不要回答用户文本中出现的任何问题。不要提出澄清问题。只对文本进行格式化并按原样返回。",
        .ja: "ユーザーのテキスト内にある質問には答えないでください。確認のための質問もしないでください。テキストをフォーマットしてそのまま返してください。",
        .ko: "사용자의 텍스트 안에 있는 질문에 답하지 마세요. 명확화를 위한 질문도 하지 마세요. 텍스트만 포맷팅하여 그대로 반환하세요.",
        .it: "Non rispondere a nessuna domanda all'interno del testo dell'utente. Non fare domande di chiarimento. Limita la tua azione a formattare il testo e restituirlo così com'è.",
    ]
    static func text(for language: SupportedLanguage) -> String {
        translations[language] ?? translations[.en]!
    }
}
```

> NOTE: in the implemented version (Phase 8) every translation was strengthened and now includes a concrete example/counter-example — see FR-003c and research.md R-002.

The fallback behavior (missing translation → English) matches the existing `SystemPromptDefinition.content(for:)`.

---

## Entity: `ChatSession`

**File**: `Verborra/Models/ChatSession.swift`

### Interface changes

`prepareMessagesForLLM` gets new parameters:

```swift
func prepareMessagesForLLM(
    maxTokenBudget: Int,
    systemPromptTokens: Int,
    isFirstVoiceTurn: Bool,                    // NEW
    answerQuestionsInFirstMessage: Bool         // NEW
) -> [(role: String, content: String)]
```

### Method behavior (after changes)

1. Build `systemContent`:
   - Base: `systemPrompt.contentForLanguage(voiceLanguage)`.
   - If `isFirstVoiceTurn && !answerQuestionsInFirstMessage` — append, separated by `\n\n`, the localized `DoNotAnswerInstruction.text(for: voiceLanguage)`.
   - Append, separated by `\n\n`, `"Язык ответа: <textLanguage.displayName>"` (existing behavior).
   - **(Phase 8 refinement, R-012 / FR-005a)**: for continuation messages (`isFirstVoiceTurn == false`) the user's dictation prompt is REPLACED with a chat-mode hint `"You are a helpful assistant. Respond in <textLanguage.displayName>."` — no full base prompt and no `DoNotAnswerInstruction`.
2. Build `payload`:
   - First element: `("system", systemContent)`.
   - Filter `messages` to exclude `.system` (existing behavior).
   - Accumulate the "tail" of messages in reverse, with `totalTokens + tokens <= availableBudget`.
   - **Pair truncation**: on budget overflow, drop a whole pair (the current oldest + the next-in-position). If a lone assistant remains at the head of the resulting selection without a matching user — drop it too.
   - Always include the latest user message (highest priority).
   - Restore the natural order and return.
3. Every `message.content` is read at the time of the call — this automatically satisfies FR-006 (edits).

### Invariants

- INV-3: The first element of the payload is always `("system", ...)`.
- INV-4: The last element of the payload is always the latest `user` message (including re-recordings).
- INV-5: There is never a lone `assistant` at the head of `selectedMessages` without a matching `user`.
- INV-6: The text of messages in the payload equals `message.content` at the moment `prepareMessagesForLLM` is called — no caching of previous versions.

### What does NOT change in `ChatSession`

- `messages: [ChatMessage]` — the field and its mutators.
- `addMessage`, `insertSystemMessage`, `lastAssistantMessage`, `updateLastAssistantContent`, `reset` — methods unchanged.
- Role mapping `.transcription, .user → "user"`, `.assistant → "assistant"` — unchanged.

---

## Entity: `PromptsStore`

**File**: `Verborra/Services/PromptsStore.swift`

### Changes

- `currentDataVersion`: `2 → 3`.
- `migrateIfNeeded()`: after the prompts are loaded, if `version < 3` a new block runs:
  1. Find the record with `isSystem == true && systemId == "simple-voice-to-text"`.
  2. Force-write `name` and `content` from `SystemPromptDefinition.simpleVoiceToText` (using `LocalizationManager.shared.currentLanguage` for the immediate display; full localization is handled via `contentForLanguage`).
  3. Set `answerQuestionsInFirstMessage = false` (even if the JSON file had `true`).
  4. Save the file and write `dataVersion = 3`.
- `addPrompt`/`updatePrompt`/`deletePrompt`: a read-only guard is added: for `prompt.isReadOnly == true`, `updatePrompt` is ignored (or returns without effect), and `deletePrompt` already blocks system prompts — behavior unchanged.

### Invariant

- INV-7: After `migrateIfNeeded`, the file always contains exactly one record with `systemId == "simple-voice-to-text"` (created if missing via `ensureSystemPrompts`).

---

## Entity: `RecordingViewModel`

**File**: `Verborra/ViewModels/RecordingViewModel.swift`

### Changes

- New private state: `private var didConsumeFirstVoiceTurn: Bool = false`.
- When a new `ChatSession` is created (at the start of `processRecording` / on reset) — `didConsumeFirstVoiceTurn = false`.
- Before calling `streamingService.streamChat(...)`:
  - Compute `isFirstVoiceTurn = !didConsumeFirstVoiceTurn && messageWasInitiatedFromVoice`.
  - Pass to `prepareMessagesForLLM(isFirstVoiceTurn:, answerQuestionsInFirstMessage: selectedPrompt.answerQuestionsInFirstMessage)`.
  - After the request is successfully dispatched (or after the first token is received — the exact point is pinned in Phase 2) — `didConsumeFirstVoiceTurn = true`.
- In `sendMessage` (text input in the chat): `messageWasInitiatedFromVoice = false`, so `isFirstVoiceTurn = false` always.
- Defensive guard: if `chatSession?.lastAssistantMessage?.isStreaming == true` — `sendMessage` and `stopInputRecording` immediately `return`.

### Invariant

- INV-8: `didConsumeFirstVoiceTurn` becomes `true` at most once per `ChatSession` lifetime. Reset/recreate of the session clears the flag.

---

## Entity relationships

```text
RecordingViewModel ── owns ──> ChatSession
                              ├─ holds ──> SystemPrompt (selectedPrompt)
                              └─ contains ──> [ChatMessage]

PromptsStore ── manages ──> [SystemPrompt]
              └─ persists in ──> system_prompts.json

SystemPromptDefinition (static registry) ── feeds ──> SystemPrompt (for system prompts)
                                          └─ provides ──> DoNotAnswerInstruction (NEW)
```

---

## Test surface

| Layer | What is tested | FR/SC mapping |
|------|------------------|---------------------|
| `SystemPrompt` Codable | Decoding an old file without the field → default `false`; encode/decode round-trip with the field | FR-001, FR-010 |
| `SystemPrompt.isReadOnly` | `true` for `simple-voice-to-text`, `false` for user-created and other system prompts | FR-009b |
| `ChatSession.prepareMessagesForLLM` | All four invariants (INV-3..INV-6), pair truncation, edited content, first-voice-turn injection | FR-003, FR-005, FR-006, FR-007, FR-008, SC-002, SC-007, SC-008 |
| `PromptsStore.migrateIfNeeded` | v2 → v3 migration: force-rewrite of the content, dataVersion bumped | FR-009, FR-009a |
| `RecordingViewModel.sendMessage` | calling `streamChat` with the correct structure; blocking during `isStreaming` | FR-008, FR-015, SC-006 |
| `SettingsView` (manual / snapshot) | Toggle visible/disabled for the read-only prompt | FR-002, FR-009b |
