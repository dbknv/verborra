# Feature Specification: Vocabularies and Personal Preferences

**Feature Branch**: `012-vocabularies`
**Created**: 2026-03-22
**Status**: Draft
**Input**: User description: "Add the 'Vocabularies' and 'Personal Preferences' functionality — two new sections in the application settings. Vocabularies let the user define word auto-replacements for the LLM. Personal Preferences are arbitrary user instructions appended to every LLM request."

## User Scenarios and Testing

### US-1 — Adding a vocabulary entry (Priority: P1)

As a user I want to add a new target word (or phrase) and link one or more alternative spellings to it, so that the LLM model automatically replaces inaccurate recognitions with the correct variant.

**Why this priority**: This is the core mechanic of vocabularies — without the ability to create entries, the vocabulary is meaningless. Even a single entry already brings value.

**Independent test**: Can be fully tested by opening the settings, clicking "Add Replacement", filling out the modal, and verifying that the entry appears as a card in the list and persists across application restarts.

**Acceptance scenarios**:

1. **Given** the user is on the Vocabularies tab in settings, **When** they view the page, **Then** the "Vocabularies" heading is displayed, along with a short description of how the feature works and an "Add Replacement" button.
2. **Given** the user is on the Vocabularies tab, **When** they click the "Add Replacement" button, **Then** a side drawer slides out from the right containing a Target Word field, an Alternatives field, and an "Add" button.
3. **Given** the modal is open, **When** the user enters a target word (for example, `https://meet.google.com/abc-def`) in the Target Word field, **Then** the target word is displayed as a normal input string.
4. **Given** the modal is open with the target word filled in, **When** the user types "meeting link" in the Alternatives field and presses Enter, **Then** an alternative tag is created, the input is cleared, and is ready for the next alternative.
5. **Given** there are tags in the Alternatives field, **When** the user clicks the cross on a tag, **Then** the tag is removed from the alternatives list.
6. **Given** the target word and at least one alternative have been entered, **When** the user clicks the "Add" button, **Then** the drawer closes and a new card with the added entry appears on the Vocabularies page.
7. **Given** there are entry cards on the page, **When** the user closes the settings and opens them again, **Then** all cards are displayed with the saved data.

---

### Instruction obligation standard for the prompt (RFC 2119)

