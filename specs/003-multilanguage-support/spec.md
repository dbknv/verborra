# Feature Specification: Interface Multilanguage Support

**Feature Branch**: `003-multilanguage-support`
**Created**: 2026-03-07
**Status**: Draft
**Input**: User description: "Multilanguage support in the application. Two interface languages: English and Russian. Translation of all texts into English. Detect language by OS, ability to change in settings, English by default when detection is not possible. System prompt 'Simple Voice To Text' with localized content and protection against deletion/editing."

## Clarifications

### Session 2026-03-07

- Q: Where in the settings is the interface language selection placed? → A: In the "General" tab, as a separate "Language" section at the very top
- Q: Should switching the language require an application restart? → A: No, instant switching without restart (custom localization manager)
- Q: How many languages are supported? → A: Two — English and Russian

### Session 2026-03-09

- Q: What is the default system prompt text? → A: "Fix speech recognition errors, add punctuation and capitalization. Break into paragraphs by meaning. Return only the corrected text." (localized into all supported languages)
- Q: What is the name of the system prompt? → A: "Simple Voice To Text" (translated into all languages)
- Q: Can the system prompt be deleted or edited? → A: No, system prompts are protected against deletion and editing
- Q: Will there be more system prompts? → A: Yes, other system prompts may appear in the future
- Q: Is a visual marker needed for system prompts? → A: Yes, visual indication in the list
- Q: Is the prompts window size sufficient? → A: It is necessary to verify and ensure correct display
- Q: Where are voice/text language stored — in the prompt or globally? → A: Global settings in the "Models" section. Applied to all prompts. The default system prompt uses the interface language
- Q: Migration of the old "Standard" prompt? → A: Always replace "Standard" with "Simple Voice To Text", regardless of user modifications

## User Scenarios and Testing

### User Story 1 — Automatic Interface Language Detection (Priority: P1)

A user installs the application for the first time. The application automatically detects the operating system language and displays the interface in the corresponding language. If the OS language is Russian, the interface is shown in Russian. Otherwise — in English.

**Why this priority**: This is a basic user expectation — the application should "speak" the user's language from the first launch. Without this, all other scenarios are meaningless.

**Independent test**: Can be fully tested by switching the macOS language and launching the application. The application must display the interface in the OS language (if Russian) or in English.

**Acceptance scenarios**:

1. **Given** macOS language = Russian, **When** the user launches the application for the first time, **Then** the entire interface (onboarding, settings, overlay) is displayed in Russian
2. **Given** macOS language = English, **When** the user launches the application for the first time, **Then** the interface is displayed in English
3. **Given** macOS language = Español (unsupported), **When** the user launches the application for the first time, **Then** the interface is displayed in English

---

### User Story 2 — Manual Interface Language Selection (Priority: P1)

A user wants to use the interface in a language different from the OS language. The user opens the application settings and selects the preferred interface language from the list of supported languages (English, Russian). The interface immediately switches to the selected language.

**Why this priority**: Equal to P1, since without manual switching the user would be "locked" into the auto-detected language. Often the OS language does not match the user's preference.

**Independent test**: Open settings, change the language, ensure all interface elements are translated.

**Acceptance scenarios**:

1. **Given** the interface is in English, **When** the user selects "Russian" in the language settings, **Then** all interface texts instantly switch to Russian
2. **Given** the user selected Russian, **When** they restart the application, **Then** the interface remains in Russian (setting is preserved)
3. **Given** the user selected Russian, **When** they open onboarding (via "Reset onboarding"), **Then** onboarding is displayed in Russian

---

### User Story 3 — Translation of All Existing Texts into English (Priority: P1)

All hardcoded Russian strings in the application code are moved into the localization system. English becomes the base language (development language). Russian becomes one of the supported languages.

**Why this priority**: This is the technical foundation for all other scenarios. Without extracting strings into the localization system, translations are impossible.

**Independent test**: Switch the language to English and ensure there are no Russian strings in the interface. Check all screens: onboarding, recording, result, settings (all tabs), overlay.

**Acceptance scenarios**:

1. **Given** interface language = English, **When** the user goes through all application screens, **Then** there is not a single string in Russian
2. **Given** interface language = Russian, **When** the user goes through all screens, **Then** the interface is entirely in Russian (as it is now)
3. **Given** the developer reviews the code, **When** searching for hardcoded Russian strings, **Then** all user-facing strings have been extracted into localization files

