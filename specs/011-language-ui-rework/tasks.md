# Tasks: Language Selection UI Rework

**Input**: Design documents from `/specs/011-language-ui-rework/`
**Prerequisites**: plan.md, spec.md, research.md, quickstart.md

**Tests**: Not explicitly requested in the specification. A unit test for `localizedDisplayName` is included as part of the foundational task (constitution recommendation, Principle 5).

**Organization**: Tasks are grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can be performed in parallel (different files, no dependencies)
- **[Story]**: Which user story it belongs to (US1, US2, US3, US4, US5)
- Exact file paths are specified

---

## Phase 1: Foundation (blocking prerequisites)

**Goal**: Prepare the basic infrastructure that all user stories depend on

**⚠️ CRITICAL**: Work on user stories cannot begin until this phase is complete

- [X] T001 Add the method `localizedDisplayName(for uiLanguage: SupportedLanguage) -> String` to Verborra/Models/SupportedLanguage.swift — mapping of 10 languages × 2 interface languages (ru: Russian names for English, Russian, Spanish, French, German, Portuguese, Chinese, Japanese, Korean, Italian; en: English, Russian, Spanish, French, German, Portuguese, Chinese, Japanese, Korean, Italian). Leave the existing `displayName` unchanged
- [X] T002 [P] Update localization strings in Verborra/Localizable.xcstrings: (1) change `settings.llm.voiceLanguage` to "Your Language" (localized into ru/en), (2) change `settings.llm.textLanguage` to "Response Language" (localized into ru/en), (3) add `settings.llm.voiceLanguageHint` with tooltip text in ru/en stating that this is the primary recording language, (4) add `settings.llm.textLanguageHint` with tooltip text in ru/en stating that the LLM translates into the selected language, (5) add `controlbar.start` (Start, localized into ru/en), `controlbar.stop` (Stop, localized into ru/en)

**Checkpoint**: Foundation ready — work on user stories can begin

---

## Phase 2: User Story 1 — Simplified Floating Window (Priority: P1) 🎯 MVP

**Goal**: Remove the Voice Language selector from the floating window, leave only Text Language, reassign the hotkey

**Independent test**: Open the floating window → one language selector (Text Language) → "2" key switches the language → "3" key does nothing

- [X] T003 [US1] Remove the Voice Language menu block (controlBarMenu with sfSymbol "waveform.circle.fill", hotkeyLabel "2") from Verborra/Views/ControlBarView.swift (lines ~147-165). Make sure the Text Language menu remains
- [X] T004 [US1] Update the Text Language menu in Verborra/Views/ControlBarView.swift: change `hotkeyLabel` from `"3"` to `"2"`, update `sfSymbol` if necessary
- [X] T005 [US1] In the `handleKeyDown()` method in Verborra/ViewModels/RecordingViewModel.swift: (1) for keyCode 19 ("2" key), replace the `cycleVoiceLanguage()` call with `cycleTextLanguage()`, (2) remove the case for keyCode 20 ("3" key) or replace with `break`. Leave the `cycleVoiceLanguage()` method — it may be used in the future

**Checkpoint**: The floating window shows only Text Language, the "2" hotkey switches it, "3" does not work

---

## Phase 3: User Story 4 — Renaming Fields (Priority: P1)

**Goal**: Replace the technical names Voice Language / Text Language with the understandable "Your Language" / "Response Language" in all visible places

**Independent test**: Open Models → Languages settings → fields are called "Your Language" and "Response Language" (localized into the interface language). Open the floating window → the selector is labeled "Response Language" (localized)

- [X] T006 [US4] Update the Text Language menu label in Verborra/Views/ControlBarView.swift: replace `title` with the localized name via `l10n.string("settings.llm.textLanguage")` (value already updated in T002 to "Response Language" localized into ru/en)
- [X] T007 [US4] Make sure that the Picker labels in Verborra/Views/LLMSettingsTab.swift already use `l10n.string("settings.llm.voiceLanguage")` and `l10n.string("settings.llm.textLanguage")` — values were updated in T002, so the names will change automatically. Verify visually

