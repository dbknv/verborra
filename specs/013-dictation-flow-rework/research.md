# Phase 0 Research: Переработка flow диктовки (v0.13)

**Дата**: 2026-05-27
**Источник**: [spec.md](spec.md), `## Clarifications` (5 вопросов разрешены)

Все [NEEDS CLARIFICATION] из спецификации уже зафиксированы на этапе `/speckit.clarify`. В этом документе фиксируются прикладные технические решения, выбранные на основе изучения исходников приложения.

---

## R-001: Где хранить `answerQuestionsInFirstMessage`

- **Decision**: Расширить существующую структуру `SystemPrompt` (в `Verborra/Models/SystemPrompt.swift`) булевым полем `answerQuestionsInFirstMessage` со значением по умолчанию `false`. Поле сериализуется через `Codable` в том же JSON-файле `~/Library/Application Support/Verborra/system_prompts.json`, который уже использует `PromptsStore`.
- **Rationale**: 
  - Промпт — единственное место в системе, где сохраняется per-prompt поведенческая настройка. Хранить отдельно (UserDefaults, новый JSON) — нарушит инвариант «вся конфигурация промпта — в одном объекте», который уже выдержан в проекте.
  - Существующий `PromptsStore` поддерживает миграцию (`currentDataVersion`), что позволяет без потерь обновить схему.
  - Дефолт `false` зафиксирован в Q-Clarification: «выключено для всех промптов».
- **Alternatives considered**:
  - Хранить в UserDefaults (одна общая настройка) — отверг: ломает per-prompt семантику; пользователь не сможет настроить разные промпты по-разному.
  - Хранить в отдельной таблице/файле — отверг: лишняя сущность, нарушает Principle 3 (минимализм).
  - Зашить в системные промпты как часть `content` — отверг: тогда настройка не управляема пользователем для пользовательских промптов.

---

## R-002: Как сигнализировать LLM «не отвечать на вопросы»

- **Decision**: Текстовая инжекция дополнительной инструкции в system message. При формировании запроса в `ChatSession.prepareMessagesForLLM` к содержимому системного промпта добавляется блок (отделённый `\n\n`) с локализованной инструкцией «не отвечать на вопросы, не уточнять, только вернуть отформатированный текст». Условие применения — `isFirstVoiceTurn == true && answerQuestionsInFirstMessage == false`. Текст инструкции локализуется по `voiceLanguage` (5-й clarification).
- **Rationale**:
  - OpenAI Chat Completions API не имеет специального структурированного флага «не отвечать». Единственный механизм — текстовые инструкции в system role.
  - Не требует изменения URL/headers/payload-формата. Изменение касается только содержимого `system`-сообщения.
  - Локализация согласуется с уже существующим механизмом `contentForLanguage(voiceLanguage)`, и не создаёт смешения языков в одном system message.
- **Alternatives considered**:
  - Инжектировать инструкцию в user-сообщение перед текстом транскрипции — отверг: загрязняет user-content; в логах сложнее отслеживать.
  - Использовать `function_calling` или `response_format=json_schema` — отверг: слишком тяжёлая артиллерия для простого ограничения поведения; добавляет risk-of-format-mismatch.
  - Делать второй проход «отбрасывания ответа» через локальный пост-фильтр — отверг: ненадёжно, нельзя гарантировать корректность парсинга «вопрос/ответ» из текста.

---

## R-003: Где определяется «первое голосовое сообщение сессии»

- **Decision**: В `RecordingViewModel` ввести приватный флаг `private var didConsumeFirstVoiceTurn: Bool = false`. Флаг сбрасывается в `false` в момент создания новой `ChatSession` (методы `startRecording`/`reset`) и устанавливается в `true` сразу после успешной отправки первого голосового запроса в LLM. `ChatSession.prepareMessagesForLLM` получает новый параметр `isFirstVoiceTurn: Bool`, который ViewModel вычисляет как `!didConsumeFirstVoiceTurn && isVoiceInitiated`.
- **Rationale**:
  - Семантика «первое голосовое» относится к жизненному циклу сессии, а это ответственность ViewModel.
  - Не хранится в самой `ChatSession`, потому что `ChatSession` не знает, как сообщение появилось (через voice или через text input в чате).
  - Сброс на reset/recreate — естественно следует из реинициализации ViewModel и пересоздания `ChatSession`.
