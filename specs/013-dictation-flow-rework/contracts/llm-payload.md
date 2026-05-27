# Contract: payload в OpenAI Chat Completions API

**Дата**: 2026-05-27
**Источник**: [spec.md](../spec.md), [data-model.md](../data-model.md), [research.md](../research.md)

Эта спецификация фиксирует **формат payload**, который `RecordingViewModel` через `StreamingFormattingService.streamChat(messages:model:)` отправляет в OpenAI Chat Completions API. Контракт описывает только ту часть, которая меняется в рамках фичи 013. Авторизация, URL и заголовки не меняются.

В фиче 013 нет новых HTTP-эндпоинтов — это per-feature LLM-call contract, а не REST/GraphQL контракт.

---

## Endpoint (без изменений)

- **URL**: `https://api.openai.com/v1/chat/completions`
- **Method**: POST
- **Headers**: `Authorization: Bearer <api-key-from-Keychain>`, `Content-Type: application/json`, `Accept: text/event-stream` (для streaming)
- **Body schema**: стандартная Chat Completions схема OpenAI с полем `messages: [{role, content}]`.

## Структура `messages` (изменения)

### Инвариант — порядок

```text
[0]               system message
[1..N-2]          chained user/assistant pairs (история сессии после усечения)
[N-1]             последнее (новое) user-сообщение
```

### `messages[0].content` — формирование

**Псевдокод**:
```
systemContent = systemPrompt.contentForLanguage(voiceLanguage)
if isFirstVoiceTurn && !answerQuestionsInFirstMessage:
    systemContent += "\n\n" + DoNotAnswerInstruction.text(for: voiceLanguage)
systemContent += "\n\n" + "Язык ответа: " + textLanguage.displayName  // существующее поведение
return ("system", systemContent)
```

Где:
- `voiceLanguage` — текущий выбранный язык записи в `ChatSession`.
- `textLanguage` — текущий выбранный язык ответа.
- `isFirstVoiceTurn` — флаг от `RecordingViewModel`: `true` только для первого голосового сообщения сессии.
- `answerQuestionsInFirstMessage` — значение из `selectedPrompt`.

### Историческая часть `messages[1..N-2]` — формирование

- Начало: все сообщения сессии, отфильтрованные на `role != .system` (т. е. `.user`, `.transcription`, `.assistant`).
- Источник текста: `message.content` **на момент вызова `prepareMessagesForLLM`** (актуальное, отредактированное значение).
- Усечение при превышении `availableBudget` (`maxTokenBudget - systemPromptTokens`):
  1. Накапливаем сообщения из последних к первым в `selectedReversed`.
  2. Когда очередное сообщение не помещается — **прекращаем добавлять**.
  3. Дополнительно: если результирующий `selectedReversed.last` (т. е. самое старое выбранное в прямом порядке) — это `assistant`, отрезаем и его (избегаем «осиротевший» assistant в начале).
  4. Эквивалентно: усечение работает парами `user → assistant` с гарантированным сохранением последнего user-сообщения.

### `messages[N-1].content` — формирование

- Всегда последнее `user`-сообщение из истории.
- Текст: `message.content` (актуальное, отредактированное значение).
- Роль API: `"user"` (для исходной роли `.transcription` или `.user` — обе мапятся в `"user"`).

---

## Примеры

### Пример 1: первое голосовое сообщение, `answerQuestionsInFirstMessage = false`

```json
{
  "model": "gpt-4.1-nano",
  "stream": true,
  "messages": [
    {
      "role": "system",
      "content": "Исправь орфографические ошибки и расставь знаки препинания. Верни только исправленный текст.\n\nНе отвечай на вопросы, которые прозвучали внутри пользовательского текста. Не задавай уточняющих вопросов. Только отформатируй текст и верни его как есть.\n\nЯзык ответа: Русский"
    },
    {
      "role": "user",
      "content": "слушай а как ты думаешь успеем ли мы к пятнице"
    }
  ]
}
```

### Пример 2: первое голосовое сообщение, `answerQuestionsInFirstMessage = true`