**Checkpoint**: All user-visible labels use the new names. Internal @AppStorage keys are not affected

---

## Phase 4: User Story 3 — Language Names in the Interface Language (Priority: P2)

**Goal**: Display language names in lists in the current interface language (ru/en) instead of original spellings

**Independent test**: Switch the interface language to Russian → all languages in lists are in Russian. Switch to English → all in English. Interface Language picker is not affected

- [X] T008 [P] [US3] In Verborra/Views/LLMSettingsTab.swift, replace `Text(lang.displayName).tag(lang)` with `Text(lang.localizedDisplayName(for: l10n.currentLanguage)).tag(lang)` in both Pickers (Voice Language and Text Language)
- [X] T009 [P] [US3] In Verborra/Views/ControlBarView.swift, replace `viewModel.selectedTextLanguage.displayName` with `viewModel.selectedTextLanguage.localizedDisplayName(for: l10n.currentLanguage)` in the menu title. Also in ForEach, replace `Text(language.displayName)` with `Text(language.localizedDisplayName(for: l10n.currentLanguage))`
- [X] T010 [US3] Verify that in Verborra/Views/GeneralSettingsTab.swift (Interface Language picker), `displayName` (original names) is still used, NOT `localizedDisplayName` — there should be no changes

**Checkpoint**: All languages in Voice/Text lists are displayed in the interface language. Interface Language picker is not affected

---

## Phase 5: User Story 2 — Settings Tooltips (Priority: P2)

**Goal**: Add question-mark icons (?) with popover tooltips to the "Your Language" and "Response Language" fields in settings

**Independent test**: Open Models → Languages settings → (?) icons next to both fields. When clicked — a popover with text in the interface language

- [X] T011 [US2] Add the icon `Image(systemName: "questionmark.circle")` next to the "Your Language" Picker in Verborra/Views/LLMSettingsTab.swift. On click — `.popover()` with text from `l10n.string("settings.llm.voiceLanguageHint")`. Use `@State private var showVoiceLanguageHint = false` to control visibility
- [X] T012 [US2] Add a similar icon and popover for the "Response Language" Picker in Verborra/Views/LLMSettingsTab.swift. Text from `l10n.string("settings.llm.textLanguageHint")`. Use `@State private var showTextLanguageHint = false`

**Checkpoint**: Both tooltips work, the text matches the new field names, localized into ru/en

---

## Phase 6: User Story 5 — Global Shortcut on the Start-Stop Button (Priority: P2)

**Goal**: Dynamically display the current Global Shortcut on the Start-Stop button with separators between modifiers

**Independent test**: Open the floating window → "⌥ Space" is displayed on the Start-Stop button. Change the shortcut in settings → on the next opening the text is updated

- [X] T013 [US5] Create a helper function/computed property `formattedShortcutLabel` in Verborra/Views/ControlBarView.swift (or in a separate extension). The function: (1) gets `KeyboardShortcuts.getShortcut(for: .toggleOverlay)`, (2) maps modifiers to symbols (`.option` → `⌥`, `.command` → `⌘`, `.shift` → `⇧`, `.control` → `⌃`), (3) joins modifier symbols and the key with a space (NOT using "+" — only spaces, for example "⌥ Space", "⌘ ⇧ R"), (4) if the shortcut is not assigned — returns an empty string
- [X] T014 [US5] Update the Start-Stop button in Verborra/Views/ControlBarView.swift: (1) replace the hardcoded `hotkeyLabel: "⌥Space"` with a call to `formattedShortcutLabel`, (2) replace the hardcoded `title: isRecording ? "Stop" : "Start"` with `l10n.string(isRecording ? "controlbar.stop" : "controlbar.start")`

**Checkpoint**: The button displays the current shortcut with separators. When the shortcut is changed, the text updates. Without a shortcut — empty container

---

## Phase 8: User Story 6 — Current Language in the Button Title (Priority: P1)

**Goal**: The language button in the floating window shows the currently selected language instead of a static label

**Independent test**: Open the floating window → the button shows the current language (for example, "Russian"). Press "2" → the text changed to the next language

