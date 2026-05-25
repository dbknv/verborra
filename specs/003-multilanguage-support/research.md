# Research: Interface Multilanguage Support

**Feature Branch**: `003-multilanguage-support`
**Date**: 2026-03-09

## Decision R1: Localization mechanism

**Decision**: Custom localization manager with String Catalogs (.xcstrings) as the source of strings

**Rationale**: The standard Apple mechanism (NSLocalizedString / String(localized:)) takes the language from `AppleLanguages` UserDefaults and requires an application restart. The specification requires instant switching (FR-007). The project already uses a custom `LocalizationManager` that:
1. Loads `.lproj` bundles manually via `Bundle(path:)` for the required language
2. Exposes strings through an `@Observable` property, ensuring reactive SwiftUI updates
3. Uses String Catalogs (.xcstrings) as the storage format for translations in Xcode (compiled into .strings/.stringsdict)

**Current status**: `LocalizationManager` is already implemented and works. The `l10n.string("key")` pattern is used in all Views. Fallback to English when a translation is missing. No significant changes required.

**Alternatives considered**:
- Standard `NSLocalizedString` + restart: rejected because FR-007 requires instant switching
- Hardcoded dictionaries in Swift enums: rejected, inconvenient to scale, no standard tooling for translators
- SwiftGen: redundant dependency, violates the constitution's principle of minimal dependencies

---

## Decision R2: Storage of system prompt translations

**Decision**: Swift dictionary `[SupportedLanguage: (name: String, content: String)]` in code (hardcoded)

**Rationale**:
1. The specification explicitly states: "The content of system prompts is stored in the application code (hardcoded)"
2. Prompt translations are used when sending to the OpenAI API — these are not UI strings
3. We need access to a specific translation by language (not by current UI language) for future scenarios
4. There are few prompts (1 today, several in the future) — a dictionary is optimal

**Alternatives considered**:
- Store in .xcstrings — mixes UI strings with API content, inconvenient selection by a specific language
- Store in a JSON file — excessive complexity for 1-2 prompts
- Store in UserDefaults — not suitable for large texts, no versioning

---

## Decision R3: Architecture for extensibility of system prompts

**Decision**: Struct `SystemPromptDefinition` + enum registry `SystemPromptRegistry`

**Rationale**: The specification requires architectural readiness for expanding the list of system prompts (FR-023). The registry allows adding new prompts with a single line.

```swift
struct SystemPromptDefinition {
    let id: String  // "simple-voice-to-text"
    let translations: [SupportedLanguage: (name: String, content: String)]

    func name(for language: SupportedLanguage) -> String
    func content(for language: SupportedLanguage) -> String
}

enum SystemPromptRegistry {
    static let all: [SystemPromptDefinition] = [.simpleVoiceToText]
    static func definition(for systemId: String) -> SystemPromptDefinition?
}
```

**Alternatives considered**:
- Store everything in PromptsStore — mixes storage and definition logic
- Enum with case per prompt — less flexible for future expansion
- Plist/JSON resources — excessive, hardcoded is simpler at the current scale

---

## Decision R4: Prompt data migration (v1 → v2)

**Decision**: Migration in `PromptsStore.init()` with versioning via `UserDefaults("promptsDataVersion")`

**Rationale**: The only place where prompts are loaded from JSON is the `PromptsStore` initializer. Migration logic:

1. **Check the data version** via `UserDefaults("promptsDataVersion")`:
   - If the version < 2 → perform migration
   - If the version >= 2 → skip

2. **Migrate voice/text language**:
   - Find the default prompt (isDefault == true)
   - Move its `voiceLanguage` → `UserDefaults("globalVoiceLanguage")`
   - Move its `textLanguage` → `UserDefaults("globalTextLanguage")`

3. **Migrate "Standard" → system prompt**:
   - Always replace with the system prompt `simple-voice-to-text` (regardless of user modifications)
   - Preserve the original `isDefault`

4. **Set version** = 2

**Codable compatibility**: A custom `init(from decoder:)` reads `voiceLanguage`/`textLanguage` for migration but does not store them in the model. `encode(to:)` does not write the removed fields.

**Alternatives considered**:
- A separate MigrationManager — excessive for a one-time migration
- Migration on every launch without versioning — inefficient

---

## Decision R5: Global voice/text language

**Decision**: Two new `@AppStorage` entries in `AppSettings`: `globalVoiceLanguage` and `globalTextLanguage`

**Rationale**:
- The specification requires (FR-010a): voice/text language are global settings in the "Models" section
- Consistent with the existing approach to storing settings (constitution: UserDefaults / @AppStorage)
- Default: `.ru` (or values from the migration of the default prompt)

**Location in the UI**: "Language" section in the "Models" tab (LLMSettingsTab)

**Per-session behavior**: `RecordingViewModel` initializes `selectedVoiceLanguage`/`selectedTextLanguage` from the global settings. Changes made in the recording overlay are per-session and not persisted.

**Alternatives considered**:
- Keep per-prompt — contradicts FR-010a
- Auto-save from the overlay — unexpected behavior for the user

---

## Decision R6: Displaying system prompts in the UI

**Decision**: `lock.fill` icon + form field blocking

**Rationale**: The specification requires (FR-022) visual distinction and (FR-021) editing blocking.

Implementation:
- In the prompts list: `lock.fill` icon next to the name of the system prompt
- In the editor: all fields are blocked with `.disabled(true)` for system prompts
- Delete button: `.disabled` for system prompts
- "Default" button: available (a system prompt can be set/unset as default)

**Alternatives considered**:
- A separate read-only View for system prompts — code duplication
- Text label "System" — less informative than an icon

---

## Decision R7: Localization of errors and model descriptions

**Decision**: All user-facing strings (errors, model descriptions, durations) MUST be localized via `LocalizationManager`

**Rationale**:
- `RecordingError.errorDescription` contains hardcoded Russian strings — they are displayed in the UI
- `PasteService` contains hardcoded Russian error strings
- `STTModel.infoDescription` and `LLMModel.infoDescription` — Russian-language descriptions
- `MaxRecordingDuration.displayName` — "1 minute", "5 minutes"
- FR-012 requires localization of all screens

**Alternatives considered**:
- Leave errors in a single language: violates FR-012

---

## Decision R8: New dependencies

**Decision**: No new third-party dependencies are REQUIRED

**Rationale**:
- `LocalizationManager` is already implemented using Foundation
- String Catalogs is a built-in Xcode format
- `@Observable` is already used in the project
- Conforms to the constitution's principle of minimal dependencies (P2)

---

## String inventory for translation

### By module:

| Module | File(s) | Approximate string count |
|--------|---------|--------------------------|
| Onboarding | WelcomeStep, PermissionsStep, MicrophoneTestStep, CompletionStep | ~25 |
| Recording | RecordingView | ~10 |
| Result | ResultView | ~5 |
| Settings (General) | SettingsView (GeneralSettingsTab) | ~15 |
| Settings (Prompts) | SettingsView (PromptsSettingsTab) | ~8 |
| Settings (Hotkeys) | HotkeysSettingsTab | ~8 |
| Settings (LLM) | LLMSettingsTab | ~12 |
| Settings (About) | SettingsView (AboutSettingsTab) | ~8 |
| Settings (Advanced) | AdvancedSettingsTab | ~4 |
| Errors | RecordingError, PasteService | ~12 |
| Models | STTModel, LLMModel, MaxRecordingDuration | ~15 |
| Menu Bar | VerborraApp (MenuBarView) | ~3 |
| Common | SettingsTab titles | ~6 |
| **Total** | | **~131** |
