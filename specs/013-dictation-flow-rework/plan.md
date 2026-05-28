# Implementation Plan: Dictation and Message-Processing Flow Rework (v0.13)

**Branch**: `013-dictation-flow-rework` | **Date**: 2026-05-27 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/013-dictation-flow-rework/spec.md`

## Summary

The feature reworks the dictation flow along four coordinated axes:

1. **Controlled first-voice-message behavior.** A boolean field `answerQuestionsInFirstMessage` (default `false`) is added to `SystemPrompt`. When it is off AND the message is the first voice turn of the session, a `## Critical Instruction` section with a localized, strengthened "do not answer" prompt (including an example/counter-example to ground small models) is appended **at the end** of the final system message — after all `PromptEnhancer` sections. For subsequent messages and when the toggle is on, no such instruction is added. See R-002 / FR-003 / FR-003a / FR-003b / FR-003c.
2. **Correct chat history with edits and limits.** `ChatSession.prepareMessagesForLLM` builds the payload for continuation messages: it substitutes a minimal **chat-mode system message** ("You are a helpful assistant. Respond in <lang>.") in place of the user's dictation prompt (R-012 / FR-005a), includes the full session history in its current (edited) form, and truncates in user/assistant pairs. The non-streaming branch of `sendMessage` is removed — all sends go through `streamingService.streamChat(messages:model:)`. The UI disables Send and the re-record button while `isStreaming`.
3. **Simplifying and locking `simple-voice-to-text`.** In `SystemPromptDefinition.simpleVoiceToText` all 10 locales are rewritten to the short form "fix spelling + punctuation, return only the text." `PromptsStore` gets a new migration (`currentDataVersion = 3`) that force-overwrites the content of this built-in prompt. The Settings → System Prompts UI blocks editing for read-only entries (new computed property `isReadOnly = isSystem && systemId == "simple-voice-to-text"`).
4. **Unified LLM path.** The first voice turn (previously using `streamFormat`) now also goes through `streamChat` — `RecordingViewModel.stopRecording` explicitly calls `PromptEnhancer.enhance(...)` and then appends `## Critical Instruction`, giving direct control over the DoNotAnswer position.

The technical approach is targeted edits to existing files (`SystemPrompt.swift`, `SystemPromptDefinition.swift`, `PromptsStore.swift`, `ChatSession.swift`, `RecordingViewModel.swift`, `OverlayContentView.swift`, `SettingsView.swift`), with no new modules or dependencies. Unit tests in `VerborraTests/` cover every FR.

## Technical Context

**Language/Version**: Swift 5.9+ (Xcode 15+)
**Primary Dependencies**: SwiftUI, AppKit (NSPanel, NSAlert), AVFoundation (AVAudioEngine — already in use), swift-markdown (4.0+ — already in use for rendering), KeyboardShortcuts (sindresorhus — already in use), swift-atomics (1.2+ — already in use for streaming)
**Storage**: JSON file `~/Library/Application Support/Verborra/system_prompts.json` (via the existing `PromptsStore`); UserDefaults for `promptsDataVersion`
**Testing**: XCTest (existing `VerborraTests` target — has `SystemPromptTests`, `ProcessingRouterTests`, new tests added)
**Target Platform**: macOS 15+ (Sequoia), 26+ (Tahoe) — unchanged
**Project Type**: single (macOS app, MVVM)
**Performance Goals**: SC-004 — first-response latency does not increase by more than 5% over baseline; SC-008 — payload truncation does not produce context errors
**Constraints**: All constitution requirements (Swift only, MVVM with `@Observable`, keys in Keychain, no new external dependencies)
**Scale/Scope**: ~7 modified Swift files, ~15 new unit tests, one data migration (single overwrite at first launch)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Justification |
|---------|--------|-------------|
| **P1: Native macOS experience** | ✅ Pass | Changes are limited to SwiftUI/AppKit views and `@Observable` view-models. No web tech. The Settings checkbox is a standard `Toggle`. Disabling Send during streaming uses the standard SwiftUI `.disabled(...)` pattern. |
| **P2: Swift-first development** | ✅ Pass | All code in Swift. No new dependencies. Reuses existing: SwiftUI, AVFoundation, `@Observable`. |
| **P3: Minimalism and simplicity** | ✅ Pass | One new bool per prompt, one new parameter in payload composition, one one-time rewrite migration. No new windows or screens. No new external DBs. |
| **P4: Security and privacy** | ✅ Pass | No new data beyond the per-prompt boolean (stored in the existing JSON, non-sensitive). Message contents stay in session RAM and transit to OpenAI as before. No new logged entities; we keep `\(value, privacy: .private)` for message text. |
| **P5: Code quality and testing** | ✅ Pass | Every FR is covered by a unit test. API mocks already exist (`ProcessingRouterTests`). No new SwiftLint warnings — the existing style is preserved. |
| **P6: Logging and observability** | ✅ Pass | INFO-level logs: session creation noting `answerQuestionsInFirstMessage`, the do-not-answer injection event, the truncation event with dropped-pair count. DEBUG-level: full payload (instruction text, history size, budget). Confidential data (message text) is logged with `privacy: .private`. |