- **Alternatives considered**:
  - Хранить флаг в `ChatSession` — отверг: смешивает источник сообщения (voice/text) с содержимым.
  - Определять по типу первого сообщения в `messages` (`role == .transcription`) — отверг: транскрипционные сообщения отсутствуют как отдельная роль для второй и более голосовой записи, и в коде роль `.transcription` уже маппится в `user` для API-запроса; этот сигнал ненадёжен.

---

## R-004: Усечение истории парами `user/assistant`

- **Decision**: Перерабатывается алгоритм в `ChatSession.prepareMessagesForLLM`:
  1. Системный промпт всегда первый, всегда сохраняется.
  2. Последнее `user`-сообщение всегда сохраняется.
  3. Перебирая `messages` с конца, накапливаем сообщения в буфер `selected` (в обратном порядке) до тех пор, пока `totalTokens + nextMessage.tokens <= availableBudget`.
  4. Если очередное сообщение не помещается — отбрасываем сразу пару: текущее старое + соседнее (обычно `assistant`, парный к user в более поздней позиции). Реализация: при отбрасывании смотрим, не остался ли в `selected` сразу за выбрасываемой границей «осиротевший» assistant без своего user — если да, тоже его исключаем.
  5. Финальный payload собирается в прямом порядке: `[system, ...selected, lastUserMessage]`.
- **Rationale**:
  - Сохраняет conversational coherence (assistant-ответ всегда имеет свой user-вопрос рядом).
  - Сохраняет SC-008-проверку: «отбрасываются самые старые».
- **Alternatives considered**:
  - Удалять по одному с начала — отверг: clarification Q3 = пары.
  - Удалять по семантическим «турам» с сохранением последней пары — отверг: добавляет сложность без явной пользы; пользователь не отличит результат.

---

## R-005: `simple-voice-to-text` — содержимое и read-only

- **Decision**:
  - Все 10 локалей в `SystemPromptDefinition.simpleVoiceToText` переписываются на короткую формулировку. Проектные строки (одна на каждый язык):
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
  - Чекбокс `answerQuestionsInFirstMessage` для `simple-voice-to-text` зафиксирован в `false`.
  - В `SystemPrompt` появляется computed property `var isReadOnly: Bool { isSystem && systemId == "simple-voice-to-text" }`. Это локализованное правило, не требует нового поля в Codable.
  - В `PromptsStore.migrateIfNeeded` (`currentDataVersion = 3`) после загрузки прокидывается принудительная синхронизация: для каждого промпта с `isSystem && systemId == "simple-voice-to-text"` — `content` и `name` перезаписываются из `SystemPromptDefinition.simpleVoiceToText`. После миграции `dataVersion` пишется как `3`.
- **Rationale**:
  - Формулировки соответствуют Clarification Q2 («force-rewrite»).
  - Использование computed `isReadOnly` вместо нового Codable-поля исключает риск рассинхронизации файла и кода: правило задаётся в одном месте.
  - Миграция дозированная: затрагивает только конкретный промпт по `systemId`.
- **Alternatives considered**:
  - Добавить Codable-поле `isReadOnly: Bool` в `SystemPrompt` — отверг: лишняя сущность, дублирует семантику `isSystem`.
  - Удалять и пересоздавать запись `simple-voice-to-text` при миграции — отверг: теряется UUID, ломаются ссылки (`isDefault` мог быть выбран на этой записи).

---

## R-006: Унификация streaming и non-streaming веток `sendMessage`

