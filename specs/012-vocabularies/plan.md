# Implementation Plan: Vocabularies and Personal Preferences

**Branch**: `012-vocabularies` | **Date**: 2026-03-22 (updated) | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/012-vocabularies/spec.md`

## Brief description

Add two new sections to the Verborra application settings:
1. **Vocabularies** — a user-defined auto-replacement dictionary (target word → alternative spellings), passed to the LLM prompt as a Markdown table with an RFC 2119 (MUST/MUST NOT) instruction. UI: cards on a gray background, a side drawer for creation/editing.
2. **Personal Preferences** — arbitrary Markdown instructions from the user, appended to the system prompt for all LLM requests.
3. **Response Language** — a dedicated prompt section with a MUST instruction about the target response language (replaces the plain "Response language" string).

All three sections are integrated into the system prompt assembly chain (`PromptEnhancer` → `FormattingService` / `StreamingFormattingService`) after Whisper transcription. Vocabulary data is stored in a JSON file, Personal Preferences — in @AppStorage.

## Technical context

**Language/Version**: Swift 5.9+ (Xcode 15+)
**Primary Dependencies**: SwiftUI, AVFoundation, swift-markdown (0.4.0+), KeyboardShortcuts (2.0.0+), swift-atomics (1.2.0+)
**Storage**: JSON files in `~/Library/Application Support/Verborra/` (vocabularies.json); UserDefaults / @AppStorage (personal preferences text)
**Testing**: XCTest / Swift Testing
**Target Platform**: macOS 15 (Sequoia)+
**Project Type**: Single macOS app (Xcode project + SPM)
**Performance Goals**: Adding sections to the prompt < 10 ms; loading a 100-entry vocabulary < 100 ms
**Constraints**: No external DBs (Constitution Principle 3); API key in Keychain (Constitution Principle 4)
**Scale/Scope**: Up to 100 vocabulary entries; single user; one Personal Preferences text field

## Constitution check

*GATE: Check before Phase 0. Re-check after Phase 1.*

| Principle | Status | Comment |
|---------|--------|-------------|
| 1. Native macOS experience | Passed | SwiftUI, native components (SwiftUI trailing sidebar/inspector for the drawer), HIG |
| 2. Swift-first development | Passed | All code in Swift, MVVM + @Observable, URLSession + async/await |
| 3. Minimalism and simplicity | Passed | Storage via JSON files + UserDefaults; no external DBs; minimal UI |
| 4. Security and privacy | Passed | No confidential data (vocabulary and settings are user text); the API key is not touched |
| 5. Code quality and testing | Passed | Unit tests for VocabularyStore, PromptEnhancer; protocols for mocking |
| 6. Logging and observability | Passed | Reuses the existing DiagnosticLogger; category `.vocabulary`; info/debug levels |

No constitution violations. Gate passed.

## Project structure

### Documentation (this feature)

```text
specs/012-vocabularies/
├── spec.md              # Specification (7 US, 36 FR)
├── plan.md              # This file
├── research.md          # Phase 0: research
├── data-model.md        # Phase 1: data model
├── quickstart.md        # Phase 1: quickstart
└── tasks.md             # Phase 2: tasks (created by /speckit.tasks)
```

### Source code (from repository root)

```text
Verborra/
├── Models/
│   ├── VocabularyEntry.swift          # Vocabulary entry model
│   └── LogCategory.swift              # MODIFY: .vocabulary category
├── Services/
│   ├── VocabularyStore.swift          # Vocabulary storage and management (JSON)
│   ├── PromptEnhancer.swift           # MODIFY: add Response Language section, update order
│   ├── FormattingService.swift        # MODIFY: PromptEnhancer for fullSystemPrompt
│   └── StreamingFormattingService.swift # MODIFY: PromptEnhancer for fullSystemPrompt
├── Views/
│   ├── SettingsView.swift             # MODIFY: .vocabularies and .personalPreferences tabs
│   ├── VocabulariesSettingsTab.swift   # MODIFY: drawer instead of sheet, updated card design
│   ├── VocabularyEditorDrawer.swift    # NEW: side drawer for creation/editing (replaces VocabularyEditorSheet)
│   ├── PersonalPreferencesSettingsTab.swift # UI for the Personal Preferences tab
│   └── Components/
│       └── TagInputField.swift         # Tag input component
├── ViewModels/
│   └── SettingsViewModel.swift         # MODIFY: vocabularyStore
└── Models/
    └── AppSettings.swift               # MODIFY: personalPreferencesText (@AppStorage)
```

**Structure decision**: The existing project is a single macOS app. `VocabularyEditorSheet` is renamed to `VocabularyEditorDrawer` and implemented via SwiftUI `.inspector()` or a trailing sidebar instead of `.sheet()`.

## Key changes (plan update)

### 1. Drawer instead of modal window
- **Before**: `.sheet(isPresented:)` for creating/editing entries
- **After**: Side drawer (SwiftUI `.inspector()` or `NavigationSplitView` with a trailing sidebar)
- **File**: `VocabularyEditorSheet.swift` → `VocabularyEditorDrawer.swift`
- **Buttons**: "Add" for creation, "Apply" + "Delete" for editing (instead of Update/Delete)

### 2. Updated card design
- Gray background (`.controlBackgroundColor`)
- Gray "Target Word" caption at the top, target word in large bold font
- Gray "Alternatives" caption, chip tags
- Clicking any element of the card → drawer

### 3. US-7: Response Language as a prompt section
- **Before**: `"\(systemPrompt)\n\nResponse language: \(textLanguage.displayName)"`
- **After**: `## Response Language` section with a MUST/MUST NOT instruction (RFC 2119)
- **File**: `PromptEnhancer.swift` — update the `enhance()` method
- **Prompt order**: base → Response Language → Personal Preferences → Vocabulary Replacements

## Complexity tracking

No constitution violations — section not required.
