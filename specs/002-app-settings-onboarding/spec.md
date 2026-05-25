# Feature specification: App settings and onboarding

**Feature Branch**: `002-app-settings-onboarding`
**Created**: 2026-03-05
**Updated**: 2026-03-07
**Status**: Updated
**Description**: Expand the list of LLM models (GPT 5.1, 5.2, 5.3), visual improvements to the settings window, an onboarding window on first launch with permission requests (Accessibility and Microphone). Settings tabs reorganization: added "Hotkeys" and "LLM". Fixed size of the floating window, screen-center positioning.

## Context

The Verborra app is a native macOS Menu Bar application for voice text input. The current version (feature 001-voice-input) implements:
- A settings window with 3 tabs (General, Prompts, About) — this feature reorganizes the tabs
- Support for LLM models: gpt-4.1-nano, gpt-4o-mini, gpt-4.1-mini, gpt-5-nano
- Support for STT models: gpt-4o-mini-transcribe, gpt-4o-transcribe, whisper-1
- Storage of the API key in the Keychain, settings in UserDefaults, prompts in JSON
- Accessibility and Microphone permission checks in settings (no onboarding)
- No local processing — all work goes through the OpenAI API

## Clarifications

### Session 2026-03-05

- Q: API key in onboarding — add a separate screen, remove it entirely, or embed it in the completion screen? → A: Embed the API key field into the completion screen (screen 4) with the option to skip.
- Q: Renumber FR and SC consecutively after removing Apple Intelligence? → A: Yes, renumber FR-001..FR-016, SC-001..SC-005.

### Session 2026-03-05 (onboarding update)

- The onboarding window MUST be active and focused when it appears
- The onboarding window MUST be centered on the screen horizontally and vertically
- Navigation in onboarding MUST support moving forward and back ("Back" / "Next" buttons)
- The app MUST NOT request Keychain, Accessibility, Microphone permissions immediately at startup — all requests happen only when buttons in onboarding are pressed
- Until onboarding is complete, opening settings and the floating window is forbidden
- The onboarding completion status is persisted; on a subsequent launch the onboarding is not shown
- The settings have an "Advanced" section with an option to reset the onboarding status (requires restarting the app)
- Q: Can one move past the permissions screen without granting permissions? → A: The transition is allowed only when the Microphone permission is granted. Accessibility is not required for the transition. The screen shows text descriptions of the purpose of each permission.
- Q: Where in settings is the "Advanced" section located? → A: A new separate "Advanced" tab in the sidebar (the 4th tab). Total: General, Prompts, About, Advanced.
- Q: Is a confirmation required before resetting onboarding? → A: No, the reset happens immediately on button click, without a confirmation dialog. Only a notification about the need to restart is shown.

### Session 2026-03-07 (clarify)

- Q: Which hotkey is the default for recording start/stop? → A: Space — works only when the floating window is open, an intuitive pattern for recording
- Q: On which screen does the floating overlay appear with multiple monitors? → A: On the screen with the active window (key window)

### Session 2026-03-07 (settings and floating window reorganization)

- The settings sidebar MUST NOT have a collapse button. The button is removed
- The insets from the system buttons (red, yellow, green) MUST be correct — the first sidebar item must not overlap or impinge on the system window control buttons
- The settings window MUST support the system shortcuts: Command+Q (quit the app) and Command+W (close the settings window)
- The settings window MUST always have a visible close button (the system red button)
- A separate "Hotkeys" tab is added to the settings — the floating overlay invocation settings are moved here from General, a new setting is added for the recording start/stop hotkey
- A separate "LLM" tab is added to the settings — the audio transcription (STT model), ChatGPT (LLM model) and API key settings are moved here from General/Prompts
- New tabs structure: General, Prompts, Hotkeys, LLM, About, Advanced
- The floating overlay MUST appear at the horizontal center of the screen and at 10% from the bottom edge of the screen vertically
- The floating window MUST have a fixed size (width and height), not changeable by the user
- The controls (icons/buttons) in the floating window are moved to the bottom of the window

## User scenarios and testing *(required)*

### User Story 1 — Onboarding on first launch (Priority: P1)