- **Decision**: В `RecordingViewModel.sendMessage` non-streaming ветка (`formattingService.format(text:systemPrompt:...)`) удаляется. Все отправки идут через `streamingService.streamChat(messages: messagesForAPI, model: ...)`, который уже принимает полный массив сообщений и стримит токены. Если `streamingService == nil` (теоретически не должно случаться в production-конфигурации) — выбрасывается ошибка инициализации, а не fallback к одиночному вызову.
- **Rationale**:
  - Текущая non-streaming ветка отправляет ровно один `text` и не использует историю — это и есть тот баг, который US3/FR-005/FR-008 закрывают.
  - StreamingFormattingService уже корректно принимает `[(role, content)]` массив через `streamChat(messages:)`.
  - Единый путь упрощает поддержку: FR-006 (edited messages), FR-007 (truncate), FR-006 (chain) — реализуются только в одном месте — в `prepareMessagesForLLM`.
- **Alternatives considered**:
  - Поддерживать обе ветки и пробросить полный array в каждую — отверг: дублирование, риск расхождения форматирования.
  - Использовать non-streaming как «без стриминга» fallback — отверг: streaming уже работает стабильно (см. ProcessingRouterTests); смысла поддерживать оба пути нет.

---

## R-007: Disabled-состояние Send и кнопки повторной голосовой записи на время стрима

- **Decision**: 
  - В `OverlayContentView` пробросить `isStreaming: Bool` (вычислять как `chatSession?.lastAssistantMessage?.isStreaming == true`) в `InputBar` и в overlay-кнопки voice-input.
  - На SwiftUI Toggle — `.disabled(isStreaming)`; кнопка повторной записи `.disabled(isStreaming || ...)` (составной условие включает существующие state-проверки `.idle`).
  - Дополнительно сделать defensive guard в `sendMessage`: если `lastAssistantMessage?.isStreaming == true` — return.
- **Rationale**:
  - Соответствует Clarification Q4 (blocking strategy).
  - SwiftUI `.disabled` — идиоматическое решение, не требует нового state-machine.
- **Alternatives considered**:
  - Cancel-and-resend — отверг: clarification Q4.
  - Queue — отверг: clarification Q4.

---

## R-008: Размещение чекбокса и tooltip в Settings → System Prompts

- **Decision**:
  - В `SettingsView` в секции редактирования промпта (под полем `content`) добавить горизонтальный `HStack`:
    - `Toggle("answer_in_first_message_label".localized, isOn: $prompt.answerQuestionsInFirstMessage).disabled(prompt.isReadOnly)`
    - `Button(action: { showHelp = true }) { Image(systemName: "questionmark.circle") }.popover(isPresented: $showHelp) { Text(helpText) }`
  - Локализованные ключи:
    - `answer_in_first_message_label` = «Отвечать на вопросы в первом сообщении?» (ru), «Answer questions in the first message?» (en), и аналогично для остальных 8 локалей.
    - `answer_in_first_message_help` = пояснение «При включении модель может отвечать на вопросы, прозвучавшие в первом голосовом сообщении. При выключении — только форматирует текст. Действует только на первое сообщение сессии.»
  - Для `simple-voice-to-text` (read-only): controls для content/name/toggle отображаются в disabled-состоянии; кнопка Delete скрыта (`.disabled(prompt.isReadOnly)` + условное `.hidden()` для Delete).
- **Rationale**:
  - Использует существующий паттерн локализации проекта (`Localizable.xcstrings`).
  - Не вводит новое окно/sheet — pop-over по icon-info это стандарт macOS.
- **Alternatives considered**:
  - Inline-описание под Toggle — отверг: визуально перегружает форму редактирования.
  - Отдельный «Advanced» pane — отверг: оверкилл для одной настройки.

---

## R-009: Логирование (Principle 6)