All instructions added to the system prompt for the LLM model (both from Vocabularies and from Personal Preferences) MUST use a single obligation standard based on [RFC 2119](https://datatracker.ietf.org/doc/html/rfc2119):

- **MUST** / **MUST NOT** — a mandatory requirement that the LLM model cannot ignore.
- **SHOULD** / **SHOULD NOT** — a recommendation that allows deviation when there is a compelling reason.

Every instruction section in the system prompt MUST:
1. Begin with a level-2 Markdown heading (`##`).
2. Contain an introductory instruction with the keyword **MUST** to express obligation.
3. Use a consistent wording style: clear, directive sentences without excessive wording (no ALL CAPS, no "bribe" tricks — per the [OpenAI GPT-4.1 Prompting Guide](https://developers.openai.com/cookbook/examples/gpt4-1_prompting_guide) recommendations).

---

### US-2 — Automatic vocabulary application during LLM requests (Priority: P1)

As a user I want all vocabulary entries to be automatically included in the request to the LLM model after speech recognition, so that the response contains the correct target words instead of inaccurate recognitions.

**Why this priority**: This is the second key part of vocabularies — without LLM integration the vocabulary is useless. Together with US-1 they form the vocabularies MVP.

**Independent test**: Can be tested by creating a vocabulary entry (target: "Verborra", alternatives: "verbora", "verborrah"), then speaking a phrase with "verbora", and verifying that the LLM response contains "Verborra".

**Instruction format in the system prompt**:

Vocabulary entries MUST be passed to the LLM model as a separate section of the system prompt containing:
1. Section header: `## Vocabulary Replacements`.
2. An introductory instruction with the keyword **MUST** (RFC 2119) explaining the mandatory replacement rule.
3. A Markdown table with all vocabulary entries, containing two columns: "Target Word" and "Alternatives" (comma-separated alternative spellings).

Example of the expected section format in the system prompt:

```
## Vocabulary Replacements

You MUST use the exact "Target Word" in your response whenever the user's input contains any of the listed alternatives. You MUST NOT use the alternative spelling in your output — replace it with the target word.

| Target Word | Alternatives |
|-------------|-------------|
| GitHub | git hub, githab |
| Verborra | verbora, verborrah |
| https://meet.google.com/abc-def | meeting link, meet link |
```

**Acceptance scenarios**:

1. **Given** the vocabulary contains entries, **When** the user performs voice input and the text is sent for LLM processing, **Then** a "Vocabulary Replacements" section with a Markdown table of all vocabulary entries and an instruction using MUST/MUST NOT keywords (RFC 2119) is added to the LLM request's system prompt.
2. **Given** the vocabulary contains an entry (target: "GitHub", alternatives: "git hub", "githab"), **When** Whisper recognizes "open git hub", **Then** the LLM response contains "GitHub" instead of "git hub".
3. **Given** the vocabulary is empty (no entries), **When** the user performs voice input, **Then** the LLM request is built without the "Vocabulary Replacements" section (behavior unchanged).
4. **Given** the vocabulary contains 50 entries, **When** the system prompt is built, **Then** all 50 entries are included in the Markdown table in the "Vocabulary Replacements" section.

---

### US-3 — Entering personal preferences (Priority: P1)

As a user I want to write arbitrary instructions in the Personal Preferences text field so that they are automatically applied to every LLM request — for example, text formatting rules, prohibition of emoji use, and other general preferences.

**Why this priority**: Personal preferences are a standalone feature that immediately affects the quality of every LLM response. Even without vocabularies it provides value.

**Independent test**: Can be fully tested by opening the Personal Preferences tab, entering the text "Do not use emoji. Format text as numbered lists.", then performing voice input and confirming that the LLM response follows these instructions.

**Acceptance scenarios**:

1. **Given** the user is on the Personal Preferences tab in settings, **When** they view the page, **Then** the heading, a hint description, and a large text field with a placeholder are displayed.
2. **Given** the text field is empty, **When** the user sees the placeholder, **Then** it contains example instructions in Markdown list format (for example: "- Do not use emoji\n- Never use separator").
3. **Given** the user has clicked the text field, **When** they start typing, **Then** the placeholder disappears and the typed text is shown.
4. **Given** the text field contains little text (1-2 lines), **When** the user sees the field, **Then** it has an initial height of about 200 pixels.
5. **Given** the user enters more text, **When** the content exceeds the current field height, **Then** the field automatically grows in height but no more than 600 pixels; once the maximum height is reached, scrolling appears.
6. **Given** the user has entered text with Markdown markup (headings, lists, bold, italic), **When** the text is saved, **Then** on reopening the settings the text is displayed with the saved content.
7. **Given** the user has entered personal preferences, **When** they close the settings and open them again, **Then** the entered text is preserved.

---

### US-4 — Applying personal preferences to LLM requests (Priority: P1)

As a user I want my personal preferences to be automatically included in every LLM request after speech recognition, so that all responses comply with my preferences. The instructions should be highlighted in the prompt so the LLM model does not skip them.

**Why this priority**: Without LLM integration the text field is useless. Together with US-3 they form the personal preferences MVP.

**Independent test**: Can be tested by entering "Do not use emoji" in Personal Preferences, then saying a phrase and verifying that the LLM response does not contain emoji.

**Instruction format in the system prompt**:

Personal preferences MUST be passed to the LLM model as a distinct system prompt section containing:
1. Section header: `## Personal Preferences`.
2. An introductory instruction with the keyword **MUST** (RFC 2119) stating that the rules below are mandatory for every response.
3. The user's personal preferences text in Markdown format (as-is — without modification).

Example of the expected section format in the system prompt:

```
## Personal Preferences

You MUST follow the user's personal preferences listed below in every response. You MUST NOT deviate from these rules.

- Do not use emoji
- Never use separator
- Format text as numbered lists when possible
```

**Section order in the system prompt**:

The final system prompt MUST be built in the following order:
1. The base system prompt (the prompt selected by the user from the Prompts section)
2. The "Response Language" section (always present — the target response language with a MUST instruction)
3. The "Personal Preferences" section (if not empty)
4. The "Vocabulary Replacements" section (if the vocabulary is not empty)

This order ensures that the response language and personal preferences are placed closer to the beginning of the prompt (after the main context), and the vocabulary — at the end (as a reference table).

**Acceptance scenarios**:

1. **Given** text is entered in Personal Preferences, **When** the user performs voice input and the text is sent for LLM processing, **Then** a "Personal Preferences" section is added to the system prompt with the user's text and an instruction to follow it strictly.
2. **Given** Personal Preferences contains "Do not use emoji", **When** the LLM produces a response, **Then** the response contains no emoji.
3. **Given** Personal Preferences is empty, **When** the user performs voice input, **Then** the LLM request is built without the "Personal Preferences" section (behavior unchanged).
4. **Given** both Personal Preferences and the vocabulary are populated, **When** the system prompt is built, **Then** both sections are present in the specified order: Personal Preferences first, then Vocabulary Replacements.
5. **Given** the user has entered the instructions "Format responses as numbered lists", **When** the LLM processes voice input, **Then** the response is formatted as a numbered list.

---

### US-5 — Managing vocabulary entries (Priority: P2)

As a user I want to edit and delete vocabulary entries via the side drawer to keep the vocabulary up to date.

**Why this priority**: Without entry management the vocabulary becomes inconvenient — the user cannot correct mistakes or delete unneeded entries. However, the base functionality (US-1 + US-2) works without this.

**Independent test**: Can be tested by creating an entry, then clicking the card to open the edit drawer, changing the target word, removing one alternative tag, adding a new one, clicking "Apply", and then deleting the entry via "Delete".

**Acceptance scenarios**:

1. **Given** there is an entry card on the Vocabularies page, **When** the user clicks any element of the card (heading, tags, background), **Then** a side drawer slides out on the right — similar to the creation drawer but with pre-filled data and "Apply" and "Delete" buttons instead of "Add".
2. **Given** the edit drawer is open, **When** the user changes the target word and clicks "Apply", **Then** the drawer closes and the card is updated with the new target word.
3. **Given** the edit drawer is open, **When** the user clicks the cross on an alternative tag and clicks "Apply", **Then** the alternative is removed and the card is updated.
4. **Given** the edit drawer is open, **When** the user adds a new alternative and clicks "Apply", **Then** the new alternative appears on the card.
5. **Given** the edit drawer is open, **When** the user clicks "Delete", **Then** the entry is removed, the card disappears from the list, and the entry no longer affects LLM requests.
6. **Given** a card is displayed on the page, **When** the user tries to edit data directly on the card (without opening the drawer), **Then** it is not possible — cards are read-only.

---

### US-6 — Logging vocabulary and personal preferences actions (Priority: P2)

As a developer/support engineer I want all vocabulary and personal preferences actions to be logged with level separation, so that we can diagnose problems and track system behavior.

**Why this priority**: Logging does not affect core functionality but is critical for diagnostics. Without logs it is impossible to understand why a replacement did not work or settings were not applied.

**Independent test**: Can be tested by enabling debug logging in settings (Advanced), then creating a vocabulary entry and performing voice input — info-level logs (the fact of entry creation, the fact of adding sections to the prompt) and debug-level logs (details: which exact entries were added, contents of sections) should appear in the console.

**Log level separation**:

- **Info** — actions actually performed (business events):
  - Vocabulary entry created / updated / deleted
  - Personal preferences saved
  - Vocabulary loaded at application startup (entry count)
  - Vocabulary Replacements section added to the prompt (entry count)
  - Personal Preferences section added to the prompt

- **Debug** — detailed information about each specific action:
  - Contents of a created/updated vocabulary entry (target word + alternatives)
  - Contents of saved personal preferences
  - Full text of the built Vocabulary Replacements and Personal Preferences sections before adding to the prompt
  - Attempt to add a duplicate target word (rejected)
  - Attempt to add an empty value (rejected)
  - Personal Preferences debounce timer triggered / deferred

**Acceptance scenarios**:

1. **Given** the log level is set to info, **When** the user creates a vocabulary entry, **Then** an info-level log entry about creating the entry appears in the console (without detailed contents).
2. **Given** the log level is set to debug, **When** the user creates a vocabulary entry, **Then** info-level (creation fact) AND debug-level logs (target word, list of alternatives) appear in the console.
3. **Given** the log level is set to info, **When** an LLM request is built with a non-empty vocabulary, **Then** an info-level log entry about adding the Vocabulary Replacements section and the entry count appears in the console.
4. **Given** the log level is set to debug, **When** an LLM request is built with a non-empty vocabulary, **Then** a debug-level log entry with the full text of the built Vocabulary Replacements section appears in the console.
5. **Given** the log level is set to info, **When** the user saves personal preferences, **Then** an info-level log entry about the save appears in the console.
6. **Given** the log level is set to debug, **When** an LLM request is built with non-empty personal preferences, **Then** a debug-level log entry with the full text of the Personal Preferences section appears in the console.

---

### US-7 — Response language as a mandatory prompt section (Priority: P1)

As a user I want the chosen response language to be passed into the LLM prompt as a separate section with a mandatory instruction (RFC 2119), so that the LLM always responds in the target language even if the user speaks a different language.

**Why this priority**: Response language is a basic part of the prompt that must work reliably. The current implementation adds the language as a plain string, but for consistency with Vocabularies and Personal Preferences it should be formatted as a fully fledged section with an RFC 2119 MUST instruction.

**Independent test**: Can be tested by choosing the response language "English", then saying a phrase in Russian and verifying that the LLM response is in English. In the debug log the "Response Language" section with a MUST instruction is visible.

**Instruction format in the system prompt**:

The response language MUST be passed to the LLM model as a separate system prompt section containing:
1. Section header: `## Response Language`.
2. An introductory instruction with the keyword **MUST** (RFC 2119) stating that the response MUST be in the specified language.
3. The name of the target language.

Example of the expected section format in the system prompt:

```
## Response Language

You MUST respond in the following language: English.
You MUST NOT use any other language in your response, even if the user's input is in a different language. If the input language differs from the response language, translate the content accordingly.
```

**Acceptance scenarios**:

1. **Given** the user has selected the response language "English", **When** the system prompt is built, **Then** the prompt contains the "Response Language" section with a MUST instruction and the language name "English".
2. **Given** the user has selected the response language "Russian", **When** they speak a phrase in English, **Then** the LLM response is in Russian.
3. **Given** the response language is set, **When** the prompt is built, **Then** the "Response Language" section is placed after the base prompt and before the "Personal Preferences" section (per the updated section order).

---

### Edge cases

**Vocabularies:**
- What happens if the target word is duplicated (an entry with the same target word already exists)? — The system warns the user and does not allow creating a duplicate.
- What happens if an alternative matches the target word? — The system does not add such an alternative (no point replacing a word with itself).
- What happens if the same alternative is specified for multiple target words? — The system warns about the conflict and asks to choose a single target word.
- What happens if the vocabulary contains 100 entries and is sent to the LLM? — All entries are included in the prompt; if the total size becomes too large, the user sees a warning.
- What happens if the target word or alternative is an empty string? — The system does not allow saving empty values.
- What happens if the target word is a long string (URL)? — The system correctly displays long text on the card with wrapping or truncation.
- What happens if the user clicks "Add" in the modal without entering a target word? — The "Add" button is disabled until the target word is filled in.
- What happens if the user clicks "Add" without alternatives? — The "Add" button is disabled until at least one alternative is added.

**Personal Preferences:**
- What happens if the personal preferences text is very long (several thousand characters)? — The text is included in the prompt in full; the field grows up to 600 pixels and then scrolling appears. If the total system prompt size becomes too large, the user sees a warning.
- What happens if the user completely clears the Personal Preferences field? — The system stores the empty value, LLM requests are built without additional user instructions, and the field returns to its initial height with the placeholder.
- What happens if personal preferences conflict with the base system prompt? — Personal preferences supplement the base prompt; conflicts are resolved on the LLM model's side; priority is determined by the order in the prompt.

## Requirements

### Functional requirements

**Vocabularies:**

- **FR-001**: The system MUST provide a new "Vocabularies" section in the application settings, located after the Models (LLM) section and before the Personal Preferences section.
- **FR-002**: The Vocabularies section MUST display the "Vocabularies" heading, a short description of how the feature works, and an "Add Replacement" button.
- **FR-003**: When the "Add Replacement" button is clicked, the system MUST open a side drawer (slider) with a Target Word input field, an Alternatives input field, and an "Add" button.
- **FR-004**: The Target Word field MUST accept an arbitrary string (word, phrase, or URL).
- **FR-005**: The Alternatives field MUST allow entering text and creating tags by pressing Enter; tags MUST support multi-word phrases (with spaces).
- **FR-006**: Each alternative tag MUST have a cross for deletion.
- **FR-007**: The "Add" button in the modal MUST be disabled until the target word is filled in and at least one alternative is added.
- **FR-008**: Clicking "Add" MUST close the drawer and the new entry MUST be displayed as a card on the Vocabularies page.
- **FR-009**: The entry card MUST be displayed on a gray background and contain: at the top — a gray "Target Word" caption, below it — the target word in large bold font; a visual separator; below — a gray "Alternatives" caption and alternative chip tags. The cards MUST be ordered chronologically by addition (newest at the bottom).
- **FR-010**: The cards MUST be read-only — editing directly on the card is not possible. Clicking any element of the card (heading, tags, background) MUST open the edit drawer.
- **FR-011**: When a card is clicked, the system MUST open a side edit drawer — similar to the creation drawer but with pre-filled data and "Apply" and "Delete" buttons instead of "Add".
- **FR-012**: When "Apply" is clicked, the drawer MUST close and the card MUST be updated with the changed data.
- **FR-013**: When "Delete" is clicked, the system MUST delete the entry — the card disappears and the entry no longer affects LLM requests.
- **FR-014**: The system MUST persist the vocabulary across application restarts.
- **FR-015**: The system MUST automatically include all vocabulary entries in the system prompt for every LLM completion request as a separate "Vocabulary Replacements" section containing a Markdown table with "Target Word" and "Alternatives" columns and a mandatory replacement instruction (format described in US-2).
- **FR-016**: The instruction in the "Vocabulary Replacements" section MUST clearly tell the LLM model: when any of the alternatives is detected in the user's text — always use the corresponding target word in the response.
- **FR-017**: The system MUST forbid creating entries with duplicate target words.
- **FR-018**: The system MUST forbid adding empty target words or alternatives.
- **FR-019**: The system MUST forbid adding an alternative that matches the target word of the same entry.
- **FR-020**: If the vocabulary is empty, LLM requests MUST be built without additional replacement instructions (behavior unchanged).

**Personal Preferences:**

- **FR-021**: The system MUST provide a new "Personal Preferences" section in the application settings, located after the Vocabularies section and before the About section.
- **FR-022**: The section MUST contain a "Personal Preferences" heading, a hint description of the section's purpose, and a large multi-line text input field.
- **FR-023**: The text field MUST support arbitrary text input with basic Markdown markup: headings (#), numbered and bulleted lists, bold (**), italic (*).
- **FR-024**: The text field MUST display a placeholder with example instructions (for example: "- Do not use emoji\n- Never use separator") that disappears when typing starts.
- **FR-025**: The text field MUST have an initial height of about 200 pixels.
- **FR-026**: The text field MUST automatically grow in height as text is added, but no more than 600 pixels; when the maximum height is exceeded, vertical scrolling MUST appear.
- **FR-027**: The system MUST persist the personal preferences content across application restarts. Saving MUST occur automatically: (a) when leaving the Personal Preferences tab or closing the settings window, (b) via a debounce timer 0.5 seconds after input inactivity.
- **FR-028**: The system MUST automatically include the personal preferences content in the system prompt for every LLM completion request as a distinct "Personal Preferences" section with a mandatory execution instruction (format described in US-4).
- **FR-029**: If the personal preferences field is empty, LLM requests MUST be built without the "Personal Preferences" section (behavior unchanged).
- **FR-030**: The final system prompt MUST be built in the following order: (1) base system prompt, (2) "Response Language" section with a MUST instruction about the target response language, (3) "Personal Preferences" section (if not empty), (4) "Vocabulary Replacements" section (if the vocabulary is not empty).

**Response Language:**

- **FR-035**: The "Response Language" section MUST always be present in the system prompt and contain: the `## Response Language` heading, a MUST instruction to respond in the specified language and a MUST NOT instruction not to use another language even if the user speaks a different language, with a directive to translate the content when languages differ.
- **FR-036**: The "Response Language" section MUST be built instead of the current plain string "Response language: {displayName}" (format described in US-7).

**Logging (Observability):**

- **FR-031**: The system MUST log major performed actions at the **info** level: vocabulary entry creation / update / deletion, personal preferences save, vocabulary load at startup, adding Vocabulary Replacements and Personal Preferences sections to the prompt.
- **FR-032**: The system MUST log detailed information about each action at the **debug** level: vocabulary entry contents, personal preferences text, full text of built prompt sections, rejected attempts (duplicates, empty values), debounce timer firing.
- **FR-033**: Logging MUST use the application's existing logging system and obey the current log level set in settings (Advanced → Log Level).
- **FR-034**: Logging MUST NOT impact operation performance at the info level; at the debug level a minor increase in record volume is acceptable.

### Key entities

- **VocabularyEntry**: Contains a target word/phrase and a set of alternative spellings. A "one-to-many" relationship — one target word → many alternatives. Every entry has a unique identifier.
- **Alternative**: An alternative spelling or phrase linked to a single vocabulary entry. May contain spaces and special characters.
- **PersonalPreferences**: A single text value — the user's arbitrary text with Markdown markup, applied globally to all LLM requests.

## Success criteria

### Measurable outcomes

- **SC-001**: A user can create a vocabulary entry (target word + alternatives) via the modal in under 30 seconds.
- **SC-002**: After adding an entry to the vocabulary, LLM responses contain the target word instead of the alternatives in 90%+ of cases.
- **SC-003**: A vocabulary with 100 entries loads correctly and is displayed as cards in the settings without noticeable delays.
- **SC-004**: All vocabulary and personal preferences data persist across application restarts without loss.
- **SC-005**: Adding vocabulary entries and personal preferences does not increase voice request processing time by more than 1 second.
- **SC-006**: A user can enter and save personal preferences in under 1 minute.
- **SC-007**: LLM responses comply with the user's personal preferences (for example, no emoji if specified) in 95%+ of cases.
- **SC-008**: All key vocabulary and personal preferences actions appear in the console at the info log level; full detail for diagnostics is available at the debug level.

## Clarifications

### Session 2026-03-22

- Q: When are personal preferences (Personal Preferences) saved? → A: Auto-save when leaving the tab or closing settings + debounce save on inactivity (0.5 seconds without input).
- Q: In what order are vocabulary cards displayed on the page? → A: Chronological order of addition, new cards appear at the bottom of the list.

## Assumptions

- The vocabulary and personal preferences are global — applied to all prompts and sessions, without the ability to bind to a specific prompt (may be extended in the future).
- The instruction format for the LLM is defined in US-2 and US-4 with a single RFC 2119 obligation standard (MUST/MUST NOT): the vocabulary is passed as a Markdown table in the "Vocabulary Replacements" section, the personal preferences — as a Markdown block in the "Personal Preferences" section. Both sections use a consistent style for their introductory instructions.
- Prompt format recommendations are based on [RFC 2119](https://datatracker.ietf.org/doc/html/rfc2119) and the [OpenAI GPT-4.1 Prompting Guide](https://developers.openai.com/cookbook/examples/gpt4-1_prompting_guide): Markdown markup with headings, clear directive instructions with MUST/MUST NOT, no ALL CAPS tricks.
- The maximum vocabulary size is limited practically (100 entries as a testing reference), no hard limit is set.
- The interface of the new sections follows the existing design patterns of the application's settings.
- The order of sections in settings: General → Prompts → Hotkeys → Models (LLM) → Vocabularies → Personal Preferences → About → Advanced.
- The Personal Preferences text field stores text as plain text; Markdown markup is interpreted by the user while typing but is not rendered in WYSIWYG mode — the field works as a regular text editor.
- The vocabulary modal is reused for creation and editing; in edit mode the data is pre-filled and the buttons change to "Update"/"Delete".