The user installs the app and launches it for the first time. Instead of the usual Menu Bar interface, an onboarding welcome window appears, centered on the screen, active and focused. The window walks the user through 4 initial-setup screens step by step, with the ability to move forward and back. Until onboarding is complete, the user cannot open settings or the floating recording window. On subsequent launches (if onboarding has already been completed) the window is not shown.

The app does NOT request any permissions (Keychain, Accessibility, Microphone) immediately at startup. All permission requests happen only after the user presses buttons on the corresponding onboarding screen.

**Onboarding flow (4 screens)**:

1. **Welcome** — product description: what it is for and how it works. A brief explanation that the app lets you dictate text by voice and paste it into any application.
2. **Permissions (Accessibility and Microphone)** — both permission statuses are shown on a single screen. Access checking is performed automatically in the background, without invoking the grant request. The current statuses are displayed (granted / not granted). If access is not granted — the "Request access" button is enabled and, on press, calls the system request for the corresponding permission. If access is already granted — the button is disabled, the status shows "granted".
   - **Microphone description**: "Microphone access is needed so you can speak and get text from that"
   - **Accessibility description**: "Accessibility access is needed to automatically paste text into apps. Without this permission only copy-paste is available. You can grant access later in the app settings"
   - **Condition for moving to the next screen**: the "Next" button is active only after the Microphone permission is granted. The Accessibility permission is not required for the transition — the user can continue without it.
3. **Microphone test** — a voice activity indicator (waveform / sound level) is displayed so that the user can verify the microphone is actually working and configured correctly.
4. **Completion** — a thank-you for the user. The OpenAI API key input field is displayed with an option to skip (the "Skip" / "Later" button). The current setting of the global hotkey for invoking the floating recording window is displayed (default value). The user sees which key combination invokes the application.

**Navigation**: On each screen (except the first) there is a "Back" button to return to the previous screen. On each screen (except the last) there is a "Next" button to move to the next screen. On the last screen there is a "Finish" button.

**Why this priority**: Without proper permissions the app cannot perform its primary functions (voice recording and text insertion). Onboarding significantly lowers the barrier to entry and reduces errors on first use.

**Independent Test**: Can be tested by removing the first-launch flag and restarting the app — the onboarding window should appear and walk through all 4 screens.

**Acceptance Scenarios**:

1. **Given** the app is launched for the first time (no completed-onboarding flag), **When** the app starts, **Then** the onboarding window is displayed with the welcome screen, the window is active, focused and centered horizontally and vertically on the screen
2. **Given** the app is launched for the first time, **When** the app starts, **Then** NO automatic permission requests (Keychain, Accessibility, Microphone) happen — requests only on button press
3. **Given** onboarding is not complete, **When** the user tries to open settings, **Then** the action is blocked, settings do not open
4. **Given** onboarding is not complete, **When** the user tries to activate the floating recording window (via hotkey or menu), **Then** the action is blocked, the floating window does not open
5. **Given** the user is on the welcome screen, **When** they press "Next", **Then** they move to the permissions screen
6. **Given** the user is on the permissions screen, **When** they press "Back", **Then** they return to the welcome screen
7. **Given** the user is on the permissions screen, **When** the screen loads, **Then** the Accessibility and Microphone statuses are checked automatically in the background and displayed on a single screen (granted / not granted)
8. **Given** the Accessibility permission is not granted, **When** the user presses the "Request access" button for Accessibility, **Then** the system invokes the permission request, after granting the status updates to "granted", the button becomes disabled
9. **Given** the Microphone permission is not granted (status `.notDetermined`), **When** the user presses the "Request access" button for the microphone, **Then** the system invokes the permission request, after granting the status updates to "granted", the button becomes disabled
9a. **Given** the Microphone permission was previously denied (status `.denied`/`.restricted`), **When** the user presses the "Request access" button for the microphone, **Then** System Settings → Privacy & Security → Microphone opens, where the user can enable the permission manually
10. **Given** the permission is already granted, **When** the permissions screen loads, **Then** the corresponding button is disabled, the status shows "granted"
10a. **Given** the Microphone permission is not granted, **When** the user is on the permissions screen, **Then** the "Next" button is disabled
10b. **Given** the Microphone permission is granted but Accessibility is not, **When** the user is on the permissions screen, **Then** the "Next" button is active, the user can continue without Accessibility
10c. **Given** the user is on the permissions screen, **When** the screen loads, **Then** next to each permission a text description is displayed explaining why it is needed
11. **Given** the user is on the microphone test screen, **When** the user speaks into the microphone, **Then** the voice activity indicator reacts to the sound, confirming that the microphone works
12. **Given** the user is on the completion screen, **When** the screen loads, **Then** a thank-you, the API key input field (with an option to skip) and the current global hotkey setting (default value) are displayed
12a. **Given** the user is on the completion screen, **When** they enter an API key and press "Save", **Then** the key is verified, the result is displayed, the key is saved to the Keychain
12b. **Given** the user is on the completion screen, **When** they press "Skip" without entering an API key, **Then** the onboarding finishes without saving a key
13. **Given** the user presses the "Finish" button on the last screen, **When** onboarding finishes, **Then** the window closes, the onboarding completion status is saved, the app switches to normal operation (settings and floating window become available)
14. **Given** onboarding has already been completed (status saved), **When** the app is launched again, **Then** onboarding is not shown, the app starts in normal mode

