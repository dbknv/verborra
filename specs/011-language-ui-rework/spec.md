# Feature Specification: Language Selection UI Rework

**Feature Branch**: `011-language-ui-rework`
**Created**: 2026-03-21
**Status**: Draft
**Input**: Rework language handling in the frontend: simplification of the floating window, renaming language fields, adding tooltips to language settings, localizing language names into the interface language, displaying Global Shortcut on the Start-Stop button

## User Scenarios and Testing *(required)*

### User Story 1 — Simplified Recording Floating Window (Priority: P1)

The user opens the floating window to record a voice message. The window displays only one language selector — the text output language (Text Language). The voice input language selector (Voice Language) has been removed from the floating window, because the LLM model automatically recognizes the language of the audio stream. To switch the text output language, the user presses the "2" key (previously "3").

**Why this priority**: Simplifying the main working interface is a key UX improvement. A redundant control that confuses the user is removed.

**Independent test**: Open the floating window, make sure that only one language selector (Text Language) is displayed, verify switching with the "2" key.

**Acceptance Scenarios**:

1. **Given** the floating window is open in the preProcessing phase, **When** the user looks at the control bar, **Then** only one language selector — Text Language — is displayed
2. **Given** the floating window is open in the preProcessing phase, **When** the user presses the "2" key, **Then** the text output language switches to the next one in the list
3. **Given** the floating window is open in the preProcessing phase, **When** the user presses the "3" key, **Then** nothing happens (the hotkey is not assigned)
4. **Given** the floating window is open in the postProcessing phase, **When** the user looks at the control bar, **Then** the language selector is displayed but inactive

---

### User Story 2 — Tooltips for Language Settings (Priority: P2)

The user opens the application settings, Models → Languages section. Next to the "Your Language" field (new name, see User Story 4), a question-mark icon (?) is displayed. When the user interacts with it, an explanation appears: this is your primary language, the one you most often speak in when recording. Choose the language you use for the majority of voice messages. The LLM model can also recognize other languages, but specifying the primary one improves recognition quality.

Next to the "Response Language" field (new name), a similar question-mark icon is displayed with an explanation: the LLM model will produce the text response in the selected language. Even if you recorded the message in a different language (for example, in Russian), the model will translate the result into the language specified here (for example, into English).

**Why this priority**: Users do not always understand the difference between the two language settings. Tooltips combined with clear field names reduce cognitive load and decrease setup errors.

**Independent test**: Open Models → Languages settings, verify the presence of question-mark icons next to both fields, ensure that the tooltips contain correct text consistent with the new names.

**Acceptance Scenarios**:

1. **Given** the user is in Models → Languages settings, **When** they see the "Your Language" field, **Then** a question-mark icon is displayed next to it
2. **Given** the user sees the question-mark icon next to "Your Language", **When** they interact with it (hover or click), **Then** a tooltip appears explaining that this is the primary language the user speaks in, and that the LLM can also recognize other languages
3. **Given** the user is in Models → Languages settings, **When** they see the "Response Language" field, **Then** a question-mark icon is displayed next to it
4. **Given** the user sees the question-mark icon next to "Response Language", **When** they interact with it, **Then** a tooltip appears explaining that the LLM produces the response in this language and will translate from the recording language if necessary
5. **Given** the interface is in Russian, **When** the user opens the tooltip, **Then** the tooltip text is displayed in Russian
6. **Given** the interface is in English, **When** the user opens the tooltip, **Then** the tooltip text is displayed in English

---

### User Story 3 — Language Names in the Interface Language (Priority: P2)

The user selects a language (Voice Language or Text Language) in settings or in the floating window. All language names in dropdown lists are displayed in the current application interface language. If the interface is in Russian — all languages are labeled in Russian (Russian names for English, Spanish, French, etc.). If the interface is in English — in English (English, Spanish, French, etc.). Languages are NOT displayed in their original language (e.g., not "Español", but the Russian name or "Spanish").

This change does NOT affect the interface language selection setting (Interface Language) — there languages continue to be displayed as before.

**Why this priority**: Uniform display of languages improves readability and makes the interface more predictable. The user does not need to know how a language is written in the original.

**Independent test**: Switch the interface language to Russian/English, open the Voice Language and Text Language lists — all names must be in the interface language.