---

### User Story 4 — Recognition Languages Independent of Interface Language (Priority: P2)

The interface language and the recognition/output text languages (voice language, text language) are independent settings. These languages are global parameters located in the "Models" section of settings and are applied to all prompts uniformly. The user can use an English interface but recognize speech in Russian and receive text in English.

**Why this priority**: Important for international users who work in multiple languages. Global settings simplify management — no need to configure languages for each prompt separately.

**Independent test**: Set the interface to English, in the "Models" section select voice=ru, text=en. Record speech in Russian with any prompt, get text in English, while all UI elements remain in English.

**Acceptance scenarios**:

1. **Given** interface in English, voice=Russian, text=English in the "Models" section, **When** the user records speech in Russian with any prompt, **Then** the result is in English, and the UI remains in English
2. **Given** the user changes the interface language, **When** they check the voice/text language settings in the "Models" section, **Then** voice language and text language have not changed
3. **Given** voice=Français, text=English in global settings, **When** the user switches the prompt from "Simple Voice To Text" to a custom one, **Then** voice and text language remain the same (global)

---

### User Story 5 — Localized System Prompt "Simple Voice To Text" (Priority: P1)

The application contains a built-in system prompt "Simple Voice To Text" that is used by default for converting voice to text. The prompt content in English: "Fix speech recognition errors, add punctuation and capitalization. Break into paragraphs by meaning. Return only the corrected text." The prompt is translated into all supported interface languages (en, ru). When the interface language changes, the content and name of the system prompt automatically update to the corresponding language.

**Why this priority**: This is the main usage scenario — the user records speech and receives clean text. The prompt must work in the user's interface language from the first launch.

**Independent test**: Switch the interface language and check that the name and content of the system prompt are displayed in the selected language.

**Acceptance scenarios**:

1. **Given** interface language = English, **When** the user opens the prompts list, **Then** the system prompt is named "Simple Voice To Text" and its content is in English
2. **Given** interface language = Russian, **When** the user opens the prompts list, **Then** the system prompt is named with the Russian equivalent of "Simple Voice To Text" and its content is in Russian
3. **Given** the user changed the interface language from English to Russian, **When** they open the prompts list, **Then** the name and content of the system prompt have automatically updated to Russian

---

### User Story 6 — Protection of System Prompts from Editing and Deletion (Priority: P1)

System prompts (preinstalled by the developers) are protected from editing and deletion by the user. In the prompts list, they are visually distinct from user prompts. Delete and edit buttons are unavailable for system prompts. In the future, the list of system prompts may be expanded.

**Why this priority**: Without protection, the user could accidentally delete or modify the base prompt, which would lead to loss of core functionality.

**Independent test**: Select a system prompt in the list and ensure that the edit fields and delete button are unavailable.

**Acceptance scenarios**:

1. **Given** the user selected a system prompt, **When** they look at the edit form, **Then** all fields (name, content) are unavailable for modification
2. **Given** the user selected a system prompt, **When** they try to click the delete button, **Then** the button is disabled or hidden
3. **Given** the user looks at the prompts list, **When** there is a system prompt in the list, **Then** it is visually distinct from user prompts (icon, label, or other visual indication)
4. **Given** the user created their own prompt, **When** they select it, **Then** all fields are available for editing and deletion is allowed

---

### User Story 7 — Correct Display of the Prompts Window (Priority: P2)

The prompts settings window has sufficient dimensions for comfortable display of all components. The prompts list, edit fields, language dropdowns, and control buttons are not clipped and do not extend beyond the visible area.

**Why this priority**: P2, because functionally everything works, but an inconvenient interface reduces usability.

**Independent test**: Open the "Prompts" tab in settings, add several prompts with long names, and verify that everything is displayed correctly.

**Acceptance scenarios**:

1. **Given** the user opened the "Prompts" tab, **When** there are 10+ prompts in the list, **Then** the list scrolls, no item is clipped
2. **Given** a prompt with a long name (50+ characters), **When** it is displayed in the list, **Then** the name is truncated with ellipsis but does not break the layout
3. **Given** the user resizes the settings window, **When** the window shrinks to the minimum size, **Then** all components remain visible and functional

---

### Edge Cases