---

### User Story 2 — Adding new GPT 5.x LLM models (Priority: P1)

The user opens the app settings and, in the "LLM" tab, sees an updated list of LLM models including the new GPT 5.1, GPT 5.2, GPT 5.3 models. Each model has a description with information about its capabilities and pricing. The user can choose any of the new models for text processing after recognition.

**Why this priority**: New models provide higher-quality text processing. Users should have access to up-to-date models.

**Independent Test**: Open settings, the "LLM" tab, verify that GPT 5.1, 5.2, 5.3 are present in the processing models dropdown.

**Acceptance Scenarios**:

1. **Given** the user opens settings, **When** they switch to the "LLM" tab and open the LLM model list, **Then** the list displays the GPT 5.1, GPT 5.2, GPT 5.3 models alongside the existing ones
2. **Given** the user hovers over the information icon next to a new model, **When** the popover appears, **Then** the model description, capabilities and pricing are displayed
3. **Given** the user selected GPT 5.1 (or 5.2, 5.3), **When** they perform a voice recording and send it for processing, **Then** the text is processed by the selected model and the result is displayed correctly

---

### User Story 3 — Visual improvements of the settings window (Priority: P2)

The user opens the settings window and sees an updated, tidier and more spacious interface. The settings window has been enlarged so that all elements of each tab fit fully on the screen without scrolling.

The left navigation menu (sidebar) is static — it is always visible, cannot be collapsed, the sidebar collapse button is absent. The insets from the system window control buttons (red, yellow, green) are correct — the first sidebar item does not overlap or impinge on the buttons, the layout is visually correct.

The settings window MUST support standard macOS shortcuts: Command+Q to quit the app, Command+W to close the settings window. The system window close button (red) MUST always be visible and active.

The new sidebar tab structure: **General**, **Prompts**, **Hotkeys**, **LLM**, **About**, **Advanced**.

Insets, element alignment, grouping of related settings, and visual hierarchy are improved. The settings look like a standard macOS app, following the Apple Human Interface Guidelines.

**Why this priority**: The visual quality of the settings affects the perception of the app as a whole. A tidy UI builds user trust. The absence of scrolling and persistently visible navigation provide convenience and quick access to all settings.

**Independent Test**: Open each settings tab and visually verify that all elements are visible without scrolling, the left menu does not collapse, the collapse button is absent, the insets from the system buttons are correct, Command+Q and Command+W work.

**Acceptance Scenarios**:

