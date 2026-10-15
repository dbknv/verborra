# Contract: Model Selection, Migration and Settings UI

**Requirements**: FR-030, FR-031, FR-032, FR-034, FR-036–FR-039, FR-041 | **Research**: R24, R25

## Settings UI (`LLMSettingsTab`)

- The speech-to-text picker iterates `STTModel.allCases`, which has one entry. The picker control and layout are unchanged (FR-031).
- The text model picker iterates `LLMModel.allCases`: 10 entries in the data-model order (FR-030).
- `modelInfoPopover`: same rows (name in headline, description in caption), now inside a `ScrollView` with `maxHeight: 420` and the width still 280 (R25). Every row's description includes the price (FR-034).
- No status labels, badges or migration notices anywhere in the UI (FR-038).

## Launch-time migration (`ModelSelectionMigrator.run(defaults:log:)`)

Called once from `AppDelegate.applicationDidFinishLaunching(_:)` (`Verborra/VerborraApp.swift`), right after the logging setup and before `AppController` is created, so no model setting has been read yet. The transition table is in [data-model.md](../data-model.md#modelselectionmigrator-new-verborramodelsmodelselectionmigratorswift).

Guarantees:
- G1: After the call, `selectedSTTModelRawValue` / `selectedLLMModelRawValue` are either missing (fresh install) or a current `rawValue`.
- G2: A saved current model is never changed (FR-037, FR-039).
- G3: Calling it twice produces the same state, and the second call logs nothing.
- G4: It shows no UI.

## Diagnostic event

| Message | Level | Category | When | Metadata |
|---|---|---|---|---|
| `Model selection migrated` | INFO | `.lifecycle` | each key the migrator rewrites | `kind` (`stt`/`llm`), `old` (raw ID), `new` (raw ID), `reason` (`removed`/`inheritedDefault`) |

`.lifecycle` is used because the switch happens at app startup, not through a user action. No new `LogCategory` is needed.

Existing events are unchanged: settings change logging when the user picks a model, and the `.api` request and response logs, which already include `model`.
