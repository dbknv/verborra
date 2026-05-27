# Data Model: Переработка flow диктовки (v0.13)

**Дата**: 2026-05-27
**Источник**: [spec.md](spec.md), [research.md](research.md)

В этой фиче не вводятся новые сущности — расширяется и переформулируется работа двух существующих: `SystemPrompt` и `ChatSession`. Транзитивно изменяется поведение `PromptsStore` (миграция данных) и `RecordingViewModel` (контроль «первого голосового сообщения»).

---

## Сущность: `SystemPrompt`

**Файл**: `Verborra/Models/SystemPrompt.swift`

### Поля

| Поле | Тип | Default | Codable | Описание |
|------|-----|---------|---------|----------|
| `id` | `UUID` | автогенерируется | yes | Идентификатор записи. **Без изменений.** |
| `name` | `String` | localized | yes | Имя промпта, видимое в UI. **Без изменений.** |
| `content` | `String` | localized | yes | Тело системного промпта. **Без изменений в схеме.** Для `simple-voice-to-text` — упрощённое содержимое (см. SystemPromptDefinition). |
| `isDefault` | `Bool` | false | yes | Это дефолтный промпт сессии. **Без изменений.** |
| `isSystem` | `Bool` | false | yes | Системный (встроенный) промпт. **Без изменений.** |
| `systemId` | `String?` | nil | yes | ID встроенного промпта (`"simple-voice-to-text"`). **Без изменений.** |
| **`answerQuestionsInFirstMessage`** | **`Bool`** | **`false`** | **yes** | **НОВОЕ.** Когда `true` — модель может отвечать на вопросы, прозвучавшие внутри первого голосового сообщения сессии. Когда `false` — к системному промпту добавляется инструкция «не отвечать». Применяется ТОЛЬКО к первому голосовому сообщению; на остальные сообщения сессии не влияет. |

### Computed properties

| Свойство | Тип | Описание |
|----------|-----|----------|
| **`isReadOnly`** | **`Bool`** | **НОВОЕ.** `true`, если `isSystem == true && systemId == "simple-voice-to-text"`. Хранимым полем не является — правило вычисляется в коде. UI обязан использовать `isReadOnly` для disable/hide controls. |

### Codable / миграция

- `init(from decoder:)` декодирует `answerQuestionsInFirstMessage` через `decodeIfPresent(Bool.self, forKey: .answerQuestionsInFirstMessage) ?? false`. Старые файлы без этого поля корректно загружаются с дефолтом `false`. Соответствие FR-010.
- `encode(to:)` всегда пишет `answerQuestionsInFirstMessage`.
- В `CodingKeys` добавляется case `answerQuestionsInFirstMessage`.
- Поле `voiceLanguage` / `textLanguage` (v1 legacy) остаётся в `MigrationPrompt`, как сейчас — без изменений.

### Инварианты

- INV-1: Для всех `SystemPrompt`, у которых `isReadOnly == true`, любое изменение `content`, `name`, `answerQuestionsInFirstMessage` через `PromptsStore.updatePrompt` либо игнорируется, либо запрещается на UI-уровне до вызова store. (Проще: UI скрывает controls; store-уровневая защита факультативна.)
- INV-2: Поле `answerQuestionsInFirstMessage` для `simple-voice-to-text` всегда `false` после миграции — обеспечивается принудительной записью в `PromptsStore.migrateIfNeeded`.

### Фабрика и инициализация

- `SystemPrompt.makeDefault()` — без изменений по смыслу, но теперь возвращает SystemPrompt с `answerQuestionsInFirstMessage: false`.
- При добавлении нового пользовательского промпта через UI значение `answerQuestionsInFirstMessage` инициализируется как `false` (FR-011).

---

## Сущность: `SystemPromptDefinition`

**Файл**: `Verborra/Models/SystemPromptDefinition.swift`

### Изменения

Структура остаётся та же: `id`, `translations: [SupportedLanguage: (name, content)]`. Меняется только содержимое `translations` для `simpleVoiceToText` — каждая локаль получает новый, упрощённый `content` (точные строки — см. research.md R-005). Имя (`name`) остаётся прежним («Simple Voice To Text», «Речь в текст», и т. д.) — пользователь не требовал переименовывать.

Дополнительно вводится новая статическая константа `doNotAnswerInstructions`:

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

Поведение fallback (отсутствует перевод → English) совпадает с существующим `SystemPromptDefinition.content(for:)`.

---

## Сущность: `ChatSession`

**Файл**: `Verborra/Models/ChatSession.swift`

### Изменения интерфейса

Метод `prepareMessagesForLLM` получает новый параметр:

```swift
func prepareMessagesForLLM(
    maxTokenBudget: Int,
    systemPromptTokens: Int,
    isFirstVoiceTurn: Bool,                    // НОВОЕ
    answerQuestionsInFirstMessage: Bool         // НОВОЕ
) -> [(role: String, content: String)]
```

### Логика метода (после изменений)

1. Сформировать `systemContent`:
   - База: `systemPrompt.contentForLanguage(voiceLanguage)`.
   - Если `isFirstVoiceTurn && !answerQuestionsInFirstMessage` — добавить через `\n\n` локализованную инструкцию `DoNotAnswerInstruction.text(for: voiceLanguage)`.
   - Добавить через `\n\n` `"Язык ответа: <textLanguage.displayName>"` (как сейчас).