1. **Given** the user opens the settings window, **When** the window is displayed, **Then** the window size is sufficient to display all elements of any tab without scroll regions
2. **Given** the user opens the settings window, **When** they look at the left navigation panel (sidebar), **Then** the sidebar is always visible, static, the collapse button is absent
3. **Given** the user opens the settings window, **When** they look at the top of the sidebar, **Then** the first navigation item has a sufficient inset from the system buttons (red, yellow, green) and does not overlap them
4. **Given** the user is in the settings window, **When** they press Command+W, **Then** the settings window closes
5. **Given** the user is in the settings window, **When** they press Command+Q, **Then** the app quits
6. **Given** the user opens the settings window, **When** they look at the window control buttons, **Then** the close button (red) is always visible and active
7. **Given** the user opens the settings window, **When** they look at the sidebar, **Then** the sidebar displays 6 tabs: General, Prompts, Hotkeys, LLM, About, Advanced
8. **Given** the user opens the General tab, **When** they inspect the interface, **Then** all elements (Recording, Permissions, Launch) are fully visible without scrolling, grouped into sections with clear headings
9. **Given** the user opens the Prompts tab, **When** they inspect the interface, **Then** the prompt list and settings are fully visible without scrolling, visually separated, the controls are aligned
10. **Given** the user opens the About tab, **When** they inspect the interface, **Then** the information is structured, the links and app version are easy to read, all content is visible without scrolling
11. **Given** the user tries to shrink the settings window, **When** the size reaches the minimum, **Then** the window does not shrink below the minimum size at which all elements remain visible

---

### User Story 5 — "Hotkeys" tab in settings (Priority: P2)

The user opens the app settings and switches to the "Hotkeys" tab. All keyboard shortcut settings for the app are collected here:

1. **Floating overlay invocation hotkey** — moved from the General tab. The user can change the global key combination for opening/closing the floating recording window.
2. **Recording start/stop hotkey** — a new setting (default: Space). The user can set the key combination to start and stop voice recording (when the floating window is already open).

**Why this priority**: Grouping all hotkey settings in one place improves navigation. The ability to customize the recording hotkey increases usability.

**Independent Test**: Open settings → "Hotkeys" → verify the presence of two hotkey settings, change each one and confirm that the new combinations work.

**Acceptance Scenarios**:

1. **Given** the user opens settings, **When** they switch to the "Hotkeys" tab, **Then** they see the overlay invocation hotkey setting and the recording start/stop hotkey setting
2. **Given** the user is in the "Hotkeys" tab, **When** they change the overlay invocation hotkey, **Then** the new key combination is saved and works globally
3. **Given** the user is in the "Hotkeys" tab, **When** they change the recording start/stop hotkey, **Then** the new key combination is saved and used during recording
4. **Given** the user changed the overlay invocation hotkey, **When** they press the new key combination in any app, **Then** the floating overlay opens/closes
5. **Given** the floating window is open, **When** the user presses the recording start/stop hotkey, **Then** recording starts or stops
6. **Given** the overlay invocation hotkey setting has been moved to the "Hotkeys" tab, **When** the user opens the General tab, **Then** there is NO overlay invocation hotkey setting in the General tab

---

### User Story 6 — "LLM" tab in settings (Priority: P2)

The user opens the app settings and switches to the "LLM" tab. All settings related to models and the API are collected here:

1. **OpenAI API key** — moved from the General tab. Field for entering and saving the key.
2. **Transcription model (STT)** — moved from the General/Prompts tab. Speech recognition model selection (whisper-1, gpt-4o-transcribe, etc.).
3. **Text processing model (ChatGPT/LLM)** — moved from the Prompts tab. Model selection for processing the recognized text (GPT 5.1, 5.2, 5.3, etc.).

**Why this priority**: Grouping LLM settings in one place is logical and convenient. The user can quickly find all settings related to AI models and the API.

**Independent Test**: Open settings → "LLM" → verify the presence of the API key field, STT model and LLM model selection. Change each parameter and confirm that the changes apply.

**Acceptance Scenarios**:

1. **Given** the user opens settings, **When** they switch to the "LLM" tab, **Then** they see the API key field, the transcription model (STT) selection and the text processing model (LLM) selection
2. **Given** the user is in the "LLM" tab, **When** they enter an API key and save, **Then** the key is saved to the Keychain and used for requests
3. **Given** the user is in the "LLM" tab, **When** they select another transcription model, **Then** the selected model is saved and used for subsequent recordings
4. **Given** the user is in the "LLM" tab, **When** they select another LLM model, **Then** the selected model is saved and used for text processing
5. **Given** the API key and model settings have been moved to the "LLM" tab, **When** the user opens the General and Prompts tabs, **Then** the API key, STT model and LLM model settings are NOT in those tabs