- What happens when the user changes the OS language while the application is running? — The application continues to work in the previously selected interface language. Auto-detection works only on the first launch (when the user has not yet manually selected a language). Test: change the OS language while the application is running with a previously selected language → the interface language has not changed.
- What happens if the localization file is corrupted or missing? — The application uses English as a fallback.
- What happens to existing user prompts after an update? — User prompts (created by the user) are not translated — they remain as-is. Only the interface is translated.
- What happens to the old "Standard" prompt on update? — It is always replaced by the new system prompt "Simple Voice To Text" with updated content, regardless of whether the user modified the old prompt.
- What happens if the user deleted all user prompts? — The system prompt remains and becomes the default active one. It cannot be deleted.
- What happens to the system prompt when a new interface language is added in the future? — Translations for the new language must be added to all system prompts.

### Session 2026-03-09 (bugfix)

- Q: Error -10868 (kAudioUnitErr_FormatNotSupported) when starting recording? → A: AVAudioEngine enters an invalid state after the audio device is changed/disconnected. engine.reset() does not restore the correct inputNode format. Solution: recreate AVAudioEngine on every recording start, with fallback to the system device on error
- Q: False "Microphone permission not granted" when permission is granted? → A: The entitlement com.apple.security.device.audio-input was missing. Without it, AVCaptureDevice.authorizationStatus(for: .audio) cannot correctly determine the permission status on macOS with Hardened Runtime. Also, requestAccess was called asynchronously without awaiting the result

## Requirements

### Functional Requirements

- **FR-001**: The system MUST support 2 interface languages: English (en) and Russian (ru)
- **FR-002**: The system MUST detect the interface language based on the preferred macOS language at first launch
- **FR-003**: The system MUST use English as the default language if the OS language is not Russian
- **FR-004**: The user MUST be able to select the interface language in the "General" tab of the settings
- **FR-005**: The interface language selection MUST be located in a separate "Language" section at the very top of the "General" tab
- **FR-006**: The system MUST persist the selected interface language across application restarts
- **FR-007**: The system MUST apply the new interface language immediately, without restarting the application (custom localization manager)
- **FR-008**: All hardcoded Russian strings MUST be extracted into localization files
- **FR-009**: English MUST be the base development language
- **FR-010**: The interface language and the recognition/output text languages (voice language, text language) MUST be independent settings
- **FR-010a**: Recognition language (voice language) and output text language (text language) MUST be global settings located in the "Models" section, rather than properties of each prompt
- **FR-010b**: Global voice/text languages MUST be applied to all prompts (both system and user) uniformly
- **FR-010c**: When switching prompts, the global voice/text language settings MUST NOT change
- **FR-011**: User prompts (created by the user) MUST NOT be translated when the interface language changes
- **FR-012**: The system MUST localize all screens: onboarding (Welcome, Permissions, MicrophoneTest, Completion), recording window (Recording, Result), settings (all 6 tabs)
- **FR-013**: Interface language display names MUST be shown in their native language (English, Russian shown in its native script) regardless of the current interface language
- **FR-014**: All interface texts MUST be written in an informational style — without word abbreviations, using full forms of terms
- **FR-015**: Abbreviations on first mention MUST be spelled out in full, with the short form allowed in parentheses
- **FR-016**: Russian localization MUST use clear Russian equivalents instead of jargon-style Anglicisms (for example, use the native Russian phrase for "shortcut" instead of a transliteration of "hotkey"; use the native phrase for "recording window" instead of a transliteration of "overlay")
- **FR-017**: The system MUST contain a built-in system prompt "Simple Voice To Text" with content: "Fix speech recognition errors, add punctuation and capitalization. Break into paragraphs by meaning. Return only the corrected text."
- **FR-018**: The name and content of the system prompt MUST be translated into all supported interface languages (en, ru) and into all supported text-processing languages (es, fr, de, pt, zh, ja, ko, it)
- **FR-019**: When the interface language changes, the name and content of the system prompt MUST automatically update to the corresponding language in the settings UI
- **FR-031**: When sending the system prompt to the LLM, the content MUST be dynamically resolved by the selected text language, not by the interface language. For user prompts, the saved content is used without modification
- **FR-020**: System prompts MUST be protected from deletion by the user
- **FR-021**: System prompts MUST be protected from editing by the user (all form fields are disabled)
- **FR-022**: System prompts MUST be visually distinct from user prompts in the prompts list (special icon or label)
- **FR-023**: The system MUST support extending the list of system prompts in the future (architectural readiness)
- **FR-024**: The settings window MUST have a minimum width of 980px and correctly display all components without clipping, including HSplitView prompts tab with maxWidth/maxHeight constraints
- **FR-025**: The system prompt "Simple Voice To Text" MUST be used as the default prompt at first application launch
- **FR-026**: The recording window MUST be positioned with a 5% offset from the bottom edge of the screen's visible area (OverlayPanel.positionOnScreen)
- **FR-027**: The system MUST recreate AVAudioEngine on every recording start to prevent error -10868 (kAudioUnitErr_FormatNotSupported)
- **FR-028**: On engine start failure with the selected device, the system MUST automatically switch to the default system audio device
- **FR-029**: The application MUST have the entitlement com.apple.security.device.audio-input for correct operation of AVCaptureDevice.authorizationStatus on macOS with Hardened Runtime
- **FR-030**: For a permission status of .notDetermined, the system MUST wait for the user's response (await requestAccess) before throwing an error