**Acceptance Scenarios**:

1. **Given** the interface language is Russian, **When** the user opens the Voice Language list in settings, **Then** all languages are displayed in Russian (Russian names for: English, Russian, Spanish, French, German, Portuguese, Chinese, Japanese, Korean, Italian)
2. **Given** the interface language is English, **When** the user opens the Voice Language list in settings, **Then** all languages are displayed in English (English, Russian, Spanish, French, German, Portuguese, Chinese, Japanese, Korean, Italian)
3. **Given** the interface language is Russian, **When** the user opens the Text Language list in settings, **Then** all languages are displayed in Russian
4. **Given** the interface language is English, **When** the user opens the Text Language list in the floating window, **Then** all languages are displayed in English
5. **Given** any interface language, **When** the user opens the Interface Language setting, **Then** language names are displayed as before (not affected by the changes)
6. **Given** the user switched the interface language from Russian to English, **When** they open any language list (Voice/Text), **Then** language names are immediately displayed in English

---

### User Story 4 — Renaming Language Fields in Settings (Priority: P1)

The user opens Models → Languages settings. Instead of the technical names "Voice Language" and "Text Language", they see more understandable names:

- The former "Voice Language" is now called "Your Language" — this is the language the user predominantly speaks in when recording
- The former "Text Language" is now called "Response Language" — this is the language the LLM model will produce the text response in, translating from the recording language if necessary

A similar renaming applies to the selector in the floating window: instead of "Text Language", "Response Language" is displayed.

The new names make it obvious to the user: the first field — "which language I speak", the second — "which language to respond in". Tooltip texts must be consistent with the new field names and clearly explain the difference: "Your Language" — which language I speak, "Response Language" — which language to respond to me in.

**Why this priority**: Understandable names are a basic UX requirement. Without them, tooltips (User Story 2) are less effective, and the user may confuse the purpose of the fields.

**Independent test**: Open Models → Languages settings and the floating window, ensure that the new names are displayed in the current interface language.

**Acceptance Scenarios**:

1. **Given** the interface language is Russian, **When** the user opens Models → Languages settings, **Then** they see the fields "Your Language" and "Response Language" (localized into Russian)
2. **Given** the interface language is English, **When** the user opens Models → Languages settings, **Then** they see the fields "Your Language" and "Response Language"
3. **Given** the interface language is Russian, **When** the user opens the floating window, **Then** the language selector is labeled "Response Language" (localized into Russian)
4. **Given** the interface language is English, **When** the user opens the floating window, **Then** the language selector is labeled "Response Language"
5. **Given** any interface language, **When** the user opens the Interface Language setting, **Then** its name is not changed

---

### User Story 5 — Displaying Global Shortcut on the Start-Stop Button (Priority: P2)

There is a Start-Stop button in the recording floating window that starts and stops recording. The button contains three visual elements: an action icon, the action name text, and a shortcut container. This button must also trigger when the Global Shortcut is pressed (Option+Space by default).

The shortcut container inside the button must display the currently assigned Global Shortcut, where modifiers are shown as short symbolic icons (⌥, ⌘, ⇧, ⌃), separated only by a space — for example, "⌥ Space". With multiple modifiers: "⌥ ⌘ ⇧ Space". Between elements, "+" or other separator symbols are NOT used — only spaces. If the user changes the shortcut in the application settings, the contents of the shortcut container must automatically update and reflect the new key combination.

**Why this priority**: The user must see which shortcut activates recording, directly on the button. This lowers the entry threshold for new users and helps them remember the combination.

**Independent test**: Open the floating window, verify that the current Global Shortcut is displayed on the Start-Stop button. Change the shortcut in settings, reopen the floating window — the text must update.

**Acceptance Scenarios**:

1. **Given** the Global Shortcut is set as Option+Space (default), **When** the user opens the floating window, **Then** the Start-Stop button contains an action icon, action name, and a shortcut container with the text "⌥ Space" (modifiers as symbolic icons, separated by a space)
2. **Given** the user changed the Global Shortcut to a different combination (for example, Cmd+Shift+R), **When** they open the floating window, **Then** the shortcut container on the button displays the new combination "⌘ ⇧ R" (elements separated by spaces, without the "+" sign)
3. **Given** the floating window is open, **When** the user presses the Global Shortcut, **Then** recording starts or stops (the same as pressing the button)
4. **Given** the floating window is open in the preProcessing phase, **When** the user clicks the Start-Stop button with the mouse, **Then** recording starts
5. **Given** the floating window is open in the recording phase, **When** the user clicks the Start-Stop button with the mouse or the Global Shortcut, **Then** recording stops

---

### User Story 6 — Current Language in the Floating Window Button Title (Priority: P1)

The "Response Language" button in the recording floating window must display in its title the currently selected language — for example, "Russian" (in the interface language). When the "2" key is pressed (cyclic switching), the button title instantly updates and shows the newly selected language.

**Why this priority**: The user must see which response language is currently active, without having to open the dropdown menu. This is basic feedback.

**Independent test**: Open the floating window → the button shows the current language. Press "2" → the text on the button updates to the next language.

**Acceptance Scenarios**:

1. **Given** the response language is Russian, the interface language is Russian, **When** the user opens the floating window, **Then** the language button shows "Russian" (localized into Russian)
2. **Given** the response language is Russian, the interface language is English, **When** the user opens the floating window, **Then** the language button shows "Russian"
3. **Given** the floating window is open, **When** the user presses the "2" key, **Then** the button text instantly updates to the name of the next language in the list
4. **Given** the user selected a different language from the button's dropdown menu, **Then** the button text instantly updates to the selected language

---

### User Story 7 — Settings Sidebar Width (Priority: P2)

In the application settings window, the left navigation sidebar has a minimum and initial width of 220 pixels, so that all menu items fit without text truncation.

**Why this priority**: The current width may truncate long menu item names, degrading navigation.

**Independent test**: Open application settings → the left sidebar has a width of at least 220 pixels, all items are fully visible.

**Acceptance Scenarios**:

1. **Given** the user opens application settings, **When** the window is displayed, **Then** the left sidebar has an initial width of 220 pixels
2. **Given** the user tries to reduce the sidebar width, **When** they drag the separator to the left, **Then** the width cannot become less than 220 pixels
3. **Given** any interface language, **When** the user looks at the sidebar, **Then** all menu items are fully visible without truncation

---

### Edge Cases

- What happens when the user presses the "2" key in the floating window — Text Language is switched (new behavior), Voice Language is NOT affected
- What happens if Voice Language was previously selected in settings — the value is preserved and continues to be passed to the LLM model, it is simply not displayed in the floating window
- What happens when a new language is added in the future — its name must be defined for both interface languages (Russian and English)
- What happens if the interface language is switched while the floating window is open — language names in the selector are updated to the new interface language
- What happens if the Global Shortcut is changed while the floating window is open — the text on the button updates when the window is next opened
- What happens if the Global Shortcut is not assigned — the button displays text without shortcut symbols (for example, just "Start" / "Stop")

## Requirements *(required)*

### Functional Requirements