---

### User Story 7 — Positioning and fixed size of the floating window (Priority: P2)

The floating overlay (the recording window) MUST appear strictly at the horizontal center of the screen and at the level of 10% from the bottom edge of the screen vertically. The window size is fixed — the width and height cannot be changed by the user (the window is not resizable).

The controls (settings, buttons) in the floating window have been moved to the bottom of the window for more convenient access and visual hierarchy.

**Why this priority**: Fixed positioning provides predictable app behavior. Bottom placement of controls is closer to the user's focus area. Horizontal centering is the standard pattern for overlays.

**Independent Test**: Invoke the floating window by hotkey → check position (horizontal center, 10% from the bottom), check the fixed size (cannot be changed), check that the controls are at the bottom.

**Acceptance Scenarios**:

1. **Given** the user invokes the floating overlay, **When** the overlay appears, **Then** it is positioned at the horizontal center of the screen
2. **Given** the user invokes the floating overlay, **When** the overlay appears, **Then** it is positioned at 10% from the bottom edge of the screen vertically
3. **Given** the floating overlay is shown, **When** the user tries to resize it (by dragging its edges), **Then** the window size does not change — width and height are fixed
4. **Given** the floating overlay is shown, **When** the user looks at the placement of the controls, **Then** the settings and buttons are placed at the bottom of the window
5. **Given** the user invokes the overlay on screens of different sizes/resolutions, **When** the overlay appears, **Then** the positioning (horizontal center, 10% from the bottom) is correct on any screen
6. **Given** the user works with multiple monitors, **When** they invoke the floating overlay, **Then** the overlay appears on the screen with the active window (key window)

---

### User Story 4 — Reset onboarding in settings (Priority: P3)

The user opens the app settings, switches to the separate "Advanced" tab in the sidebar and sees the "Reset onboarding" option. On click, the onboarding completion status is removed, and the user is shown a message about the need to restart the app. After the restart the onboarding is shown again.

**Why this priority**: The ability to reset onboarding is necessary for debugging, testing and situations where the user wants to go through setup again.

**Independent Test**: Open settings → "Advanced" → press "Reset onboarding" → restart the app → verify that onboarding is shown again.

**Acceptance Scenarios**:

1. **Given** the user opens settings, **When** they switch to the "Advanced" tab in the sidebar, **Then** they see the "Reset onboarding" option
2. **Given** the user presses "Reset onboarding", **When** the button is pressed, **Then** the onboarding completion status is removed immediately (without a confirmation dialog) and a notification about the need to restart the app is displayed
3. **Given** the onboarding status has been reset, **When** the user restarts the app, **Then** the onboarding window appears again, as on first launch

---

### Edge Cases

- What happens if the user closes the onboarding window (via the close button or Cmd+W)? — The onboarding window cannot be closed until completion: the close button is absent or disabled, Cmd+W does not work
- What happens if the user presses the recording hotkey during onboarding? — The action is blocked, the floating window does not open
- What happens if the user tries to open settings via the menu during onboarding? — The settings menu item is disabled until onboarding is complete
- What happens if the user selected a GPT 5.x model but the API does not support it (server error)? — Show an error message suggesting to choose another model
- What happens if the user skipped the API key entry in onboarding and tries to use the app? — Show an error with a suggestion to open settings and enter the API key. The "Open settings" button in the floating window MUST close the overlay and open the Settings window on top of all windows with a Dock icon
- What happens if the user resets onboarding but does not restart the app? — The app keeps running in the current mode, onboarding is shown only after a restart
- What happens with the "Settings" menu item after onboarding completion? — The menu item should become active immediately after onboarding completion (without restart). Reactivity is provided via `@Observable` tracking on `isOnboardingCompleted`
- What happens if the user assigns the same hotkey for the overlay and recording? — The system MUST warn about the conflict and not save a duplicate hotkey
- What happens if the floating window is invoked on a screen smaller than usual? — The window is positioned by the same rule (horizontal center, 10% from the bottom); if the window does not fit — it remains within the visible area of the screen