- **Decision**: Добавляются INFO/DEBUG-логи:
  - **INFO** при `prepareMessagesForLLM`: `prepareMessagesForLLM done` с metadata: `messageCount`, `droppedPairs`, `isFirstVoiceTurn`, `answerQuestionsInFirstMessage`, `injectedDoNotAnswer` (bool).
  - **INFO** при miграции `PromptsStore` v2 → v3: `Migrated simple-voice-to-text content` с metadata: `previousContentHash` (только хеш, не содержимое), `language`.
  - **DEBUG** при инжекции `do-not-answer`: содержимое полного системного промпта (с `privacy: .private`) для отладки.
  - **DEBUG** при усечении: список индексов отброшенных сообщений и итоговый `totalTokens`.
  - Содержимое чат-сообщений и текст транскрипции — **никогда не логируются на INFO**; на DEBUG — с `\(text, privacy: .private)` (нативное macOS-маскирование).
- **Rationale**: соответствует Principle 6 и existing pattern в `ChatSession`/`ProcessingRouter`.

---

## R-010: Тестирование (Principle 5)

Тестируемые слои и mocking-стратегия:

- **`SystemPromptTests`**: добавить tests на `Codable` round-trip с/без поля `answerQuestionsInFirstMessage` (миграция формата старого файла); `isReadOnly` computed property для `simple-voice-to-text` vs custom prompts.
- **`ChatSessionTests`** (новый/расширяемый): unit-tests `prepareMessagesForLLM`:
  - Когда история помещается в бюджет — все сообщения проходят.
  - Когда не помещается — отбрасываются пары с начала; одиночный осиротевший assistant в начале отрезается.
  - Системный промпт и последнее user-сообщение всегда сохраняются.
  - При `isFirstVoiceTurn=true, answerQuestionsInFirstMessage=false` — в system message появляется инструкция «не отвечать» в `voiceLanguage`.
  - При `isFirstVoiceTurn=false` — инструкция отсутствует.
  - Edited message: после изменения `message.content` payload содержит новый текст.
- **`PromptsStoreTests`** (новый/расширяемый): тест миграции v2 → v3 на фейковом JSON-файле; force-rewrite `simple-voice-to-text` контента с любой кастомной формы → новая формулировка.
- **`RecordingViewModelTests`** (минимально, если уже есть mock-инфраструктура): unit-test что `sendMessage` действительно вызывает `streamingService.streamChat` с массивом, начинающимся с системного промпта + последнее сообщение пользователя в конце.

Mocking: API уже за protocol'ами (`StreamingFormattingServiceProtocol`, `TranscriptionServiceProtocol`), новых mock'ов не требуется.

---

## R-011: Совместимость и rollback

- **Decision**: Миграция `currentDataVersion = 3` строго прямая (forward-only). Откат на предыдущую версию приложения корректно прочитает файл (на чтении игнорирует неизвестное поле `answerQuestionsInFirstMessage` — это стандартное поведение `Codable.decodeIfPresent`, которое в `SystemPrompt.init(from:)` уже применяется к новым полям при добавлении). Перезаписанный content `simple-voice-to-text` в старой версии будет восприниматься как пользовательская кастомизация, но визуально совпадёт с тем же текстом — никаких ошибок.
- **Rationale**: даёт безопасное возвращение к предыдущему build без потерь.

---

## Сводный список разрешённых вопросов

| Источник | Вопрос | Решение |
|----------|--------|---------|
| Spec (Q1) | Edit cascade behavior | Keep subsequent history as-is |
| Spec (Q2) | `simple-voice-to-text` migration + editability | Force-rewrite + read-only |
| Spec (Q3) | Truncation granularity | Pairs user/assistant |
| Spec (Q4) | Send while streaming | Block (disable controls) |
| Spec (Q5) | Language of "do-not-answer" instruction | Localized to voiceLanguage + English fallback |
| Plan (R-001) | Where to store the new toggle | In `SystemPrompt`, Codable |
| Plan (R-003) | Where to track "first voice turn" | In `RecordingViewModel`, ephemeral |
| Plan (R-006) | Streaming vs non-streaming branches | Unify to streaming only |
| Plan (R-008) | UI placement | Inline `Toggle` + `?` icon popover under content field |

Все `[NEEDS CLARIFICATION]` resolved.