2. Сформировать `payload`:
   - Первым элементом — `("system", systemContent)`.
   - Из `messages` отфильтровать `.system` (как сейчас).
   - Накопить «хвост» сообщений в обратном порядке с проверкой `totalTokens + tokens <= availableBudget`.
   - Усечение **парами**: при превышении бюджета — отбросить пару (текущее старое + следующее по позиции). Если в начале результирующего набора остался одиночный assistant без своего user — также отрезать.
   - Включить последнее user-сообщение всегда (приоритетно).
   - Восстановить прямой порядок и вернуть.
3. Все `message.content` берутся **по текущему значению** — это автоматически обеспечивает FR-006 (правки).

### Инварианты

- INV-3: Первый элемент payload — всегда `("system", ...)`.
- INV-4: Последний элемент payload — всегда последнее `user`-сообщение (включая повторные голосовые записи).
- INV-5: В `selectedMessages` не существует одиночного assistant в начале без соответствующего user.
- INV-6: Текст сообщений в payload равен `message.content` на момент вызова `prepareMessagesForLLM` — никакого кэширования предыдущих версий.

### Что НЕ меняется в `ChatSession`

- `messages: [ChatMessage]` — поле и его управление.
- `addMessage`, `insertSystemMessage`, `lastAssistantMessage`, `updateLastAssistantContent`, `reset` — методы без изменений.
- Маппинг ролей `.transcription, .user → "user"`, `.assistant → "assistant"` — без изменений.

---

## Сущность: `PromptsStore`

**Файл**: `Verborra/Services/PromptsStore.swift`

### Изменения

- `currentDataVersion`: `2 → 3`.
- `migrateIfNeeded()`: после загрузки промптов, если `version < 3`, выполняется новый блок:
  1. Найти запись с `isSystem == true && systemId == "simple-voice-to-text"`.
  2. Для каждой поддерживаемой локали `SystemPromptDefinition.simpleVoiceToText.translations.keys` принудительно перезаписать `name` и `content` теми, что лежат в `SystemPromptDefinition.simpleVoiceToText` (берётся `LocalizationManager.shared.currentLanguage` для актуального отображения; полная локализация осуществляется через `contentForLanguage`).
  3. Установить `answerQuestionsInFirstMessage = false` (даже если в JSON-файле было `true`).
  4. Сохранить файл и записать `dataVersion = 3`.
- `addPrompt`/`updatePrompt`/`deletePrompt`: добавляется guard на read-only: для `prompt.isReadOnly == true` — `updatePrompt` игнорируется (или возвращается без эффекта), `deletePrompt` уже блокирует системные промпты — поведение не меняется.

### Инвариант

- INV-7: После `migrateIfNeeded` файл всегда содержит ровно одну запись с `systemId == "simple-voice-to-text"` (создаётся, если её не было — через `ensureSystemPrompts`).

---

## Сущность: `RecordingViewModel`

**Файл**: `Verborra/ViewModels/RecordingViewModel.swift`

### Изменения

- Новое приватное состояние: `private var didConsumeFirstVoiceTurn: Bool = false`.
- При создании новой `ChatSession` (в начале `processRecording` / при reset) — `didConsumeFirstVoiceTurn = false`.
- Перед вызовом `streamingService.streamChat(...)`:
  - Вычислить `isFirstVoiceTurn = !didConsumeFirstVoiceTurn && messageWasInitiatedFromVoice`.
  - Передать в `prepareMessagesForLLM(isFirstVoiceTurn:, answerQuestionsInFirstMessage: selectedPrompt.answerQuestionsInFirstMessage)`.
  - После успешной постановки запроса (или после первого полученного токена — точная точка фиксируется в Phase 2) — `didConsumeFirstVoiceTurn = true`.
- В `sendMessage` (текстовый ввод в чате): `messageWasInitiatedFromVoice = false`, поэтому `isFirstVoiceTurn = false` всегда.
- Defensive guard: если `chatSession?.lastAssistantMessage?.isStreaming == true` — `sendMessage` и `stopInputRecording` сразу `return`.

### Инвариант

- INV-8: `didConsumeFirstVoiceTurn` становится `true` максимум один раз за время жизни одной `ChatSession`. Reset/recreate сессии сбрасывает флаг.

---

## Отношения между сущностями

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

## Тестовая поверхность

| Слой | Что тестируется | Соответствие FR/SC |
|------|------------------|---------------------|
| `SystemPrompt` Codable | Декодирование старого файла без поля → дефолт `false`; encode/decode round-trip с полем | FR-001, FR-010 |
| `SystemPrompt.isReadOnly` | `true` для `simple-voice-to-text`, `false` для пользовательских и других системных | FR-009b |
| `ChatSession.prepareMessagesForLLM` | Все 4 инварианта (INV-3..INV-6), pair-truncation, edited content, first-voice-turn injection | FR-003, FR-005, FR-006, FR-007, FR-008, SC-002, SC-007, SC-008 |
| `PromptsStore.migrateIfNeeded` | v2 → v3 миграция: force-rewrite контента, dataVersion обновляется | FR-009, FR-009a |
| `RecordingViewModel.sendMessage` | вызов `streamChat` с корректной структурой; блокировка во время `isStreaming` | FR-008, FR-015, SC-006 |
| `SettingsView` (manual / snapshot) | Toggle visible/disabled для read-only промпта | FR-002, FR-009b |
