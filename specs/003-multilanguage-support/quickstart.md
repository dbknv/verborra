# Quickstart: Interface Multilanguage Support

**Feature Branch**: `003-multilanguage-support`
**Date**: 2026-03-09

## Overview

The feature adds interface multilanguage support (English/Russian), a localized system prompt "Simple Voice To Text" (10 languages) with protection against editing/deletion, and migrates voice/text language from per-prompt to global settings.

## Key Files to Change

### Models (Models/)

| File | What changes |
|------|--------------|
| `SystemPrompt.swift` | Add `isSystem`, `systemId`. Remove `voiceLanguage`, `textLanguage`. Custom Codable |
| `AppSettings.swift` | Add `globalVoiceLanguage`, `globalTextLanguage` via @AppStorage |
| `SystemPromptDefinition.swift` | **New file** — registry of system prompts with translations into 10 languages |

### Services (Services/)

| File | What changes |
|------|--------------|
| `PromptsStore.swift` | Migration v1→v2, protection of system prompts from deletion/editing, update on language change |
| `PasteService.swift` | Replace hardcoded Russian error strings with localization keys |

### ViewModels (ViewModels/)

| File | What changes |
|------|--------------|
| `RecordingViewModel.swift` | Initialize languages from `AppSettings` instead of the prompt |
| `SettingsViewModel.swift` | Block editing/deletion of system prompts. Remove voice/text from the prompt |

### Views (Views/)

| File | What changes |
|------|--------------|
| `SettingsView.swift` | PromptsSettingsTab: remove voice/text pickers, add system prompt protection |
| `LLMSettingsTab.swift` | Add voice/text language section (global settings) |

### Localization

| File | What changes |
|------|--------------|
| `Localizable.xcstrings` | Add missing keys, verify translation completeness |

## Implementation Order

1. **SystemPromptDefinition** — create the translation registry (independent entity)
2. **SystemPrompt model** — update the struct (isSystem, systemId, remove languages)
3. **AppSettings** — add global voice/text language
4. **PromptsStore migration** — v1→v2 update logic
5. **Localizable.xcstrings** — extract all hardcoded strings
6. **Views** — update UI (system prompt protection, move voice/text into LLM)
7. **RecordingViewModel** — adapt to global languages
8. **Tests** — update existing, add new

## Main Patterns

### String localization
```swift
// Existing pattern (unchanged):
@Environment(LocalizationManager.self) private var l10n
Text(l10n.string("settings.general.language"))
l10n.string("error.format", args: errorMessage)
```

### System prompt check
```swift
if prompt.isSystem {
    // Block editing/deletion
}
```

### Updating system prompts on language change
```swift
// In PromptsStore — called on uiLanguage change:
func updateSystemPrompts(for language: SupportedLanguage) {
    for i in prompts.indices where prompts[i].isSystem {
        if let def = SystemPromptRegistry.definition(for: prompts[i].systemId!) {
            prompts[i].name = def.name(for: language)
            prompts[i].content = def.content(for: language)
        }
    }
    save()
}
```

## Dependencies Between Changes

```
SystemPromptDefinition (independent)
         │
         ▼
SystemPrompt model ──→ PromptsStore migration
         │                      │
         ▼                      ▼
    AppSettings ──→ RecordingViewModel
         │                      │
         ▼                      ▼
   LLMSettingsTab    OverlayContentView
         │                      │
         └──────────┬───────────┘
                    ▼
            Localizable.xcstrings
                    │
                    ▼
                  Tests
```

## What Does NOT Change

- `SupportedLanguage` enum — unchanged
- `LocalizationManager` — already implemented, no significant changes
- User prompts — not translated
- Recording, transcription, formatting logic — not affected
- API contracts with OpenAI — not affected

## Testing

- Unit tests: `SystemPromptRegistry` (translation correctness, fallback)
- Unit tests: `PromptsStore` migration v1→v2 (voice/text transfer, replacement of "Standard")
- Unit tests: `SystemPrompt` Codable (v1/v2 compatibility, isSystem)
- Unit tests: `AppSettings.globalVoiceLanguage/globalTextLanguage` (save, load)
- Manual testing: language switching, checking all screens, system prompt protection
