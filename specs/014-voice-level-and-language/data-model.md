# Data Model — Voice Level Indicator Scaling & Forced Response Language

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Date**: 2026-05-28

This feature does not introduce any new persistent storage. All data either reuses existing models or lives in transient `RecordingViewModel` / `AudioWaveformView` state. The "entities" below are the minimal in-memory shapes the feature relies on.

---

## Existing entities (consumed unchanged)

### `AppSettings.globalTextLanguage`

- **Where**: [Verborra/Models/AppSettings.swift:236-252](Verborra/Models/AppSettings.swift#L236)
- **Backing store**: `@AppStorage("globalTextLanguage")` (UserDefaults).
- **Type**: `SupportedLanguage` (raw value `String`).
- **Default**: `.ru` if empty.
- **Role in this feature**: Read-only source for `RecordingViewModel.initialTextLanguageOnOpen`. **Never mutated by Direction 2.** Mutation continues to come only from the Settings screen UI.

### `RecordingViewModel.selectedTextLanguage`

- **Where**: existing field on the ViewModel.
- **Type**: `SupportedLanguage`.
- **Lifecycle**: Initialized from `AppSettings.globalTextLanguage` inside `RecordingViewModel.showOverlay()` ([RecordingViewModel.swift:473](Verborra/ViewModels/RecordingViewModel.swift#L473)). Reset (or simply re-initialized) on each subsequent overlay open. Discarded when the overlay closes.
- **Role in this feature**: Authoritative "resolved target language" at submission time (per FR-009).

### `RecordingViewModel.didConsumeFirstVoiceTurn`

- **Where**: [RecordingViewModel.swift:18](Verborra/ViewModels/RecordingViewModel.swift#L18)
- **Type**: `Bool`.
- **Lifecycle**: Set to `false` in `showOverlay()`. Captured into a local `isFirstVoiceTurn` at the top of the formatting submission path (line ~607), then set to `true` (line ~628) so subsequent voice turns of the same chat session see `false`.
- **Role in this feature**: Gates the new translation directive injection (FR-011/FR-012) and the new diagnostic event (FR-022). Same gate that currently controls `DoNotAnswerInstruction` injection.

### `SupportedLanguage`

- **Where**: existing enum used throughout the project.
- **Role**: Type for `globalTextLanguage`, `selectedTextLanguage`, and the keys of the new `TranslateToTargetInstruction.translations` dictionary.

---

## New entities (added by this feature)

### `TranslateToTargetInstruction`

- **Where (new)**: appended at the bottom of [Verborra/Models/SystemPromptDefinition.swift](Verborra/Models/SystemPromptDefinition.swift) (parallel to `DoNotAnswerInstruction`).
- **Shape**:

  ```swift
  enum TranslateToTargetInstruction {
      static let translations: [SupportedLanguage: String]
      static func text(for language: SupportedLanguage) -> String
  }
  ```

- **`translations` keys**: every value of `SupportedLanguage` currently used in `DoNotAnswerInstruction.translations` (one-for-one parity ensures no language is silently missing).
- **`translations` values**: a two-branch instruction string in the target language, parameterised by that language's display name. Concrete strings are listed in [contracts/translation-directive.md](./contracts/translation-directive.md).
- **`text(for:)` behavior**: returns `translations[language]` if present, otherwise falls back to the English text. (Same fallback shape as `DoNotAnswerInstruction.text(for:)`.)
- **Lifecycle**: pure static data, no state.
- **Consumed by**: `RecordingViewModel.streamChat()` on first voice turn only.

### `RecordingViewModel.initialTextLanguageOnOpen`

- **Where (new)**: `RecordingViewModel`, near the other window-lifecycle state.
- **Type**: `SupportedLanguage?`.
- **Lifecycle**:
  - Assigned `AppSettings.globalTextLanguage` inside `showOverlay()` (immediately after `didConsumeFirstVoiceTurn = false`).
  - Read at submission time inside the existing first-voice-turn path to classify the override source.
  - Reset to `nil` when the overlay closes.
- **Role**: Lets the diagnostic event distinguish `"settings-default"` from `"user-changed"` (per R5).
- **Storage**: in-memory only. Never persisted.

### `LanguageResolutionLogEvent` (logical schema, not a Swift type)

- **Where (new)**: emitted via the existing `DiagnosticLogger` (no new Swift type required — passed as `metadata: [String: String]` to the existing log call).
- **Fields**: see the table in [contracts/diagnostic-event.md](./contracts/diagnostic-event.md).
- **Category**: `.api` (LogCategory).
- **Level**: `INFO`.
- **Emission rate**: one event per first voice turn of a chat session. Zero events for follow-up turns.

---

## Indicator-side entities (no Swift type changes)

### `AudioWaveformView` parameter surface

- **Existing input**: `audioLevel: Float` (linear 0…1).
- **New internal behavior** (no new public field): wraps body in `GeometryReader`; derives bar `maxHeight` from `geometry.size.height * 0.9`; applies `pow(audioLevel, 0.5)` before mapping to bar height.
- **Public API**: unchanged. Callers continue to pass `audioLevel` and (optionally) wrap in `.frame(height:)`.

---

## State transitions

### Floating-window override lifecycle (Direction 2)

```text
[window closed] ─open─▶ initialTextLanguageOnOpen = AppSettings.globalTextLanguage
                        selectedTextLanguage    = AppSettings.globalTextLanguage
                        didConsumeFirstVoiceTurn = false
                        │
                        ▼
                ┌──────────────────────────────┐
                │ window open, no submission yet │ ◀── user may change selectedTextLanguage
                └──────────────────────────────┘     any number of times (no side effects)
                        │
                  user submits first voice turn
                        │
                        ▼
                resolvedTarget = selectedTextLanguage
                overrideSource = (selectedTextLanguage == initialTextLanguageOnOpen
                                  ? "settings-default"
                                  : "user-changed")
                inject TranslateToTargetInstruction.text(for: resolvedTarget)
                emit LanguageResolutionLogEvent
                didConsumeFirstVoiceTurn = true
                        │
                        ▼
                ┌─────────────────────────────────────────┐
                │ window open, first turn consumed         │
                │ subsequent turns: NO directive injection │
                │ subsequent turns: NO log event           │
                │ language is established by first turn    │
                └─────────────────────────────────────────┘
                        │
                  window close
                        │
                        ▼
                initialTextLanguageOnOpen = nil
                selectedTextLanguage      = (will be re-initialized on next open)
                didConsumeFirstVoiceTurn  = false
                [window closed]
```

### Indicator lifecycle (Direction 1)

The indicator has no new lifecycle. It binds to `audioLevel`, reads container height each layout pass, applies the curve, and animates between consecutive values. There is no first-frame or final-frame state.

---

## Validation rules

- **VR-001**: `TranslateToTargetInstruction.translations` MUST cover every `SupportedLanguage` case currently covered by `DoNotAnswerInstruction.translations`. Enforced by a unit test that iterates `SupportedLanguage.allCases` and asserts each has a non-empty entry.
- **VR-002**: `initialTextLanguageOnOpen` MUST be non-nil whenever `didConsumeFirstVoiceTurn == false` and the overlay is open. Enforced by setting both in the same `showOverlay()` block; tested by exercising the window-open path.
- **VR-003**: The diagnostic log event MUST contain all four metadata fields (`resolvedTargetLanguage`, `directiveInjected`, `overrideSource`, `isFirstVoiceTurn`). Enforced by a unit test that captures the structured-log call and asserts presence.
- **VR-004**: `AudioWaveformView`'s rendered bar maxHeight MUST be a function of the geometry-provided height only — never a hardcoded constant. Enforced by code review; a unit-level snapshot test would be overkill given how visually validated this is.

---

## Concurrency notes

- `selectedTextLanguage` and `didConsumeFirstVoiceTurn` are already accessed on the main actor via the `@Observable` `RecordingViewModel`. The new `initialTextLanguageOnOpen` lives on the same actor and has no special concurrency considerations.
- The diagnostic log emission goes through `DiagnosticLogger`, which is already thread-safe (used today from `ChatSession.prepareMessagesForLLM`).
- The indicator changes are pure SwiftUI — concurrency model is unchanged.