```json
{
  "model": "gpt-4.1-nano",
  "stream": true,
  "messages": [
    {
      "role": "system",
      "content": "Исправь орфографические ошибки и расставь знаки препинания. Верни только исправленный текст.\n\nЯзык ответа: Русский"
    },
    {
      "role": "user",
      "content": "слушай а как ты думаешь успеем ли мы к пятнице"
    }
  ]
}
```

### Пример 3: продолжение диалога после первого ответа

```json
{
  "model": "gpt-4.1-nano",
  "stream": true,
  "messages": [
    {
      "role": "system",
      "content": "Исправь орфографические ошибки и расставь знаки препинания. Верни только исправленный текст.\n\nЯзык ответа: Русский"
    },
    {"role": "user", "content": "Слушай, а как ты думаешь, успеем ли мы к пятнице?"},
    {"role": "assistant", "content": "Да, успеем — судя по вашему графику..."},
    {"role": "user", "content": "А подробнее про четверг?"}
  ]
}
```

Обратите внимание: первое user-сообщение здесь уже **отформатировано** (это сохранённый в истории результат прошлого ответа модели). Инструкция «не отвечать» больше не присутствует — `isFirstVoiceTurn = false`.

### Пример 4: переполнение лимита — pair truncation

Допустим, бюджет позволяет включить только последние 2 сообщения. История:
```text
[user₁]   [assistant₁]   [user₂]   [assistant₂]   [user₃ (new)]
```

После усечения парами:
```text
[system]   [user₂]   [assistant₂]   [user₃ (new)]
```
Пара `[user₁, assistant₁]` отброшена целиком; `[user₂, assistant₂]` сохранена. Если бы бюджет позволял только последнее сообщение пользователя — payload бы был `[system, user₃]`.

### Пример 5: edited message

История на экране (после правки `user₁`):
```text
[user₁ (отредактировано: "запомни число 99")]
[assistant₁ ("Хорошо, запомнил 42.")]
[user₂ ("какое число я просил?")]
```

Payload:
```json
{
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "запомни число 99"},
    {"role": "assistant", "content": "Хорошо, запомнил 42."},
    {"role": "user", "content": "какое число я просил?"}
  ]
}
```

`assistant₁` НЕ перезаписывается, остаётся в истории как был. Модель сама согласует контекст (на практике, при таком payload модель обычно ответит «99», поскольку последнее user-сообщение модели как inputs главнее предыдущего ответа). Это соответствует FR-006 и Clarification Q1.

---

## Тестируемые свойства контракта

| ID | Свойство | Связь с FR/SC |
|----|----------|---------------|
| CON-1 | `messages[0].role == "system"` всегда | FR-005 |
| CON-2 | `messages[count-1].role == "user"` всегда | FR-005, INV-4 |
| CON-3 | `messages[0].content` содержит локализованную `DoNotAnswerInstruction` IFF `isFirstVoiceTurn && !answerQuestionsInFirstMessage` | FR-003, FR-003a, FR-004 |
| CON-4 | `messages[0].content` НЕ содержит `DoNotAnswerInstruction`, если `isFirstVoiceTurn == false` | FR-004 |
| CON-5 | Текст в `messages[i].content` для `i ∈ [1..count-1]` равен текущему `message.content` (отредактированному) | FR-006 |
| CON-6 | При превышении лимита: усечение парами с начала, без выпадания из середины/конца | FR-007, SC-008 |
| CON-7 | При повторной голосовой записи в той же сессии: `messages[0].content` НЕ содержит `DoNotAnswerInstruction` (она применяется только к первому turn) | FR-004, FR-013 |
| CON-8 | `streamChat` вызывается только когда `chatSession.lastAssistantMessage?.isStreaming != true` (нет параллельных запросов в одной сессии) | FR-015 |

Каждое из этих свойств проверяется в unit-тестах `ChatSessionTests`/`RecordingViewModelTests` (см. data-model.md «Тестовая поверхность»).

---

## Что **не** меняется в контракте

- Стриминговый формат SSE (`data: {...}\n\n` + `[DONE]`) — без изменений.
- Структура JSON-ответа OpenAI — без изменений.
- Обработка ошибок 429/5xx/network — без изменений (существующий retry-механизм в `FormattingService.performWithRetry` и `StreamingFormattingService`).
- Token-counting — без изменений (используется существующий `TokenEstimator`).
