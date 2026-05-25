# Data Model: Interface Multilanguage Support

**Feature Branch**: `003-multilanguage-support`
**Date**: 2026-03-09

## Entity Changes

### SystemPrompt (modification)

**File**: `Verborra/Models/SystemPrompt.swift`

```swift
// BEFORE (v1):
struct SystemPrompt: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var isDefault: Bool
    var voiceLanguage: SupportedLanguage    // ← REMOVED
    var textLanguage: SupportedLanguage     // ← REMOVED
}

// AFTER (v2):
struct SystemPrompt: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var isDefault: Bool
    var isSystem: Bool                      // ← ADDED
    var systemId: String?                   // ← ADDED
}
```

**New fields**:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `isSystem` | `Bool` | `false` | System prompt flag (protection against editing/deletion) |
| `systemId` | `String?` | `nil` | Identifier for linking to the translation registry (e.g. `"simple-voice-to-text"`) |

**Removed fields**:

| Field | Reason for removal |
|-------|--------------------|
| `voiceLanguage` | Migrated to global `AppSettings` (FR-010a) |
| `textLanguage` | Migrated to global `AppSettings` (FR-010a) |

**Validation rules**:
- If `isSystem == true`, then `systemId` MUST NOT be `nil`
- If `isSystem == true`, `name` and `content` are computed from the registry on language change
- `isSystem` cannot be changed via the UI after creation
- User prompts: `isSystem == false`, `systemId == nil`

**Behavior during encoding/decoding (Codable)**:
- `init(from decoder:)` — reads `voiceLanguage`/`textLanguage` (if present) for migration, does not store them in model properties
- `encode(to encoder:)` — does not write `voiceLanguage`/`textLanguage`
- `isSystem` is decoded with fallback `false` for compatibility with the old format
- `systemId` is decoded with fallback `nil`

---

### AppSettings (modification)

**File**: `Verborra/Models/AppSettings.swift`

```swift
// ADDED:
@AppStorage("globalVoiceLanguage")
private var globalVoiceLanguageRawValue: String = ""

@AppStorage("globalTextLanguage")
private var globalTextLanguageRawValue: String = ""

var globalVoiceLanguage: SupportedLanguage { get set }
var globalTextLanguage: SupportedLanguage { get set }
```

**New fields**:

| Field | Storage type | Default | Description |
|-------|--------------|---------|-------------|
| `globalVoiceLanguage` | `@AppStorage("globalVoiceLanguage")` | `.ru` | Global speech recognition language |
| `globalTextLanguage` | `@AppStorage("globalTextLanguage")` | `.ru` | Global text output language |

**Default value logic**:
- During migration (v1→v2): the value is taken from the default prompt
- For new users (no migration, raw value empty): `.ru` (compatible with current behavior — the application originally worked only in Russian, voice/text language defaults were `.ru`)
- If the value is invalid → `.ru`

---

### SystemPromptDefinition (new entity)

**File**: `Verborra/Models/SystemPromptDefinition.swift` (new)

```swift
struct SystemPromptDefinition {
    let id: String
    let translations: [SupportedLanguage: (name: String, content: String)]

    func name(for language: SupportedLanguage) -> String {
        translations[language]?.name ?? translations[.en]!.name
    }

    func content(for language: SupportedLanguage) -> String {
        translations[language]?.content ?? translations[.en]!.content
    }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Unique identifier (`"simple-voice-to-text"`) |
| `translations` | `[SupportedLanguage: ...]` | Dictionary of translations into interface languages (en, ru) |

---

### SystemPromptRegistry (new entity)

**File**: `Verborra/Models/SystemPromptDefinition.swift` (in the same file)

```swift
enum SystemPromptRegistry {
    static let all: [SystemPromptDefinition] = [.simpleVoiceToText]

    static func definition(for systemId: String) -> SystemPromptDefinition? {
        all.first { $0.id == systemId }
    }
}
```

**Content of the `simple-voice-to-text` prompt**:

| Language | Name | Content |
|----------|------|---------|
| en | Simple Voice To Text | Fix speech recognition errors, add punctuation and capitalization. Break into paragraphs by meaning. Return only the corrected text. |
| ru | (Russian translation of "Simple Voice To Text") | (Russian translation of the English content above) |

---

## Existing Entities (unchanged)

### LocalizationManager

Central localization manager. Singleton, `@Observable`, accessible via SwiftUI Environment. **No significant changes** — already implemented and works.

### SupportedLanguage

Existing enum. 10 values: en, ru, es, fr, de, pt, zh, ja, ko, it. **Unchanged**.

---

## Data Migration

### JSON format: v1 → v2

**Trigger**: `PromptsStore.init()`, check `UserDefaults("promptsDataVersion") < 2`

**Steps**:

1. Load `prompts.json` (decoder compatible with both formats)
2. Find the default prompt → move `voiceLanguage` / `textLanguage` into UserDefaults:
   - `UserDefaults("globalVoiceLanguage")` = defaultPrompt.voiceLanguage.rawValue
   - `UserDefaults("globalTextLanguage")` = defaultPrompt.textLanguage.rawValue
3. Find the "Standard" prompt (or the first prompt) → replace with a system prompt:
   - `isSystem = true`
   - `systemId = "simple-voice-to-text"`
   - `name` = from the registry by the current `uiLanguage`
   - `content` = from the registry by the current `uiLanguage`
   - Preserve the original `isDefault`
4. Save `prompts.json` in the new format (without voiceLanguage/textLanguage)
5. Set `UserDefaults("promptsDataVersion") = 2`

**Fallback**: If the file cannot be read — create a system prompt from scratch.

---

## Relationships Between Entities

```
AppSettings
├── uiLanguage: SupportedLanguage          (UI language, en/ru)
├── globalVoiceLanguage: SupportedLanguage  (NEW: voice for all prompts)
└── globalTextLanguage: SupportedLanguage   (NEW: text for all prompts)

PromptsStore
├── prompts: [SystemPrompt]
│   ├── SystemPrompt (isSystem: true, systemId: "simple-voice-to-text")
│   │   └── name/content → SystemPromptRegistry.definition(for: systemId)
│   └── SystemPrompt (isSystem: false, user prompts)
└── defaultPrompt: SystemPrompt

SystemPromptRegistry
└── all: [SystemPromptDefinition]
    └── translations: [SupportedLanguage: (name, content)]

RecordingViewModel
├── selectedPrompt: SystemPrompt
├── selectedVoiceLanguage ← AppSettings.globalVoiceLanguage (per-session)
└── selectedTextLanguage ← AppSettings.globalTextLanguage  (per-session)
```

## Localization Key Format

Prefix-based grouping (unchanged):

| Prefix | Module | Example key |
|--------|--------|-------------|
| `onboarding.` | Onboarding | `onboarding.welcome.title` |
| `settings.` | Settings | `settings.general.recording` |
| `recording.` | Recording | `recording.idle.hint` |
| `result.` | Result | `result.paste` |
| `error.` | Errors | `error.micNotAvailable` |
| `common.` | Common | `common.cancel` |
| `menu.` | Menu Bar | `menu.settings` |
| `model.` | STT/LLM models | `model.stt.gpt4oMini.info` |