### Key Entities

- **UILanguage**: The user's preferred interface language. Persisted across sessions. Two values: en, ru
- **LocalizedString**: A translated interface string. Organized by modules (onboarding, settings, recording, result, common)
- **SupportedLanguage**: Existing entity for speech recognition languages. Not changed. The set of UILanguage values is a subset of SupportedLanguage
- **SystemPrompt**: Prompt for text processing. Contains name, content, "default" flag, and "system" (isSystem) flag. The voice/text languages are NOT stored in the prompt — they are global settings. System prompts differ in that their name and content are localized, and the user cannot edit or delete them
- **VoiceTextLanguageSettings**: Global settings for recognition language (voice language) and output text language (text language). Located in the "Models" section of settings. Applied to all prompts

## Success Criteria

### Measurable Outcomes

- **SC-001**: The user sees the interface in their language from the first launch without additional actions
- **SC-002**: Switching the interface language takes no more than 2 actions (open settings -> select language)
- **SC-003**: 100% of user-facing interface strings are translated into both supported languages (English and Russian)
- **SC-004**: Changing the interface language does not affect speech recognition settings or user prompts
- **SC-005**: When switching the language, all visible interface elements update instantly (without noticeable delay)
- **SC-006**: The system prompt "Simple Voice To Text" is available in all supported languages (en, ru, es, fr, de, pt, zh, ja, ko, it). In the UI it switches when the interface language changes; for text processing, it follows the text language
- **SC-007**: The user cannot accidentally delete or modify the system prompt — controls are disabled
- **SC-008**: All components of the "Prompts" tab are displayed correctly at the minimum settings window size

## Assumptions

- Only two interface languages are supported: English and Russian
- For localization, the standard Apple mechanism is used — String Catalogs (.xcstrings) or Localizable.strings
- The quality of the Russian translation must be at native-speaker level (original strings from the current code)
- Technical terms (API, OpenAI, LLM, STT, Accessibility, Markdown) are not translated
- The application menu in the macOS menu bar is also localized (two items: "Settings..." and "Quit")
- Additional interface languages may be added in the future but are not within the current scope
- The content of system prompts is stored in the application code (hardcoded), not in localization files, and is switched programmatically when the language changes
- The system prompt "Simple Voice To Text" replaces the former "Standard" prompt
- In the future, other system prompts may be added (the architecture must support this)
- Voice language and text language migrate from prompt properties (SystemPrompt.voiceLanguage, SystemPrompt.textLanguage) to global settings in the "Models" section. During migration, values from the default prompt are used. For new users (without migration), the default value is `.ru` (compatibility with current application behavior)
- All interface texts MUST be written in an informational style: without word abbreviations (for example, "Maximum duration" instead of "Max. duration", "seconds" instead of "sec", "By default" instead of "Def.")
- If abbreviations are used in the text, on first mention they MUST be spelled out in full with the short form in parentheses (for example, "Speech-to-text (STT)")
- Jargon and English-language terms in Russian localization MUST be replaced with clear Russian equivalents (for example, use the native Russian phrase for "shortcut" instead of a transliteration of "hotkey"; use the native phrase for "recording window" instead of a transliteration of "overlay")
- Error texts MUST be concise — only the essence of the problem, without instructions on how to fix it (for example, "OpenAI API key is not configured" instead of "OpenAI API key is not configured. Set it in settings.")
- Recording window positioning is defined in FR-026
