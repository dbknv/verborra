# Implementation Plan: Переработка flow диктовки и обработки сообщений (v0.13)

**Branch**: `013-dictation-flow-rework` | **Date**: 2026-05-27 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/013-dictation-flow-rework/spec.md`

## Summary

Фича перерабатывает flow диктовки в три согласованных направления:

1. **Управляемое поведение первого голосового сообщения.** В модель `SystemPrompt` добавляется булево поле `answerQuestionsInFirstMessage` (дефолт — `false`). Если выключено и сообщение является первым голосовым в сессии — к локализованному системному промпту инжектируется дополнительная инструкция «не отвечать на вопросы, не уточнять, только отформатировать». Для всех последующих сообщений сессии и при включённом чекбоксе инструкция не добавляется.
2. **Корректная история чата с учётом правок и лимитов.** Метод `ChatSession.prepareMessagesForLLM` уже формирует payload, но `sendMessage` имеет non-streaming-ветку, которая отправляет только последний текст. Унифицируем: обе ветки идут через `prepareMessagesForLLM`. Усечение по лимиту перерабатывается с «по одному» на «парами `user → assistant`». UI получает disabled-состояние для Send/повторной записи на время `isStreaming`.
3. **Упрощение и блокировка `simple-voice-to-text`.** В `SystemPromptDefinition.simpleVoiceToText` все 10 локалей переписываются на короткую формулировку «исправь орфографию + знаки препинания, верни только текст». `PromptsStore` получает новую миграцию (`currentDataVersion = 3`), которая принудительно перезаписывает контент этого системного промпта и помечает его как read-only (новое поле `isReadOnly` либо использование `isSystem` + `systemId == "simple-voice-to-text"`). UI Settings → System Prompts скрывает controls editing для read-only записи.

Технический подход — точечные правки в существующих файлах (`SystemPrompt.swift`, `SystemPromptDefinition.swift`, `PromptsStore.swift`, `ChatSession.swift`, `RecordingViewModel.swift`, `OverlayContentView.swift`, `SettingsView.swift`), без введения новых модулей или зависимостей. Юнит-тесты в `VerborraTests/` покрывают каждое FR.

## Technical Context

**Language/Version**: Swift 5.9+ (Xcode 15+)
**Primary Dependencies**: SwiftUI, AppKit (NSPanel, NSAlert), AVFoundation (AVAudioEngine — уже используется), swift-markdown (4.0+ — уже используется для рендеринга), KeyboardShortcuts (sindresorhus — уже используется), swift-atomics (1.2+ — уже используется в стриминге)
**Storage**: JSON файл `~/Library/Application Support/Verborra/system_prompts.json` (через существующий `PromptsStore`); UserDefaults для `promptsDataVersion`
**Testing**: XCTest (существующий `VerborraTests` target — есть `SystemPromptTests`, `ProcessingRouterTests`, добавляются новые тесты)
**Target Platform**: macOS 15+ (Sequoia), 26+ (Tahoe) — без изменений
**Project Type**: single (macOS app, MVVM)
**Performance Goals**: SC-004 — латентность первого ответа не возрастает более чем на 5% от baseline; SC-008 — payload-усечение не приводит к ошибкам контекста
**Constraints**: Все требования Constitution (только Swift, MVVM с `@Observable`, ключи в Keychain, без новых внешних зависимостей)
**Scale/Scope**: ~7 модифицируемых Swift-файлов, ~15 новых юнит-тестов, миграция данных (одна перезапись при первом запуске)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Статус | Обоснование |
|---------|--------|-------------|
| **P1: Native macOS experience** | ✅ Pass | Изменения только в SwiftUI/AppKit View и Observable ViewModel. Никаких web-технологий. Чекбокс в Settings — стандартный `Toggle`. Кнопка Send в disabled — стандартный паттерн SwiftUI (`.disabled(...)`). |
| **P2: Swift-first development** | ✅ Pass | Весь код на Swift. Никаких новых зависимостей. Используются существующие: SwiftUI, AVFoundation, `@Observable`. |
| **P3: Minimalism and simplicity** | ✅ Pass | Один новый bool на промпт, один новый параметр в payload-формировании, одна перезаписывающая миграция. Никаких новых окон или экранов. Никаких новых external-DBs. |
| **P4: Security and privacy** | ✅ Pass | Никаких новых данных, кроме булева поля промпта (хранится в существующем JSON, не критично). Содержимое сообщений всё так же только в RAM сессии + транзитом в OpenAI API. Никаких новых логируемых сущностей; продолжаем `\(value, privacy: .private)` для текстов сообщений. |
| **P5: Code quality and testing** | ✅ Pass | Каждое FR покрывается юнит-тестом. Mock'и API уже есть (`ProcessingRouterTests`). SwiftLint warnings не добавляются — используем существующий стиль. |
| **P6: Logging and observability** | ✅ Pass | Логируется на уровне INFO: создание сессии с указанием значения `answerQuestionsInFirstMessage`, факт инжекции инструкции «не отвечать», факт усечения истории и количество отброшенных пар. На DEBUG — полный payload (текст инструкции, размер истории, новый бюджет). Confidential-данные (тексты сообщений) логируются с `privacy: .private`. |

**Вывод**: нарушений нет. Раздел Complexity Tracking не заполняется.

## Project Structure

### Documentation (this feature)

```text
specs/013-dictation-flow-rework/
├── plan.md              # Этот файл (/speckit.plan)
├── research.md          # Phase 0 — технические решения и trade-offs
├── data-model.md        # Phase 1 — изменения в SystemPrompt и ChatSession
├── quickstart.md        # Phase 1 — как локально проверить feature
├── contracts/
│   └── llm-payload.md   # Контракт «как формируется payload в OpenAI Chat Completions»
├── checklists/
│   └── requirements.md  # Уже создан /speckit.specify
└── tasks.md             # Phase 2 — создаётся /speckit.tasks (НЕ в этом плане)
```

### Source Code (repository root)

Существующая структура проекта `Verborra/` (single Swift app). Изменения локализованы в перечисленных ниже файлах — никаких новых директорий не вводится.

```text
Verborra/
├── Models/
│   ├── SystemPrompt.swift               # +поле answerQuestionsInFirstMessage, Codable, dataVersion miграция
│   ├── SystemPromptDefinition.swift     # переписываются content() для всех 10 локалей; +localized doNotAnswerInstruction
│   ├── ChatSession.swift                # prepareMessagesForLLM: усечение парами + edited messages always-in
│   ├── ChatMessage.swift                # (нет изменений; isStreaming уже есть)
│   └── TokenEstimator.swift             # (нет изменений; используется как есть)
├── Services/
│   ├── PromptsStore.swift               # currentDataVersion: 2 → 3; новая миграция force-rewrite + read-only marker
│   └── FormattingService.swift          # (нет изменений; вызовы переходят на streamChat)
├── ViewModels/
│   ├── RecordingViewModel.swift         # sendMessage: убрать non-streaming branch (или унифицировать через prepareMessagesForLLM); транскрипцию первого сообщения отправлять через streamChat; флаг isFirstVoiceTurnConsumed
│   └── SettingsViewModel.swift          # +обработчик toggle для answerQuestionsInFirstMessage
├── Views/
│   ├── OverlayContentView.swift         # Send button и кнопка повторной записи .disabled(isStreaming)
│   └── SettingsView.swift               # Settings → System Prompts: Toggle + tooltip; для read-only — disabled controls и hidden delete
└── Localizable.xcstrings                # +строки label/tooltip чекбокса (10 локалей)

VerborraTests/
├── SystemPromptTests.swift              # +тесты: миграция, default-value, read-only mark
├── ChatSessionTests.swift               # +тесты: prepareMessagesForLLM (pair-truncation, edited messages, system-prompt + last-user invariant)
├── PromptsStoreTests.swift              # +тесты: force-rewrite simple-voice-to-text, dataVersion 2→3
└── ProcessingRouterTests.swift          # (без изменений)
```

**Structure Decision**: single Swift app (macOS), MVVM. Изменения встраиваются в существующие файлы без создания новых модулей и без структурных перестроек. Это совпадает с principle 3 (minimalism) и обеспечивает минимальный merge surface.

## Complexity Tracking

> Constitution Check прошёл без нарушений — раздел не заполняется.