## Requirements *(required)*

### Functional requirements

#### Onboarding

- **FR-001**: The system MUST show the onboarding window on the app's first launch (if the onboarding completion status is not saved)
- **FR-002**: The onboarding window MUST be active, focused and centered horizontally and vertically on the screen
- **FR-003**: The onboarding window MUST include 4 screens: (1) welcome with the product description, (2) Accessibility and Microphone statuses and requests on a single screen, (3) microphone test with a voice activity indicator, (4) completion with the API key field and default hotkey display
- **FR-004**: Onboarding MUST support forward ("Next" button) and backward ("Back" button) navigation between screens
- **FR-005**: Until onboarding is complete, the system MUST block opening the settings window and the floating recording window
- **FR-006**: The app MUST NOT request permissions (Keychain, Accessibility, Microphone) automatically at startup — all permission requests happen strictly after the user presses the corresponding buttons in onboarding, settings or when attempting to record from the floating window
- **FR-007**: On the permissions screen, the Accessibility and Microphone status checks MUST be performed automatically in the background on screen load, without invoking the grant request
- **FR-008**: The access request button MUST be active only if the corresponding permission is not granted, and disabled if the permission is already granted. If the Microphone permission was previously denied (`.denied`/`.restricted`), the button MUST open System Settings → Privacy & Security → Microphone (macOS does not allow showing the system dialog again)
- **FR-008a**: On the permissions screen text descriptions MUST be shown: for Microphone — why microphone access is needed (speech to text recognition), for Accessibility — why access is needed (auto text insertion; without it only copy-paste is available; can be granted later in settings)
- **FR-008b**: The "Next" button on the permissions screen MUST be active only after the Microphone permission is granted. The Accessibility permission is NOT required for the transition
- **FR-009**: On the microphone test screen a visual voice activity indicator MUST be displayed, reacting to sound in real time
- **FR-010**: On the completion screen the current setting of the global hotkey for invoking the floating recording window MUST be displayed
- **FR-011**: On the onboarding completion screen there MUST be an OpenAI API key input field with the option to skip (the "Skip" / "Later" button)
- **FR-011a**: When entering the API key on the completion screen the key MUST be verified (a test request to the API) with the result displayed
- **FR-012**: The system MUST save the onboarding completion status after completion and MUST NOT show the onboarding window on subsequent launches
- **FR-013**: The onboarding window MUST NOT allow closing before completion (the close button is disabled, Cmd+W does not work)

#### Settings — general

- **FR-014**: The settings window MUST contain 6 tabs in the sidebar: General, Prompts, Hotkeys, LLM, About, Advanced
- **FR-015**: The left navigation menu (sidebar) MUST be static — always visible, the sidebar collapse button MUST be absent. The sidebar width is fixed: 210px
- **FR-016**: The insets from the system window control buttons (red, yellow, green) MUST be correct — the first sidebar item does not overlap the system buttons
- **FR-017**: The settings window MUST support the shortcuts: Command+Q (quit the app) and Command+W (close the settings window)
- **FR-018**: The settings window MUST always have a visible and active close button (the system red button)
- **FR-019**: The settings MUST be visually improved: element grouping, insets, alignment per the Apple HIG
- **FR-020**: The settings window MUST be enlarged so that all elements of each tab fit fully without scroll regions
- **FR-021**: The settings window MUST NOT have vertical or horizontal scrolling — all elements must be visible immediately
- **FR-022**: The settings window MUST have a minimum size that guarantees all elements are shown without clipping

#### Settings — "Hotkeys" tab

- **FR-023**: The "Hotkeys" tab MUST contain the global hotkey setting for invoking/hiding the floating overlay (moved from General)
- **FR-024**: The "Hotkeys" tab MUST contain the hotkey setting for starting and stopping recording (default: Space, works only when the floating window is open)
- **FR-025**: The system MUST warn about a conflict when an attempt is made to assign the same hotkey to different actions

#### Settings — "LLM" tab