- **FR-001**: The system MUST display only one language selector in the recording floating window — Text Language (text output language)
- **FR-002**: The system MUST assign the "2" key for switching Text Language in the floating window (instead of the previous "3")
- **FR-003**: The system MUST NOT display the Voice Language selector in the recording floating window
- **FR-004**: The system MUST continue to use the Voice Language value from global settings when sending a request to the LLM model
- **FR-005**: The system MUST display a tooltip icon (?) next to the Voice Language field in Models → Languages settings
- **FR-006**: The Voice Language tooltip MUST contain text stating that it is a hint to the LLM model about the primary recording language, and that the model can also recognize other languages
- **FR-007**: The system MUST display a tooltip icon (?) next to the Text Language field in Models → Languages settings
- **FR-008**: The Text Language tooltip MUST contain text stating that the LLM model produces a response in the selected language and translates if necessary
- **FR-009**: Tooltip texts MUST be localized into both interface languages (Russian and English)
- **FR-010**: The system MUST display language names in the Voice Language and Text Language lists in the current application interface language
- **FR-011**: For the Russian interface, all languages MUST be displayed in Russian (Russian names for English, Russian, Spanish, etc.)
- **FR-012**: For the English interface, all languages MUST be displayed in English (English, Russian, Spanish, etc.)
- **FR-013**: The change MUST NOT affect the interface language selection (Interface Language) — there language names remain unchanged
- **FR-014**: Localization of language names MUST be applied both in settings and in the floating window
- **FR-015**: The "Voice Language" field in settings MUST be renamed to "Your Language" (localized into Russian and English)
- **FR-016**: The "Text Language" field in settings MUST be renamed to "Response Language" (localized into Russian and English)
- **FR-017**: The language selector in the floating window MUST use the new name "Response Language" (localized into Russian and English)
- **FR-018**: The renaming MUST NOT affect internal identifiers and settings storage keys — only the labels shown to the user change
- **FR-019**: The Start-Stop button in the floating window MUST contain an action icon, action name text, and a shortcut container, in which modifiers are displayed as symbolic icons (⌥, ⌘, ⇧, ⌃), separated only by a space (by default — "⌥ Space"). The "+" sign or other separator symbols are NOT used
- **FR-020**: The text on the Start-Stop button MUST automatically update when the Global Shortcut is changed in settings
- **FR-021**: Pressing the Global Shortcut while the floating window is open MUST start or stop recording (the same as pressing the button)
- **FR-022**: Tooltips (?) MUST be consistent with the new field names ("Your Language" / "Response Language") and clearly explain the difference between them
- **FR-023**: The "Response Language" button in the floating window MUST display the currently selected language in its title (for example, "Russian" — in the interface language)
- **FR-024**: When switching the language via the "2" hotkey or via the dropdown menu, the button text MUST instantly update and show the newly selected language
- **FR-025**: The minimum width of the left navigation sidebar in the settings window MUST be 220 pixels
- **FR-026**: The initial (default) width of the left navigation sidebar in the settings window MUST be 220 pixels

### Key Entities

- **Your Language** (formerly Voice Language): The language that hints to the LLM model about the user's primary audio recording language. Configured only in settings (globally). Not displayed in the floating window
- **Response Language** (formerly Text Language): The language of the LLM model's text output. Configured globally in settings and can be changed for a specific session in the floating window
- **Interface Language**: The application interface language (Russian or English). Determines in which language the language names in Voice/Text Language lists are shown. The Interface Language setting itself is not affected
- **Global Shortcut**: A global key combination for starting/stopping recording (Option+Space by default). Configured in application settings. A textual representation of the shortcut is displayed on the Start-Stop button in the floating window

## Clarifications

### Session 2026-03-21

- Q: What is the format of the text on the Start-Stop button? → A: The button contains an action icon + action name + shortcut container. Modifiers in the container are displayed as short symbolic icons, separated only by a space (for example, "⌥ Space", "⌥ ⌘ ⇧ Space"). The "+" sign is NOT used.

## Assumptions

- Voice Language continues to be passed to the LLM model as a hint, even though its selection has been removed from the floating window
- The set of supported languages (10 of them) remains the same
- The set of interface languages (Russian, English) remains the same
- Tooltip format — standard for macOS (popover or tooltip on hover/click of the "?" icon)

## Success Criteria *(required)*

### Measurable Outcomes

- **SC-001**: 100% of users see only one language selector in the floating window (Text Language), without a Voice Language selector
- **SC-002**: The "2" key switches Text Language in the floating window, the "3" key does not perform any action
- **SC-003**: 100% of language names in Voice Language and Text Language lists are displayed in the current interface language (not in the original language)
- **SC-004**: Tooltips (?) are present and contain correct text for both fields (Voice Language and Text Language) in settings
- **SC-005**: The Interface Language setting is not affected — visually and functionally identical to the current version
- **SC-006**: Voice Language continues to be correctly passed to the LLM model during recording, despite its absence in the floating window
- **SC-007**: Field names in settings and in the floating window correspond to the new names ("Your Language" / "Response Language", localized into the interface language) — the user does not see the technical terms Voice Language / Text Language
- **SC-008**: The current Global Shortcut is displayed on the Start-Stop button in the floating window, and it updates when the setting is changed
- **SC-009**: The language button in the floating window displays the name of the currently selected language; when switching, the text updates instantly
- **SC-010**: The left settings sidebar has a width of at least 220 pixels, all items are visible without truncation
