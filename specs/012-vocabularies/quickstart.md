# Quickstart: Vocabularies and Personal Preferences (012-vocabularies)

**Date**: 2026-03-22
**Branch**: `012-vocabularies`

## Prerequisites

- Xcode 15+ with the macOS 15 SDK
- A working build of the Verborra application
- OpenAI API key (for testing the LLM integration)

## Architecture overview

```
┌─────────────────────────────────────────────────────┐
│                   SettingsView                       │
│  ┌──────────────┐  ┌────────────────────────────┐   │
│  │ Vocabularies │  │   Personal Preferences      │   │
│  │    Tab       │  │          Tab                │   │
│  │              │  │                             │   │
│  │ [Cards]      │  │ [Auto-grow TextField]       │   │
│  │ [Add btn]    │  │ (200-600px, debounce 0.5s) │   │
│  └──────┬───────┘  └────────────┬───────────────┘   │
│         │                       │                    │
│  ┌──────▼───────┐               │                    │
│  │ Editor Sheet │               │                    │
│  │ (modal)      │               │                    │
│  └──────┬───────┘               │                    │
└─────────┼───────────────────────┼────────────────────┘
          │                       │
   ┌──────▼───────┐    ┌──────────▼──────────┐
   │ Vocabulary   │    │   AppSettings       │
   │   Store      │    │ .personalPreferences│
   │ (JSON file)  │    │ (@AppStorage)       │
   └──────┬───────┘    └──────────┬──────────┘
          │                       │
          └───────────┬───────────┘
                      │
               ┌──────▼───────┐
               │ PromptEnhancer│
               │ .enhance()   │
               └──────┬───────┘
                      │
          ┌───────────▼───────────┐
          │  FormattingService /   │
          │ StreamingFormatting    │
          │ Service               │
          │                       │
          │ fullSystemPrompt =    │
          │   basePrompt          │
          │   + language          │
          │   + preferences       │
          │   + vocabularies      │
          └───────────────────────┘
```

## Key files to modify

| File | Action | Description |
|------|----------|----------|
| `Models/VocabularyEntry.swift` | NEW | Vocabulary entry model (Codable, Identifiable) |
| `Models/LogCategory.swift` | MODIFY | Add `.vocabulary` |
| `Services/VocabularyStore.swift` | NEW | CRUD for the vocabulary + JSON persistence |
| `Services/PromptEnhancer.swift` | NEW | Build prompt sections (Personal Preferences + Vocabulary Replacements) |
| `Services/FormattingService.swift` | MODIFY | Use PromptEnhancer for fullSystemPrompt |
| `Services/StreamingFormattingService.swift` | MODIFY | Use PromptEnhancer for fullSystemPrompt |
| `Views/SettingsView.swift` | MODIFY | Add the .vocabularies and .personalPreferences tabs |
| `Views/VocabulariesSettingsTab.swift` | NEW | Page with cards and the Add Replacement button |
| `Views/VocabularyEditorDrawer.swift` | NEW | Side drawer for creating/editing an entry (replaces VocabularyEditorSheet) |
| `Views/PersonalPreferencesSettingsTab.swift` | NEW | Page with the auto-growing text field |
| `Views/Components/TagInputField.swift` | NEW | Tag input component |
| `ViewModels/SettingsViewModel.swift` | MODIFY | Properties for vocabularies and preferences |
| `Models/AppSettings.swift` | MODIFY | Add personalPreferencesText |

## Implementation order

1. **Models and storage** → VocabularyEntry, VocabularyStore, AppSettings (personalPreferencesText)
2. **Prompt integration** → PromptEnhancer, modify FormattingService/StreamingFormattingService
3. **UI: Personal Preferences** → PersonalPreferencesSettingsTab, debounce save
4. **UI: Vocabularies** → TagInputField, VocabularyEditorDrawer (drawer), VocabulariesSettingsTab (updated cards)
5. **Settings integration** → SettingsView (new tabs), SettingsViewModel
6. **Logging** → LogCategory.vocabulary, logs in VocabularyStore and PromptEnhancer
7. **Tests** → Unit tests for VocabularyStore, PromptEnhancer, VocabularyEntry validation

## Prompt format (PromptEnhancer output)

```
{baseSystemPrompt}

## Response Language

You MUST respond in the following language: {textLanguage.displayName}.
You MUST NOT use any other language in your response, even if the user's input is in a different language. If the input language differs from the response language, translate the content accordingly.

## Personal Preferences

You MUST follow the user's personal preferences listed below in every response. You MUST NOT deviate from these rules.

{personalPreferencesText}

## Vocabulary Replacements

You MUST use the exact "Target Word" in your response whenever the user's input contains any of the listed alternatives. You MUST NOT use the alternative spelling in your output — replace it with the target word.

| Target Word | Alternatives |
|-------------|-------------|
| GitHub | git hub, githab |
| Verborra | verbora, verborrah |
```

The Response Language section is always present. The Personal Preferences and Vocabulary Replacements sections are included only when they contain data.