- **FR-026**: The "LLM" tab MUST contain the OpenAI API key input and save field (moved from General)
- **FR-027**: The "LLM" tab MUST contain the audio transcription (STT) model selection — moved from General/Prompts
- **FR-028**: The "LLM" tab MUST contain the text processing model (ChatGPT/LLM) selection — moved from Prompts
- **FR-029**: The system MUST support the GPT 5.1, GPT 5.2, GPT 5.3 LLM models in addition to the existing models
- **FR-030**: Each model MUST have a description with information about its capabilities and pricing

#### Settings — "Advanced" tab

- **FR-031**: The "Advanced" tab MUST have a "Reset onboarding" option
- **FR-032**: When the "Reset onboarding" button is pressed, the saved completion status MUST be removed immediately (without a confirmation dialog) and a notification about the need to restart the app MUST be displayed

#### Floating overlay

- **FR-033**: The floating overlay MUST appear at the horizontal center of the screen and at 10% from the bottom edge of the screen vertically. With multiple monitors — on the screen with the active window (key window)
- **FR-034**: The floating window MUST be of a fixed size in width and height — the user CANNOT change the window size
- **FR-035**: The controls (settings, buttons) in the floating window MUST be placed at the bottom of the window

#### Permissions and security

- **FR-036**: In settings the Accessibility and Microphone status checks MUST be performed automatically in the background (without invoking the system grant dialogs). Permission requests — only on press of the "Request" button
- **FR-037**: The app MUST run without App Sandbox (`com.apple.security.app-sandbox = false`), since the Accessibility API (`AXIsProcessTrusted`, CGEvent) is incompatible with the sandbox. Distribution — direct download, not Mac App Store
- **FR-038**: KeychainService MUST NOT use `kSecUseDataProtectionKeychain`, since the Data Protection Keychain is incompatible with the disabled App Sandbox. The standard legacy macOS Keychain MUST be used

### Key entities

- **OnboardingState**: Onboarding progression state — current step, completion status, granted permissions
- **OnboardingCompletionFlag**: Onboarding completion flag, saved to UserDefaults — determines whether to show the window at startup
- **LLMModel** (extension): Existing model enumeration, extended with GPT 5.1, 5.2, 5.3
- **HotkeySettings**: Hotkey settings — the overlay invocation hotkey and the recording hotkey

## Success criteria *(required)*

### Measurable outcomes

- **SC-001**: 90% of new users successfully complete onboarding on the first try without referring to documentation
- **SC-002**: Time to walk through onboarding from launch to ready-to-work — no more than 2 minutes
- **SC-003**: All permissions (Accessibility and Microphone) are requested only on button press, not automatically at startup
- **SC-004**: The user can freely move between onboarding screens forward and back
- **SC-005**: The user can select and use any of the new GPT 5.x models for text processing
- **SC-006**: The visual quality of the settings meets the Apple Human Interface Guidelines — elements are aligned, grouped, with correct insets, all elements visible without scrolling, the sidebar is always in place, the sidebar collapse button is absent
- **SC-007**: The user can reset the onboarding via the "Advanced" section in settings and, after a restart, go through it again
- **SC-008**: The user can set the overlay invocation hotkey and the recording hotkey in the "Hotkeys" tab, both work correctly
- **SC-009**: All LLM settings (API key, STT model, LLM model) are available in a single "LLM" tab
- **SC-010**: The floating overlay always appears at the horizontal center of the screen and at 10% from the bottom edge, has a fixed size
- **SC-011**: The settings window supports Command+Q and Command+W, the close button is always visible

## Assumptions

- The GPT 5.1, 5.2, 5.3 models are available via the OpenAI API and are compatible with the current request format (Chat Completions API)
- The pricing and parameters of the new GPT 5.x models will be clarified at the planning stage (exact API identifiers and prices are determined in research.md)
- The onboarding completion status is stored in UserDefaults (a simple boolean flag)
- The current onboarding step is NOT persisted between launches — for an incomplete onboarding it starts from the first screen
- The recording start/stop hotkey works only when the floating window is open (it is not a global system shortcut)
- When moving settings between tabs (API key from General to LLM, hotkey from General to "Hotkeys") the data is preserved — the user does not lose previously entered values
- The floating window positioning (10% from the bottom) is computed from the visible area of the screen (excluding the Dock and Menu Bar)
