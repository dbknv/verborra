---
description: "Task list for feature 013 — Переработка flow диктовки и обработки сообщений (v0.13)"
---

# Tasks: Переработка flow диктовки и обработки сообщений (v0.13)

**Input**: Design documents from `/specs/013-dictation-flow-rework/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/llm-payload.md](contracts/llm-payload.md)

**Tests**: Включены — соответствует Principle 5 конституции (business logic MUST be covered by unit tests) и разделу «Тестовая поверхность» в data-model.md.

**Organization**: Задачи сгруппированы по user stories, каждая story независимо тестируема. UI-папки `ui/*.md` для этой фичи нет (изменения локализованы в Settings и Overlay), поэтому отдельных UI-component-задач не генерируется.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Можно выполнять параллельно (разные файлы, нет блокирующих зависимостей).
- **[Story]**: К какой user story относится задача (US1, US2, US3, US4).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Базовая подготовка ветки и общих ресурсов локализации.

- [ ] T001 Проверить, что ветка `013-dictation-flow-rework` чистая (`git status`), и запустить baseline `xcodebuild test -project Verborra.xcodeproj -scheme Verborra -only-testing:VerborraTests` — все существующие тесты ДОЛЖНЫ быть зелёными до начала работы.
- [ ] T002 [P] Добавить локализованные строки `answer_in_first_message_label` и `answer_in_first_message_help` для 10 локалей (en, ru, es, fr, de, pt, zh, ja, ko, it) в `Verborra/Localizable.xcstrings`. Тексты: см. research.md R-008.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Доменные изменения в моделях/сервисах, на которых стоят ВСЕ user stories. Без этой фазы ни одна story не реализуема.

**⚠️ CRITICAL**: Никакая работа по user stories не может начаться до завершения этой фазы.

- [ ] T003 Расширить структуру `SystemPrompt` в `Verborra/Models/SystemPrompt.swift`: добавить поле `var answerQuestionsInFirstMessage: Bool` (default `false`), добавить case в `CodingKeys`, использовать `decodeIfPresent(...) ?? false` в `init(from decoder:)`, всегда писать в `encode(to:)`. Добавить computed `var isReadOnly: Bool { isSystem && systemId == "simple-voice-to-text" }`. Обновить `makeDefault()`, чтобы устанавливать `answerQuestionsInFirstMessage = false`. Соответствие FR-001, FR-009b, FR-010, FR-011, FR-012.
- [ ] T004 Переработать `Verborra/Models/SystemPromptDefinition.swift`: (а) переписать `simpleVoiceToText.translations` для всех 10 локалей на упрощённую формулировку (точные строки — research.md R-005); (б) добавить новую структуру `DoNotAnswerInstruction` с `static let translations: [SupportedLanguage: String]` (10 локалей, тексты — data-model.md) и статической функцией `text(for: SupportedLanguage) -> String` с English fallback. Соответствие FR-003a, FR-009.
- [ ] T005 [P] Расширить `VerborraTests/SystemPromptTests.swift` тестами: (а) Codable round-trip с полем `answerQuestionsInFirstMessage`; (б) декодирование старого JSON БЕЗ поля даёт `false`; (в) `isReadOnly == true` только для `simple-voice-to-text`, для остальных системных и пользовательских — `false`; (г) ассерт упрощённого содержимого `SystemPromptDefinition.simpleVoiceToText` во всех 10 локалях — отсутствие подстрок «абзац», «параграф», «paragraph», «paragraphes», «paragrafo», «Absätze», «段落» и аналогичных. Соответствие SC-005.
- [ ] T006 Переработать `Verborra/Models/ChatSession.swift`, метод `prepareMessagesForLLM`: (а) расширить сигнатуру параметрами `isFirstVoiceTurn: Bool`, `answerQuestionsInFirstMessage: Bool`; (б) при `isFirstVoiceTurn && !answerQuestionsInFirstMessage` добавить через `\n\n` к `systemContent` локализованный текст `DoNotAnswerInstruction.text(for: voiceLanguage)` ПЕРЕД блоком `"Язык ответа: ..."`; (в) переработать алгоритм усечения: при превышении бюджета отбрасывать **парами** (`user → assistant`); одиночный осиротевший `assistant` в начале результирующего набора также отрезать; (г) гарантировать инварианты INV-3..INV-6 из data-model.md (system всегда первый, последний user всегда сохраняется, текст берётся из текущего `message.content`). Обновить `ChatSessionProtocol` соответственно. Соответствие FR-003, FR-005, FR-006, FR-007.
- [ ] T007 [P] Создать/расширить `VerborraTests/ChatSessionTests.swift` юнит-тестами: (а) payload не содержит `DoNotAnswerInstruction` при `isFirstVoiceTurn == false`; (б) payload содержит `DoNotAnswerInstruction` в `voiceLanguage` при `isFirstVoiceTurn == true && answerQuestionsInFirstMessage == false`; (в) payload НЕ содержит инструкцию при `answerQuestionsInFirstMessage == true`; (г) при превышении бюджета — отрезание именно парами с начала, последний user сохраняется (тест на 5+ сообщениях); (д) одиночный осиротевший assistant в начале также отрезается; (е) при изменении `message.content` payload содержит обновлённый текст. Соответствие CON-1..CON-7, SC-002, SC-007, SC-008.
- [ ] T008 Переработать `Verborra/ViewModels/RecordingViewModel.swift`: (а) добавить приватное состояние `private var didConsumeFirstVoiceTurn: Bool = false`; (б) при создании новой `ChatSession` (в `processRecording` и при `reset`) — обнулять флаг; (в) в `sendMessage` (текстовый ввод чата) убрать non-streaming-ветку (вызов `formattingService.format(...)`), оставить только `streamingService.streamChat(messages: messagesForAPI, model: ...)`; пробросить в `prepareMessagesForLLM` параметры `isFirstVoiceTurn: false` и `answerQuestionsInFirstMessage: selectedPrompt.answerQuestionsInFirstMessage`; (г) в пути первой голосовой отправки (после транскрипции в `processRecording`) — пробросить `isFirstVoiceTurn: !didConsumeFirstVoiceTurn` и установить `didConsumeFirstVoiceTurn = true` после успешной отправки; (д) defensive-guard: если `chatSession?.lastAssistantMessage?.isStreaming == true` — `sendMessage` сразу `return`. Соответствие FR-004, FR-008, FR-013, FR-014, FR-015.

**Checkpoint**: Foundation готова. После T003–T008 (с зелёными тестами T005, T007) можно начинать работу по user stories параллельно.

---

## Phase 3: User Story 1 — Диктовка без ответов на вопросы (Priority: P1) 🎯 MVP

**Goal**: Дефолтный сценарий «голос → текст»: пользователь надиктовывает с вопросами внутри, при выключенном чекбоксе (дефолт) модель только форматирует — без ответов и встречных уточнений.

**Independent Test**: Выбрать промпт с выключенным чекбоксом «Отвечать на вопросы в первом сообщении?», надиктовать текст с двумя-тремя вопросами; в окне результата — только отформатированная транскрипция, без ответов модели. (См. Сценарий 1 в quickstart.md.)

### Implementation for User Story 1

- [ ] T009 [US1] В `Verborra/Views/SettingsView.swift`, в редакторе промпта (`PromptEditorView` или эквивалентном), добавить под полем `content` горизонтальный `HStack` с `Toggle("answer_in_first_message_label".localized, isOn: $editedPrompt.answerQuestionsInFirstMessage)` и `Button(action: { showHelpPopover.toggle() }) { Image(systemName: "questionmark.circle") }.popover(isPresented: $showHelpPopover) { Text("answer_in_first_message_help".localized).padding().frame(maxWidth: 320) }`. Использовать `.disabled(editedPrompt.isReadOnly)` на `Toggle`. Соответствие FR-002.
- [ ] T010 [P] [US1] Расширить `VerborraTests/RecordingViewModelTests.swift` (создать файл, если его нет) интеграционным тестом: создать `RecordingViewModel` с mock `StreamingFormattingService`, выбрать промпт с `answerQuestionsInFirstMessage = false`, вызвать путь первой голосовой отправки (вызов через transcription-handler), захватить переданный массив `messages`, ассертить что `messages[0].content` содержит подстроку «Do not answer» (en) или эквивалент по `voiceLanguage`. Соответствие SC-001.

**Checkpoint**: US1 полностью функционален и тестируем независимо.

---

## Phase 4: User Story 2 — Диктовка с ответом и продолжением диалога (Priority: P1)

**Goal**: Пользователь надиктовывает вопрос модели, при включённом чекбоксе получает ответ и продолжает диалог в окне результата с полной историей контекста.

**Independent Test**: Включить чекбокс у промпта; надиктовать вопрос; получить содержательный ответ; в текстовом инпуте отправить уточнение со ссылкой на предыдущий ответ; убедиться, что модель удерживает контекст. (См. Сценарий 2 в quickstart.md.)

### Implementation for User Story 2

US2 НЕ требует новых UI или сервисных задач — переключатель уже добавлен в US1 (T009), а сохранение/прокидывание истории и единый streaming-путь обеспечены foundational T006/T008.

- [ ] T011 [P] [US2] Добавить в `VerborraTests/RecordingViewModelTests.swift` интеграционный тест: создать сессию с промптом `answerQuestionsInFirstMessage = true`, надиктовать первое голосовое (mock возвращает текст ответа), затем вызвать `sendMessage("уточнение")`, захватить второй вызов `streamChat`, ассертить, что переданный `messages` содержит четыре элемента в порядке `[system, user₁ (транскрипция), assistant₁ (ответ), user₂ (уточнение)]`, и `messages[0].content` НЕ содержит `DoNotAnswerInstruction`. Соответствие CON-4, SC-006.

**Checkpoint**: US2 функционален. US1 + US2 работают независимо друг от друга через одну и ту же настройку (значение чекбокса).

---

## Phase 5: User Story 3 — Полная история текущего чата с правками и лимитами (Priority: P1)

**Goal**: Все последующие сообщения в окне результата отправляются с полной историей текущей сессии в актуальной (отредактированной) форме; при превышении лимита история усекается парами с начала; на время стрима ввод и повторная запись заблокированы.

**Independent Test**: 1) «запомни число 42» → ответ → «какое число я просил запомнить?» → ответ «42». 2) Отредактировать «42» на «99» → задать тот же вопрос → ответ «99». 3) Синтетическая длинная сессия (>бюджет) → новый запрос проходит, INFO-лог показывает `droppedPairs>0`. (См. Сценарии 3–6 в quickstart.md.)

### Implementation for User Story 3

Большая часть US3 реализована в foundational (T006: pair-truncation + edited content; T008: единый streaming-путь + guard). Здесь остаётся UI-блокировка и расширенные тесты.

- [ ] T012 [US3] В `Verborra/Views/OverlayContentView.swift` пробросить вычисляемое значение `let isAssistantStreaming = viewModel.chatSession?.lastAssistantMessage?.isStreaming == true` в дочерний `InputBar` и в кнопку повторной голосовой записи. На Send-кнопке инпута: `.disabled(isAssistantStreaming || inputText.trimmed.isEmpty)`. На кнопке повторной записи overlay: добавить `isAssistantStreaming` к составному `.disabled(...)`. Соответствие FR-015.
- [ ] T013 [P] [US3] Расширить `VerborraTests/ChatSessionTests.swift` тестами edge-cases pair-truncation: (а) симулировать сессию с 6+ сообщениями (3 пары user/assistant) + новое user; искусственно установить очень маленький `maxTokenBudget`; ассертить, что в результате остаются `[system, ...последняя_пара, user_new]` и `[system, user_new]` для крайнего малого бюджета; (б) симулировать сессию, начинающуюся с осиротевшего assistant в начале, и убедиться, что он отрезается. Соответствие SC-008.
- [ ] T014 [P] [US3] Расширить `VerborraTests/RecordingViewModelTests.swift` тестом: после `sendMessage` с `isStreaming = true` для последнего assistant-сообщения — повторный `sendMessage` не должен инициировать новый `streamChat` (ассерт через mock invocation counter). Соответствие FR-015, CON-8.
- [ ] T015 [P] [US3] Расширить `VerborraTests/RecordingViewModelTests.swift` тестом edited-message: создать сессию, добавить user-сообщение «запомни 42», добавить assistant-ответ, изменить `messages[0].content` на «запомни 99» программно (имитируя `onConfirmEdit`), отправить новый `sendMessage`, ассертить, что переданный `messages[1].content == "запомни 99"`. Соответствие FR-006, SC-007.

**Checkpoint**: US3 функционален — баг-фикс истории применяется единообразно, edited-сообщения попадают в payload в актуальной форме, лимит модели обрабатывается парами, во время стрима ввод заблокирован.

---

## Phase 6: User Story 4 — Упрощение и read-only встроенного `simple-voice-to-text` (Priority: P2)

**Goal**: Встроенный промпт `simple-voice-to-text` принудительно перезаписывается на упрощённую формулировку во всех 10 локалях и становится read-only в UI Settings.

**Independent Test**: 1) Сначала на старой версии (main) отредактировать content `simple-voice-to-text` на «test-content». 2) Запустить новую версию (013). 3) Открыть Settings → System Prompts → выбрать `simple-voice-to-text`. **Ожидание**: content сброшен на новую формулировку, controls (name, content, Toggle) в disabled, кнопка Delete скрыта/disabled. (См. Сценарий 7 в quickstart.md.)

### Implementation for User Story 4

Содержимое промптов уже обновлено в foundational T004. Здесь — миграция и UI read-only.

- [ ] T016 [US4] В `Verborra/Services/PromptsStore.swift`: (а) повысить `currentDataVersion` с `2` до `3`; (б) расширить `migrateIfNeeded()` блоком, выполняемым при `version < 3`: найти промпт с `isSystem && systemId == "simple-voice-to-text"`; если найден — принудительно перезаписать `name` и `content` из `SystemPromptDefinition.simpleVoiceToText` (через `LocalizationManager.shared.currentLanguage`), установить `answerQuestionsInFirstMessage = false`; если не найден — добавить через `ensureSystemPrompts()`; (в) сохранить файл и записать `UserDefaults.standard.set(3, forKey: Self.dataVersionKey)`. Соответствие FR-009a.
- [ ] T017 [US4] В `Verborra/Views/SettingsView.swift` (в редакторе промпта и в списке промптов): для записей с `prompt.isReadOnly == true` — все редактируемые поля (`name`, `content`, `Toggle`) отображать с `.disabled(true)`; кнопку Delete скрывать через условный `if !prompt.isReadOnly { Button("Delete") { ... } }` либо отображать в disabled. Соответствие FR-009b.
- [ ] T018 [P] [US4] Создать/расширить `VerborraTests/PromptsStoreTests.swift` тестом миграции v2 → v3: подготовить временный JSON-файл, имитирующий v2-формат с пользовательским кастомным content у `simple-voice-to-text`; инициализировать `PromptsStore`, указывающий на этот файл; вызвать `migrateIfNeeded()`; ассертить — после миграции (1) `content` промпта равен `SystemPromptDefinition.simpleVoiceToText.content(for: .ru)` (или текущая локаль), (2) `answerQuestionsInFirstMessage == false`, (3) `UserDefaults` хранит `dataVersion = 3`. Соответствие FR-009a.

**Checkpoint**: US4 функционален. Все 4 user stories независимо тестируемы.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Логирование, ручная smoke-проверка по quickstart, финальные проверки качества.

- [ ] T019 Добавить INFO/DEBUG-логи в `Verborra/Models/ChatSession.swift` (`prepareMessagesForLLM`): INFO с metadata `["messageCount", "droppedPairs", "isFirstVoiceTurn", "answerQuestionsInFirstMessage", "injectedDoNotAnswer"]`; на DEBUG — полный системный промпт через `\(systemContent, privacy: .private)`. И в `Verborra/Services/PromptsStore.swift` (`migrateIfNeeded`): INFO `Migrated simple-voice-to-text content to v3 | language=...`. Использовать существующий `DiagnosticLogger`. Соответствие Principle 6, R-009.
- [ ] T020 Прогнать все 7 сценариев из `specs/013-dictation-flow-rework/quickstart.md` вручную на локальной сборке; зафиксировать любые отклонения в `specs/013-dictation-flow-rework/verification/issues.md` (создать файл при необходимости).
- [ ] T021 [P] Прогнать `xcodebuild test -project Verborra.xcodeproj -scheme Verborra -only-testing:VerborraTests` целиком и убедиться, что все тесты (включая существующие) зелёные. Если найдены регрессии в существующих тестах — устранить в той же ветке.
- [ ] T022 [P] Прогнать SwiftLint (`swiftlint --strict` или существующий config) на изменённых файлах; устранить новые warnings/errors. Соответствие Principle 5.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Зависит только от ветки и состояния build. T001 предшествует всему.
- **Foundational (Phase 2)**: Зависит от завершения Setup. Внутри: T003 → T005 (тесты SystemPrompt), T004 не зависит от T003 (можно [P] на разные файлы); T006 не зависит от T003/T004 структурно, но логически использует `DoNotAnswerInstruction` из T004 → ставим T004 перед T006; T008 использует T006 (новая сигнатура `prepareMessagesForLLM`) → T008 после T006.
- **User Stories (Phases 3–6)**: ВСЕ зависят от Foundational (Phase 2). После завершения Phase 2 могут выполняться параллельно при наличии разработчиков:
  - US1, US2, US3, US4 — независимы между собой на уровне реализации (общие изменения уже в foundational).
  - US2 в T011 использует уже добавленный в US1 UI Toggle (T009) для ручного включения, но в unit-тестах состояние промпта задаётся программно — техническая независимость сохранена.
- **Polish (Phase 7)**: Запускается после всех желаемых user stories.

### Detailed Within-Phase Order

Phase 2 (Foundational):
1. T003 (SystemPrompt) — может идти параллельно с T004 (разные файлы)
2. T004 (SystemPromptDefinition) — может идти параллельно с T003
3. T005 (SystemPromptTests) — после T003 и T004
4. T006 (ChatSession) — после T004 (нужна `DoNotAnswerInstruction`)
5. T007 (ChatSessionTests) — после T006
6. T008 (RecordingViewModel) — после T006

Phase 3 (US1):
1. T009 (Settings UI) — независим, можно стартовать сразу после Phase 2
2. T010 (US1 integration test) — после T008 (требует mock'и RecordingViewModel)

Phase 4 (US2):
- T011 — после T008 (как и US1)

Phase 5 (US3):
- T012 (Overlay disabled) — после T008
- T013, T014, T015 — после T006/T008, параллельны между собой ([P])

Phase 6 (US4):
- T016 (PromptsStore миграция) — после T003
- T017 (Settings read-only UI) — после T003 (нужно `isReadOnly`), независим от T009 структурно (разные подсекции SettingsView, могут конфликтовать на merge — поставить sequentially)
- T018 — после T016

Phase 7 (Polish):
- T019 — после T006 и T016
- T020 — после всех US (3–6)
- T021, T022 — после всех изменений

### Parallel Opportunities

- T003 и T004 — разные файлы → [P]
- T005 и T007 — разные тестовые файлы → могут [P] после своих impl-задач
- В Phase 3–6 после foundational почти все задачи могут идти параллельно по разным веткам/разработчикам.
- T013, T014, T015 — все три на разных тест-файлах → [P]
- T021 и T022 — независимые проверки → [P]

---

## Parallel Example: Phase 2 Foundational

```bash
# После T001 запустить T003 и T004 параллельно (разные файлы):
Task T003: "Расширить SystemPrompt в Verborra/Models/SystemPrompt.swift"
Task T004: "Переработать SystemPromptDefinition в Verborra/Models/SystemPromptDefinition.swift"

# После завершения T003+T004 — параллельно T005 и (T006 → T007 → T008):
Task T005: "Расширить SystemPromptTests"
Task T006: "Переработать ChatSession.prepareMessagesForLLM"
Then Task T007: "Тесты ChatSession"
Then Task T008: "Переработать RecordingViewModel"
```

## Parallel Example: After Foundational

```bash
# После Phase 2 — три разработчика берут US параллельно:
Dev A: T009 (US1 UI) → T010 (US1 test)
Dev B: T011 (US2 test) и T012, T013, T014, T015 (US3) последовательно
Dev C: T016 (US4 миграция) → T017 (US4 UI) → T018 (US4 тесты)
```

---

## Implementation Strategy

### MVP First (US1 + foundational)

1. T001, T002 (Setup)
2. T003 → T004 → T005 → T006 → T007 → T008 (Foundational)
3. T009 → T010 (US1)
4. **STOP and VALIDATE**: Сценарий 1 quickstart.md — диктовка без ответов работает на дефолтных настройках.
5. Это уже работающая MVP-выгода — основной use-case продукта закрыт.

### Incremental Delivery

1. Setup + Foundational → инфраструктура готова.
2. + US1 → MVP (диктовка без ответов).
3. + US2 → второй сценарий (диктовка-ассистент с продолжением диалога).
4. + US3 → надёжность чата (история, правки, лимиты, блокировка стрима) — баг закрыт.
5. + US4 → встроенный промпт упрощён и заблокирован.
6. + Polish → логи, smoke-test, SwiftLint.

### Parallel Team Strategy

- Phase 2 (Foundational) ВСЕГДА делается одним владельцем или сильно скоординированной парой — иначе мерж-конфликты в `ChatSession`/`RecordingViewModel`.
- После Phase 2 три-четыре разработчика могут параллельно вести US1/US2/US3/US4.
- Phase 7 — пятый разработчик или один из освободившихся.

---

## Notes

- **Тесты включены**: соответствует Principle 5 (P5) конституции — business logic MUST be covered by unit tests. Конкретный список тестов синхронизирован с разделом «Тестовая поверхность» в [data-model.md](data-model.md).
- **Mocking**: API уже за protocol'ами (`StreamingFormattingServiceProtocol`, `TranscriptionServiceProtocol`, `FormattingServiceProtocol`). Никаких новых mock'ов писать не требуется — переиспользовать существующие из `VerborraTests/`.
- **Файлы под изменения** (полный перечень, для merge-планирования):
  - `Verborra/Models/SystemPrompt.swift` (T003)
  - `Verborra/Models/SystemPromptDefinition.swift` (T004)
  - `Verborra/Models/ChatSession.swift` (T006, T019)
  - `Verborra/ViewModels/RecordingViewModel.swift` (T008)
  - `Verborra/Services/PromptsStore.swift` (T016, T019)
  - `Verborra/Views/SettingsView.swift` (T009, T017)
  - `Verborra/Views/OverlayContentView.swift` (T012)
  - `Verborra/Localizable.xcstrings` (T002)
  - `VerborraTests/SystemPromptTests.swift` (T005)
  - `VerborraTests/ChatSessionTests.swift` (T007, T013) — возможно новый файл
  - `VerborraTests/RecordingViewModelTests.swift` (T010, T011, T014, T015) — возможно новый файл
  - `VerborraTests/PromptsStoreTests.swift` (T018) — возможно новый файл
- **Commit-стратегия**: один коммит на задачу или логическую группу (например, T003+T005 «SystemPrompt + tests», T006+T007 «ChatSession refactor + tests»).
- **Stop-point**: после Phase 3 (MVP US1) безопасно остановиться, deploy и оценить выгоду перед продолжением.