- [X] T017 [US6] In Verborra/Views/ControlBarView.swift, replace `title: LocalizationManager.shared.string("settings.llm.textLanguage")` with `title: viewModel.selectedTextLanguage.localizedDisplayName(for: LocalizationManager.shared.currentLanguage)` in the Text Language menu (hotkey 2). This will replace the static label "Response Language" with the current value of the selected language (for example, "Russian"). When switching via the hotkey or dropdown menu, the title will update automatically via @Bindable

**Checkpoint**: The language button shows the currently selected language, updates instantly when switching

---

## Phase 9: User Story 7 — Settings Sidebar Width (Priority: P2)

**Goal**: Set the minimum and initial width of the left settings sidebar to 220 pixels

**Independent test**: Open settings → the sidebar has a width of 220px, all items are visible. Attempting to reduce the width is limited to a 220px minimum

- [X] T018 [P] [US7] In Verborra/Views/SettingsView.swift, add `.navigationSplitViewColumnWidth(min: 220, ideal: 220)` (or an equivalent modifier) to the sidebar in NavigationSplitView, to set the minimum and initial width to 220 pixels

**Checkpoint**: The settings sidebar has a width of 220px by default and cannot be narrower

---

## Phase 10: Finalization and Verification

**Goal**: Cross-functional verification of all changes

- [X] T015 Perform manual verification of acceptance scenarios US1–US5 from spec.md
- [X] T016 [P] Verify build without warnings (SwiftLint) and absence of regressions
- [X] T019 Perform manual verification of acceptance scenarios US6 and US7: (1) the language button in the floating window shows the current language, updates when switching, (2) the settings sidebar has a width of 220px

---

## Dependencies and Execution Order

### Phase Dependencies

- **Phase 1 (Foundation)**: ✅ Completed. T001, T002
- **Phase 2 (US1)**: ✅ Completed. T003-T005
- **Phase 3 (US4)**: ✅ Completed. T006-T007
- **Phase 4 (US3)**: ✅ Completed. T008-T010
- **Phase 5 (US2)**: ✅ Completed. T011-T012
- **Phase 6 (US5)**: ✅ Completed. T013-T014
- **Phase 8 (US6)**: Depends on T001 (localizedDisplayName). Can start immediately
- **Phase 9 (US7)**: Fully independent. Can start immediately
- **Phase 10 (Finalization)**: Depends on completion of Phase 8 and Phase 9

### Dependencies Between New User Stories

- **US6 (P1)**: Depends on T001 (localizedDisplayName — already implemented). Can start immediately
- **US7 (P2)**: Fully independent of all other user stories

### Parallel Opportunities

- T017 and T018 are parallel (different files: ControlBarView.swift vs SettingsView.swift)
- US6 and US7 can be performed in parallel

---

## Parallel Example: Phase 1 (Foundation)

```bash
# In parallel:
Task: "T001 — localizedDisplayName in SupportedLanguage.swift"
Task: "T002 — string updates in Localizable.xcstrings"
```

## Parallel Example: Phase 4 (US3)

```bash
# In parallel:
Task: "T008 — localizedDisplayName in LLMSettingsTab.swift"
Task: "T009 — localizedDisplayName in ControlBarView.swift"
```

---

## Implementation Strategy

### MVP (only US1 + US4 — both P1)

1. Complete Phase 1: Foundation (T001, T002)
2. Complete Phase 2: US1 — Simplified Floating Window (T003-T005)
3. Complete Phase 3: US4 — Renaming Fields (T006-T007)
4. **STOP and VALIDATE**: Check both P1 stories independently
5. Already useful to the user

### Incremental Delivery

1. Foundation → ready
2. US1 + US4 → MVP (simplified window + new names)
3. US3 → Localized language names
4. US2 → Settings tooltips
5. US5 → Shortcut on the button
6. Each step adds value without breaking the previous ones

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] ties the task to a specific user story
- Each user story must be completable and testable independently
- Commit after each task or logical group
- Stop at any checkpoint to validate the story
- `@AppStorage` keys (`globalVoiceLanguage`, `globalTextLanguage`, `uiLanguage`) MUST NOT BE CHANGED — backward compatibility