**Conclusion**: no violations. The Complexity Tracking section is empty.

## Project Structure

### Documentation (this feature)

```text
specs/013-dictation-flow-rework/
├── plan.md              # This file (/speckit.plan)
├── research.md          # Phase 0 — technical decisions and trade-offs
├── data-model.md        # Phase 1 — changes to SystemPrompt and ChatSession
├── quickstart.md        # Phase 1 — how to validate the feature locally
├── contracts/
│   └── llm-payload.md   # Contract: how the OpenAI Chat Completions payload is built
├── checklists/
│   └── requirements.md  # Created by /speckit.specify
└── tasks.md             # Phase 2 — produced by /speckit.tasks (not in this plan)
```

### Source Code (repository root)

The existing `Verborra/` single-Swift-app structure is preserved. Changes are localized to the files listed below — no new directories.

```text
Verborra/
├── Models/
│   ├── SystemPrompt.swift               # +field answerQuestionsInFirstMessage, Codable, dataVersion migration
│   ├── SystemPromptDefinition.swift     # content() rewritten for all 10 locales; +localized DoNotAnswerInstruction
│   ├── ChatSession.swift                # prepareMessagesForLLM: pair-truncation + always-current edited message text
│   ├── ChatMessage.swift                # (no changes; isStreaming already exists)
│   └── TokenEstimator.swift             # (no changes; used as-is)
├── Services/
│   ├── PromptsStore.swift               # currentDataVersion: 2 → 3; new force-rewrite migration + read-only handling
│   └── FormattingService.swift          # (no changes; callers move to streamChat)
├── ViewModels/
│   ├── RecordingViewModel.swift         # sendMessage: remove non-streaming branch (unify via prepareMessagesForLLM); first-turn transcription sent through streamChat; isFirstVoiceTurnConsumed flag
│   └── SettingsViewModel.swift          # +toggle handler for answerQuestionsInFirstMessage
├── Views/
│   ├── OverlayContentView.swift         # Send button and re-record button get .disabled(isStreaming)
│   └── SettingsView.swift               # Settings → System Prompts: Toggle + tooltip; read-only entries → disabled controls and hidden Delete
└── Localizable.xcstrings                # +checkbox label/tooltip strings (10 locales)

VerborraTests/
├── SystemPromptTests.swift              # +tests: migration, default value, read-only mark
├── ChatSessionTests.swift               # +tests: prepareMessagesForLLM (pair-truncation, edited messages, system + last-user invariants)
├── PromptsStoreTests.swift              # +tests: force-rewrite simple-voice-to-text, dataVersion 2→3
└── ProcessingRouterTests.swift          # (unchanged)
```

**Structure Decision**: single Swift macOS app, MVVM. Changes fit into existing files without introducing new modules or restructuring. This aligns with principle 3 (minimalism) and minimizes the merge surface.

## Complexity Tracking

> Constitution Check passes with no violations — this section is intentionally empty.
