# Tasks: Vocabularies and Personal Preferences (012-vocabularies)

**Input**: Design documents from `/specs/012-vocabularies/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md
**Updated**: Drawer instead of modal window, updated card design, US-7 Response Language

**Organization**: Tasks are grouped by user scenario for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can be done in parallel (different files, no dependencies)
- **[Story]**: Which user scenario the task belongs to (US1, US2, etc.)
- Paths are given from the project root

---

## Phase 1: Foundational (Models, storage, prompt integration)

**Goal**: Base infrastructure. Completed.

- [X] T001 [P] Create the VocabularyEntry model in Verborra/Models/VocabularyEntry.swift
- [X] T002 [P] Add the `.vocabulary` category to LogCategory in Verborra/Models/LogCategory.swift
- [X] T003 [P] Add `personalPreferencesText` (@AppStorage) to AppSettings in Verborra/Models/AppSettings.swift
- [X] T004 Create VocabularyStore in Verborra/Services/VocabularyStore.swift
- [X] T005 Create PromptEnhancer in Verborra/Services/PromptEnhancer.swift
- [X] T006 Modify FormattingService — PromptEnhancer in Verborra/Services/FormattingService.swift
- [X] T007 Modify StreamingFormattingService — PromptEnhancer in Verborra/Services/StreamingFormattingService.swift
- [X] T008 Add tabs to SettingsTab in Verborra/Views/SettingsView.swift
- [X] T009 Add vocabularyStore to SettingsViewModel in Verborra/ViewModels/SettingsViewModel.swift

---

## Phase 2: US-7 — Response Language as a prompt section (Priority: P1)

**Goal**: The response language is passed as a separate `## Response Language` section with a MUST/MUST NOT instruction.

**Independent test**: Language "English" → phrase in Russian → LLM response in English. In the debug log the "Response Language" section is visible.

- [X] T010 [US7] Update PromptEnhancer.enhance() — replace the "Response language: {displayName}" string with the `## Response Language` section containing a MUST/MUST NOT instruction (RFC 2119) in Verborra/Services/PromptEnhancer.swift

---

## Phase 3: US-1 + US-2 — Creating vocabulary entries via the drawer (Priority: P1)

**Goal**: The user creates an entry via the side drawer and it is applied to LLM requests.

**Independent test**: Vocabularies → "Add Replacement" → drawer → enter "GitHub" + "git hub" → Add → card (gray background, large bold Target Word) → say "open git hub" → LLM response with "GitHub".

- [X] T011 [P] [US1] Create TagInputField in Verborra/Views/Components/TagInputField.swift
- [X] T012 [US1] Create VocabularyEditorDrawer (side drawer: Target Word field + TagInputField + Add button) in Verborra/Views/VocabularyEditorDrawer.swift (depends on T011)
- [X] T013 [US1] Update VocabulariesSettingsTab — drawer instead of sheet; cards: gray background, gray "Target Word" caption, large bold targetWord, separator, gray "Alternatives" caption, chip tags; click → drawer; empty state in Verborra/Views/VocabulariesSettingsTab.swift (depends on T012)
- [X] T014 [US1] Wire VocabulariesSettingsTab into SettingsView in Verborra/Views/SettingsView.swift
- [X] T015 [US2] Inject VocabularyStore into RecordingViewModel in Verborra/ViewModels/RecordingViewModel.swift

---

## Phase 4: US-3 + US-4 — Personal preferences (Priority: P1)

**Goal**: Personal preferences. Completed.

- [X] T016 [US3] Create PersonalPreferencesSettingsTab in Verborra/Views/PersonalPreferencesSettingsTab.swift
- [X] T017 [US3] Wire it into SettingsView in Verborra/Views/SettingsView.swift

---

## Phase 5: US-5 — Managing entries via the drawer (Priority: P2)

**Goal**: Editing and deleting entries via the side drawer with "Apply" / "Delete" buttons.

**Independent test**: Click on a card → drawer → change → "Apply" → updated. Click → "Delete" → removed.

- [X] T018 [US5] Extend VocabularyEditorDrawer: edit mode (pre-filled fields, "Apply" and "Delete" buttons) in Verborra/Views/VocabularyEditorDrawer.swift (depends on T012)
- [X] T019 [US5] Update VocabulariesSettingsTab: click on any element of a card → edit drawer in Verborra/Views/VocabulariesSettingsTab.swift (depends on T018, T013)

---

## Phase 6: US-6 — Logging (Priority: P2)

**Goal**: Logging. Completed.

- [X] T020 [P] [US6] Logging in VocabularyStore in Verborra/Services/VocabularyStore.swift
- [X] T021 [P] [US6] Logging in PromptEnhancer in Verborra/Services/PromptEnhancer.swift
- [X] T022 [P] [US6] Logging in PersonalPreferencesSettingsTab in Verborra/Views/PersonalPreferencesSettingsTab.swift

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T023 Validation in VocabularyStore in Verborra/Services/VocabularyStore.swift
- [X] T024 Validation in VocabularyEditorDrawer: button disabled without data in Verborra/Views/VocabularyEditorDrawer.swift
- [ ] T025 [P] UI string localization in Verborra/Localizable.xcstrings
- [ ] T026 E2E testing: vocabulary + Personal Preferences + Response Language
- [ ] T027 Validation per quickstart.md: prompt format, section order
- [ ] T028 [P] Prompt size warning in Verborra/Services/PromptEnhancer.swift
- [X] T029 Delete VocabularyEditorSheet.swift, update references to VocabularyEditorDrawer in Verborra/Views/

---

## Dependencies and execution order

### Outstanding tasks

| ID | Phase | Description |
|----|------|----------|
| T010 | Phase 2 | Response Language section in PromptEnhancer |
| T012 | Phase 3 | VocabularyEditorDrawer (new) |
| T013 | Phase 3 | VocabulariesSettingsTab (drawer + cards) |
| T018 | Phase 5 | Drawer — edit mode |
| T019 | Phase 5 | Card → edit drawer |
| T024-T029 | Phase 7 | Polish |

### Parallel opportunities

- T010 and T012 — in parallel (different files)
- T025 and T028 — in parallel

---

## Implementation strategy

1. **T010** — Response Language (PromptEnhancer) — in parallel with T012
2. **T012** — VocabularyEditorDrawer (new file)
3. **T013** — VocabulariesSettingsTab (updated cards + drawer)
4. **T018-T019** — Edit mode
5. **T029** — Delete VocabularyEditorSheet
6. **T024-T028** — Polish
