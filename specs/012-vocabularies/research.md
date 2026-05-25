# Research: Vocabularies and Personal Preferences (012-vocabularies)

**Date**: 2026-03-22
**Branch**: `012-vocabularies`

## Decision 1: Vocabulary storage

**Decision**: A `vocabularies.json` file in `~/Library/Application Support/Verborra/`

**Rationale**:
- Fully aligns with the existing `PromptsStore.swift` pattern, which stores `prompts.json` in the same directory.
- `JSONEncoder`/`JSONDecoder` + atomic write (`Data.write(to:options:.atomic)`) is a proven approach in the project.
- Requires no new dependencies.
- The constitution (Principle 3) forbids external DBs; `UserDefaults` is suitable only for scalars and small settings, not for an array of complex objects.

**Alternatives considered**:
- UserDefaults — unsuitable for an array of objects with nested collections; limited in size and performance.
- CoreData — excessive for < 100 entries, forbidden by the constitution (external DB).
- SwiftData — requires macOS 14+, but the project already targets macOS 15+; nevertheless excessive for such a simple data structure.

## Decision 2: Personal Preferences storage

**Decision**: `@AppStorage("personalPreferencesText")` in `AppSettings.swift`

**Rationale**:
- Personal Preferences is a single string (plain text). `@AppStorage` / `UserDefaults` is the ideal format for scalar values.
- Matches the pattern used by other application settings (`selectedLLMModelRawValue`, `globalVoiceLanguage`, etc.).
- Automatic synchronization with the UI via SwiftUI bindings.
- Debounce save (0.5s) is implemented with standard `Task.sleep` + `Task` cancellation on new input.

**Alternatives considered**:
- JSON file — excessive for a single string; adds load/save complexity.
- Keychain — unsuitable; the preferences text is not a secret.

## Decision 3: PromptEnhancer architecture

**Decision**: A new `PromptEnhancer` service with a single function `enhance(basePrompt:textLanguage:vocabularyEntries:personalPreferences:) -> String`

**Rationale**:
- Isolates prompt-building logic from the network services (`FormattingService`, `StreamingFormattingService`).
- Testability: the prompt construction can be tested without network mocks.
- Both services (`FormattingService.format()` and `StreamingFormattingService.streamFormat()`) build `fullSystemPrompt` identically (lines 48 and 54 respectively) — `PromptEnhancer` removes that duplication.
- Single Responsibility: prompt building is separated from HTTP requests.

**Alternatives considered**:
- Inline modification in each service — code duplication, violates DRY.
- A String extension — weak typing, unsuitable for complex logic with tables.
- Protocol + default implementation — unnecessary abstraction for a single function.

## Decision 4: Injecting the vocabulary into the prompt

**Decision**: Change the signatures of `format()` and `streamFormat()` to add a `promptEnhancer: PromptEnhancer` parameter; `RecordingViewModel` passes it from DI

**Rationale**:
- Minimal change to existing code: `fullSystemPrompt` is built via `promptEnhancer.enhance(...)` instead of string concatenation.
- `RecordingViewModel` already has access to `AppSettings` (via `settings`) — `personalPreferencesText` is taken from there.
- `VocabularyStore` is injected into `RecordingViewModel` similarly to `PromptsStore`.

**Alternatives considered**:
- A global Singleton for VocabularyStore — breaks testability (Principle 5).
- Passing the vocabulary via a closure — complicates the API with no benefit.

## Decision 5: Modal window for the vocabulary

**Decision**: SwiftUI `.sheet(isPresented:)` with `VocabularyEditorSheet`

**Rationale**:
- Native SwiftUI pattern for modal windows on macOS.
- The same View is reused for creation (empty fields, Add button) and editing (pre-filled fields, Update/Delete buttons).
- Conforms to the Human Interface Guidelines (Principle 1).

**Alternatives considered**:
- NSPanel directly — not needed for content inside the Settings window; `.sheet()` is sufficient.
- Inline editing on the card — rejected by the user; cards are read-only.
- Popover — too small for a form with tags.

## Decision 6: TagInputField component

**Decision**: A custom SwiftUI component `TagInputField` with `TextField` + `FlowLayout` for the tags

**Rationale**:
- No built-in SwiftUI components exist for tag input.
- `TextField` + `onSubmit` handles Enter to create a tag.
- Tags render as an `HStack`/`LazyVGrid` with a cross button.
- Reused in the modal for Alternatives.

**Alternatives considered**:
- A third-party library (TagListView) — no SwiftUI version for macOS; the constitution requires minimal dependencies.
- NSTokenField (AppKit) — available but does not integrate cleanly with SwiftUI; would require `NSViewRepresentable`.

## Decision 7: Logging

**Decision**: Add a new `.vocabulary` category to `LogCategory.swift`; use `DiagnosticLogger.logger(for: .vocabulary)`

**Rationale**:
- The existing logging architecture (`DiagnosticLogger`) already supports categories.
- The new category lets us filter vocabulary/settings logs in Console.app.
- Info level: business events (creation, deletion, addition to the prompt).
- Debug level: details (entry contents, prompt section text).
- Personal Preferences is logged through the same `.vocabulary` category (one functional area).

**Alternatives considered**:
- Separate `.vocabulary` and `.personalPreferences` categories — excessive for one feature.
- Using the existing `.settings` — too general; filtering would be lost.

## Decision 8: Personal Preferences debounce save

**Decision**: `Task` with `Task.sleep(for: .milliseconds(500))` + cancellation of the previous Task on new input

**Rationale**:
- Standard Swift Concurrency pattern for debounce without third-party dependencies.
- On every text change: cancel the previous Task, create a new one with a 0.5s delay.
- Additionally: save on the Personal Preferences tab's `onDisappear`.

**Alternatives considered**:
- Combine `debounce` publisher — works, but the project uses @Observable (Observation framework), not Combine.
- Timer — a less clean pattern, harder to cancel.

## Decision 9: Drawer instead of modal window (update)

**Decision**: SwiftUI `.inspector(isPresented:)` or `NavigationSplitView` with a trailing sidebar for the side drawer

**Rationale**:
- `.inspector()` is available from macOS 14+ (the project targets macOS 15+) — a native SwiftUI pattern for side panels.
- The drawer does not fully cover the main content (unlike `.sheet()`), so cards remain visible during editing.
- Follows the macOS Human Interface Guidelines — inspectors and side panels are familiar to users.
- "Apply" and "Delete" buttons instead of "Update" / "Delete" — clearer terminology.

**Alternatives considered**:
- `.sheet()` (modal window) — rejected by the user; covers the main content.
- `.popover()` — too small for a form with tags.
- NSPanel directly — not needed inside the Settings window.

## Decision 10: Response Language as a prompt section (update)

**Decision**: Replace the plain string `"Response language: {displayName}"` with a full `## Response Language` section containing an RFC 2119 MUST/MUST NOT instruction

**Rationale**:
- Consistency: every added instruction (Personal Preferences, Vocabulary Replacements) is formatted as a section with MUST. Response Language must follow the same format.
- Reliability: a plain "Response language: English" string can be ignored by the LLM in long prompts. A section with MUST NOT enforces strict adherence.
- GPT-4.1+ follows literal instructions verbatim — MUST/MUST NOT yields better results.
- Prompt order: base → Response Language → Personal Preferences → Vocabulary Replacements.

**Alternatives considered**:
- Keep the plain string — does not guarantee reliable adherence; inconsistent with the other sections.
- Include the language in Personal Preferences — the user could accidentally delete it; language is a system setting.
