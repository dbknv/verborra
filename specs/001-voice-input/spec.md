# Feature Specification: Voice Text Input

**Feature Branch**: `001-voice-input`
**Created**: 2026-03-04
**Status**: Draft
**Description**: Voice text input via global hotkey
with overlay window, speech recognition, and insertion into the active field.

## Clarifications

### Session 2026-03-05

- Q: The settings window does not receive keyboard focus — text cannot be typed? → A: A Menu Bar app (LSUIElement) requires explicit activation when opening settings. The application must temporarily activate so that text fields accept input. When settings close — it returns to background mode.
- Q: The overlay window does not respond to keyboard and hotkeys? → A: The floating panel must be configured to accept keyboard events (key window). The application must activate when showing the overlay.
- Q: What happens when the global hotkey is pressed again while the overlay is already open? → A: Toggle behavior — pressing the hotkey again closes the overlay without inserting text (similar to Alfred/Raycast).
- Q: How are OpenAI API errors handled (timeout, rate limit, server error) during transcription or LLM processing? → A: Show an error message in the overlay with a "Retry" button. The audio recording is preserved until the overlay closes, so the user can retry the request without re-recording.
- Q: What happens on first launch when there are no prompts yet? → A: On first launch, a preset prompt "Default" with basic formatting instructions (punctuation, paragraphs, Markdown) is created automatically. The prompt is assigned as default. The user can edit or delete it.
- Q: When is microphone permission requested? → A: Check in settings via a button (similar to Accessibility) and at the start of recording. If permission is not granted — request access via the button (macOS system dialog). When starting recording without permission — show a message with a button to request access.
- Q: How is the Accessibility permission for text insertion (CGEvent) handled? → A: The check is performed in the settings window via a button (not at application startup). After the check, the status is remembered. If permission is not granted when attempting to insert — show a message suggesting going to settings and granting permission.
- Q: Does Keychain prompt for password on every access? → A: Use the standard macOS Keychain (kSecClassGenericPassword) with access level kSecAttrAccessibleAfterFirstUnlock. The kSecUseDataProtectionKeychain flag must NOT be used — it requires a special entitlement and causes save errors in applications without that entitlement.

### Session 2026-03-04

- Q: Is post-processing of recognized text via AI needed? → A: Yes, transcription + AI formatting + a configurable system prompt in settings that is applied by default to all recordings.
- Q: What type of Markdown editor in the overlay? → A: WYSIWYG Markdown editor (real-time formatting, like in Notion/Bear).
- Q: Auto-launch at macOS login? → A: Auto-launch is enabled by default, can be disabled in settings.
- Q: Store recording history? → A: No, each recording is one-time; after insertion/closing the overlay, the text is not stored.
- Q: Format when copying to clipboard? → A: Markdown source (text with Markdown syntax).
- Q: System prompts — one or several? → A: Several named prompts with Markdown support. One is assigned as default. The default prompt is applied in the overlay, but it can be switched to another — the recording is re-sent for AI processing with the new prompt.
- Q: How is the global hotkey configured? → A: Recording a key combination — the user clicks on the field and presses the desired combination (like in Alfred/Raycast).
- Q: What happens when the recording limit is reached? → A: Configurable limit (1/5/10/20 min) in settings. Recording file size no more than 25 MB. The overlay displays a hint with the max duration. 30 seconds before the limit — a warning, then auto-stop with sending for recognition.
- Q: API key validation on input? → A: Yes, test request to the API on save; result (success/error) is displayed immediately in settings.
- Q: Where is the prompt selector in the overlay? → A: Visible at all times (both during recording and after the result). The user can switch the prompt during recording — the selected prompt is applied when sending for processing. After receiving the result, switching the prompt re-sends for AI processing.
- Q: Application technology stack? → A: SwiftUI + AppKit — fully native macOS application.
- Q: Which OpenAI models and where are they configured? → A: In the "System Prompts" tab, two selectors are added: transcription model (STT) and text processing model (LLM). Next to each selector — a tooltip icon (?) with a popover reference about models and prices. Available STT models: gpt-4o-mini-transcribe (default, $0.003/min), gpt-4o-transcribe ($0.006/min), whisper-1 ($0.006/min). Available LLM models: gpt-4.1-nano (default, $0.10/$0.40 per 1M tokens), gpt-4o-mini ($0.15/$0.60), gpt-4.1-mini ($0.40/$1.60), gpt-5-nano ($0.05/$0.40).
- Q: Mechanism for inserting text into the target application? → A: Clipboard + simulation of Cmd+V via CGEvent. The overlay returns focus to the previous application, places the text on the system clipboard, and simulates Cmd+V.
- Q: API key storage? → A: macOS Keychain — Apple's standard secret storage.
- Q: Settings and prompts storage? → A: UserDefaults for simple settings (hotkey, device, limit, auto-record, models), JSON file in Application Support for prompts (which contain long Markdown text).

## User Scenarios and Testing *(mandatory)*

### User Story 1 — Voice Recording and Recognition (Priority: P1)

The user places the cursor in any text field (browser,
desktop application, terminal, etc.), presses the configured
global hotkey, and a compact overlay window appears on top of
all windows. Audio recording starts automatically immediately
after the window appears (if the auto-record option is enabled
in settings, enabled by default). The user sees a
large visual voice activity and volume level indicator. Until
the recognized text appears, the overlay window
is displayed in a compact size with emphasis on the
recording indicator. When done, the user presses "Stop"
(or Space). The audio is sent for recognition. After
transcription, the text automatically goes through AI formatting
(punctuation, paragraphs, Markdown markup) using
a configurable system prompt. The finished formatted text
is displayed in the overlay window, which automatically
expands to the content size.

**Why this priority**: this is the product core — without recording,
recognition, and formatting, everything else is meaningless.

**Independent test**: can be fully verified by invoking
the hotkey, recording voice, and confirming that the recognized text
appeared in the overlay.

**Acceptance scenarios**:

1. **Given** the cursor is in the text field of any application,
   **When** the user presses the global hotkey,
   **Then** an overlay window appears on top of all windows
   in compact size within 300 ms with a selector
   for the system prompt (default prompt selected by default),
   voice language and text language selectors
   (values from the selected prompt), and audio recording
   starts automatically (when auto-record is enabled).

2. **Given** the overlay window is open and recording is in progress,
   **When** content has not yet appeared,
   **Then** the window is displayed in minimal compact size,
   the recording and sound level indicator is displayed large
   and occupies the main part of the window, the prompt
   and language selectors are available for changing.

2a. **Given** the overlay window is open (before or during recording),
   **When** the user changes the voice language or text language,
   **Then** the new language settings are applied when sending
   the audio stream for recognition and AI processing.

2b. **Given** the overlay window is open,
   **When** the user selects a different prompt in the selector,
   **Then** the voice and text languages are automatically updated
   to the values from the selected prompt (the user can additionally
   change them manually).

3. **Given** the overlay window is open and auto-record is disabled,
   **When** the user presses "Start recording" or Space,
   **Then** audio recording starts, a visual voice activity
   indicator is displayed (waveform animation/volume
   level).

4. **Given** recording is in progress,
   **When** the user presses "Stop" or Space,
   **Then** recording stops, a processing indicator is displayed,
   the audio is sent for recognition.

5. **Given** the audio is sent for recognition,
   **When** the service returns the transcription,
   **Then** the text automatically goes through AI formatting
   (punctuation, paragraphs, Markdown) applying the prompt selected
   in the overlay, the formatted result is displayed
   in the overlay window, and the window automatically expands
   to the content size.

6. **Given** recording is in progress,
   **When** the user changes the system prompt in the selector,
   **Then** the selected prompt will be applied when sending
   for AI processing after recording stops.

6a. **Given** the result is displayed in the overlay,
   **When** the user selects a different system prompt,
   **Then** the recording is re-sent for AI processing
   with the selected prompt, the result is updated.

7. **Given** recording is in progress,
   **When** 30 seconds remain before the recording limit,
   **Then** the user sees a visual warning about the
   imminent end of time.

8. **Given** recording is in progress,
   **When** the duration limit is reached or the file size
   exceeded 25 MB,
   **Then** the recording automatically stops and is sent
   for recognition.

9. **Given** recording is in progress,
   **When** the user presses Delete,
   **Then** the current recording is reset and a new
   recording can be started.

---

### User Story 2 — Text Editing and Insertion (Priority: P2)

After recognition, the user sees the result in the overlay window
with Markdown markup support. They can edit the text
if needed, and then insert it into the active text
field with the "Insert" button or copy to the clipboard
with the "Copy" button.

**Why this priority**: without the ability to use
the recognition result (insert/copy), the feature
provides no practical benefit.

**Independent test**: after receiving the recognized text,
edit it, press "Insert", and confirm
that the text appeared in the target field.

**Acceptance scenarios**:

1. **Given** the recognized text is displayed in the overlay,
   **When** the user edits the text,
   **Then** changes are saved in the overlay window
   in the WYSIWYG Markdown editor (formatting is displayed
   in real time: headings, lists, bold, italic, code).

2. **Given** the text is ready for insertion,
   **When** the user presses "Insert",
   **Then** the overlay closes, the text is inserted
   into the previously active text field.

3. **Given** the text is ready,
   **When** the user presses "Copy",
   **Then** the Markdown source is copied to the system
   clipboard, the user sees a confirmation
   of copying.

4. **Given** the overlay window is open at any stage,
   **When** the user presses Escape or the close hotkey,
   **Then** the overlay closes without inserting text.

---

### User Story 3 — Application Settings (Priority: P3)

The user opens application settings from the Menu Bar
by clicking the "Settings" option. The settings window appears on top
of all running windows in the modern style of recent macOS
applications (like System Settings in macOS Ventura+). The window
contains a sidebar with tabs and icons:

- **General** (icon: gear) — global hotkey
  for invoking the overlay, default audio device selection,
  maximum recording duration (1/5/10/20 min),
  auto-launch at macOS login,
  auto-record when overlay opens, OpenAI API key,
  Accessibility and Microphone permission check (via button).
- **System Prompts** (icon: text.bubble) —
  creation, editing, and deletion of named prompts
  with Markdown content support; assigning one
  prompt as default. For each prompt, default languages are set:
  voice language (input audio language) and text language
  (output result language). 10 popular languages are available:
  English, Russian (mandatory), Spanish, French,
  German, Portuguese, Chinese, Japanese, Korean, Italian.
  Also on this tab are global selectors for the transcription model
  (STT) and text processing model (LLM),
  applied to all prompts.
- **About** (icon: info.circle) —
  application version, license, links to documentation
  and support.

The settings window automatically adjusts its size to
the content of the selected tab on opening and when switching
between tabs.

**Why this priority**: settings are necessary for operation,
but you can start with default values.

**Independent test**: open settings, switch between
tabs, change the hotkey, confirm that the new hotkey works.

**Acceptance scenarios**:

1. **Given** the application is running,
   **When** the user clicks the Menu Bar icon
   and selects "Settings",
   **Then** the settings window opens on top of all running
   windows in modern macOS style with tabs and icons.

2. **Given** the settings window is open,
   **When** the user switches between tabs
   (General / System Prompts / About),
   **Then** the content changes, and the window size smoothly
   adapts to the content of the selected tab.

3. **Given** the "General" tab is open,
   **When** the user sets a new global hotkey,
   **Then** the new hotkey is saved and immediately
   starts working.

4. **Given** the "General" tab is open,
   **When** the user enters the OpenAI API key and saves,
   **Then** the input field supports Command+V for pasting
   from the clipboard, a test request to the API is performed,
   the validation result (success/error) is displayed immediately,
   the key is stored securely (not in plain text).

5. **Given** the "General" tab is open,
   **When** the user selects an audio device from the list
   of available recording devices,
   **Then** the selected device is saved and used
   for all subsequent recordings.

6. **Given** the "General" tab is open,
   **When** the user toggles the "Auto-record
   when overlay opens" option,
   **Then** the change is applied immediately: on the next
   overlay invocation, recording starts automatically (or not).

8. **Given** the "General" tab is open,
   **When** the user toggles the auto-launch option,
   **Then** the change is applied on the next macOS
   login.

9. **Given** the "System Prompts" tab is open,
   **When** the user creates, edits, or deletes
   a named prompt (with Markdown content support),
   **Then** changes are saved; one prompt can be
   assigned as default.

9a. **Given** the "System Prompts" tab is open,
    **When** the user edits a prompt,
    **Then** settings are available for the prompt: voice language
    (input audio language) and text language (output
    result language), selectable from the list of 10 popular languages.

10. **Given** the "About" tab is open,
    **When** the user views the information,
    **Then** the application version, license,
    and documentation links are displayed.

---

### Edge Cases

- What happens if the microphone is not available or permission
  is not granted? — The application MUST show a clear message
  with instructions for granting permission.
- What happens if the API key is not configured? — The application
  MUST show a message suggesting going to settings.
- What happens if the network is unavailable? — The application MUST
  inform the user about the network error.
- What happens if the OpenAI API returns an error (timeout,
  rate limit, 500)? — The overlay MUST display an error
  message with a "Retry" button; the audio recording is preserved
  until the overlay closes.
- What happens if the user recorded silence? —
  The application MUST handle the empty result and report
  that speech was not detected.
- What happens if the target input field becomes unavailable
  (application closed)? — The text MUST remain on the
  clipboard, the user MUST be notified.
- What happens if Accessibility permission is not granted
  when attempting insertion? — The text MUST remain on the
  clipboard, the application MUST show a message with instructions
  for granting permission in System Settings.
- What happens if the global hotkey conflicts
  with another application? — Settings MUST allow
  changing the hotkey; the application MUST warn
  about possible conflict.
- What happens if the selected audio device is disconnected
  or unavailable? — The application MUST automatically
  switch to the system default device
  and notify the user.
- What happens if the settings window is already open and
  the user clicks "Settings" again? — The existing
  window MUST be brought to the front.

## Requirements *(mandatory)*

### Functional Requirements

#### Overlay Window

- **FR-001**: The application MUST provide a global
  hotkey that works in any macOS application.
- **FR-002**: On hotkey press, an overlay window MUST
  appear on top of all applications.
- **FR-002a**: Pressing the global hotkey again while the overlay
  is open MUST close the overlay without inserting text
  (toggle behavior).
- **FR-003**: The overlay MUST support control with the
  Space key (start/stop) and Delete (reset/restart).
- **FR-004**: During recording, a large
  visual voice activity indicator MUST be displayed (volume
  level or waveform animation).
- **FR-004a**: Until the recognized text appears, the overlay
  MUST be displayed in compact size, with emphasis
  on the recording and sound level indicator. The overlay MUST
  display a hint with the maximum recording duration.
- **FR-004b**: After receiving the recognized text, the overlay
  MUST automatically expand to the content size.
- **FR-005**: After recording stops, the audio MUST
  be sent to the speech recognition service.
- **FR-005a**: After transcription, the text MUST automatically
  go through AI formatting (punctuation, structuring,
  Markdown markup) using the system prompt.
- **FR-005b**: The formatted result MUST be displayed
  in the overlay window.
- **FR-005c**: On API error (timeout, rate limit, server
  error), the overlay MUST display an error message
  with a "Retry" button. The audio recording MUST be preserved
  until the overlay closes to enable retry.
- **FR-006**: The result field in the overlay MUST be
  a WYSIWYG Markdown editor with visual rendering
  in real time (headings, lists, bold, italic, code).
- **FR-007**: The application MUST provide an
  "Insert" button that closes the overlay, returns focus
  to the previous application, places plain text on the system
  clipboard, and simulates Cmd+V via CGEvent.
- **FR-008**: The application MUST provide a
  "Copy" button to copy the Markdown source
  to the system clipboard.
- **FR-014**: The overlay MUST NOT intercept focus
  from the target application when inserting text.
- **FR-014a**: When attempting insertion without Accessibility permission,
  the application MUST show a message suggesting going
  to settings and granting permission (the text remains
  on the clipboard).

#### Audio Recording

- **FR-016a**: At the start of recording, the application MUST check
  the Microphone permission. If permission is missing — show
  a message with an access request button (macOS system dialog).
  Recording does NOT start until permission is obtained.
- **FR-017**: The application MUST support auto-record —
  audio recording starts automatically immediately after
  the overlay window appears (setting, enabled by default).
- **FR-018**: The user MUST be able to select
  a default audio device for recording from the list
  of available devices.
- **FR-018a**: If the selected device is unavailable,
  the application MUST automatically switch to the
  system default device.
- **FR-018b**: The user MUST be able to select
  the maximum recording duration (1 / 5 / 10 / 20 minutes)
  in settings.
- **FR-018c**: The recording file size MUST NOT exceed 25 MB;
  when the limit is reached, recording automatically stops.
- **FR-018d**: 30 seconds before the end of the recording limit,
  the application MUST display a visual warning.

#### Settings

- **FR-009**: The application MUST work from the Menu Bar
  (without an icon in the Dock).
- **FR-016**: The application MUST automatically launch
  at the user's macOS login (enabled by default,
  disabled in settings).
- **FR-019**: The settings window MUST open on top of all
  running windows when "Settings" is clicked in the menu.
  The window MUST receive keyboard focus — all text fields,
  including the API key field, MUST accept input from the keyboard
  without the need for additional clicks. The application MUST
  activate correctly despite running in Menu Bar mode
  (without a Dock icon).
- **FR-019a**: On re-invocation of "Settings" from the Menu Bar,
  if the settings window is already open, it MUST be brought
  to the front and receive input focus.
- **FR-020**: The settings window MUST be styled in the
  modern style of recent macOS applications (similar to
  System Settings in macOS Ventura+) with a sidebar of tabs
  and icons.
- **FR-021**: The settings window MUST contain three tabs:
  "General" (icon: gear), "System Prompts"
  (icon: text.bubble), "About"
  (icon: info.circle).
- **FR-022**: The settings window MUST automatically adjust
  its size to the content of the selected tab on opening
  and when switching between tabs.
- **FR-010**: The user MUST be able to
  configure the global hotkey for invoking the overlay through
  recording a key combination (click on field → press
  the desired combination).
- **FR-010a**: The "General" tab MUST have an Accessibility
  permission check button. On press, the application checks
  for the permission and displays the current status. The status
  is remembered. The check is NOT performed automatically at
  application startup.
- **FR-010b**: The "General" tab MUST have a Microphone
  permission check button. On press, the application checks
  for the permission and, if missing — requests access
  (macOS system dialog). The status is displayed and remembered.
- **FR-011**: The API key MUST be stored in the macOS Keychain.
- **FR-011a**: The API key input field MUST support
  Command+V for pasting from the clipboard.
- **FR-011b**: On saving the API key, the application MUST
  perform a test request to the API and display the validation
  result (success/error) directly in settings.
- **FR-011c**: Access to the API key in Keychain MUST
  be performed without requesting the user's password on every
  access. The standard macOS Keychain MUST be used
  (kSecClassGenericPassword) with the access level "after first
  unlock" (kSecAttrAccessibleAfterFirstUnlock).
  The kSecUseDataProtectionKeychain flag MUST NOT be used,
  because it requires a special entitlement and causes
  save errors. The entitlements MUST specify
  `keychain-access-groups` with the value
  `$(AppIdentifierPrefix)<bundle-id>` to prevent
  system password prompts in the sandbox environment.
- **FR-012**: For each prompt, two language parameters MUST
  be configured: voice language (input audio language)
  and text language (output result language).
- **FR-012a**: Available languages: English, Russian (mandatory),
  Spanish, French, German, Portuguese, Chinese, Japanese,
  Korean, Italian (10 languages).
- **FR-012b**: In the overlay, voice language
  and text language selectors MUST be visible at all stages (before recording,
  recording, result). By default, values are taken from the selected
  prompt.
- **FR-012c**: The user MUST be able to change
  languages in the overlay before or during recording; changes
  are applied when sending the audio stream.
- **FR-012d**: When changing the prompt in the overlay, the language
  selectors MUST automatically update to the values from the new
  prompt.
- **FR-015**: In the "System Prompts" tab, the user MUST
  be able to create, edit, and delete
  named prompts with Markdown content support.
- **FR-015a**: One prompt MUST be assigned as default
  and automatically applied during AI formatting.
- **FR-015e**: On first application launch, a preset prompt
  "Default" with basic formatting instructions
  (punctuation, paragraphs, Markdown) MUST be
  created automatically. The prompt is assigned
  as default. The user can edit or delete it.
- **FR-015b**: In the overlay, the system prompt
  selector MUST be visible at all stages (recording, processing, result).
- **FR-015c**: Changing the prompt during recording MUST be applied
  when sending for AI processing after stop.
- **FR-015d**: Changing the prompt after receiving the result MUST
  re-send the recording for AI processing with the new prompt.

#### OpenAI Models

- **FR-023**: In the "System Prompts" tab, there MUST be global
  selectors for the transcription model (STT) and text processing
  model (LLM).
- **FR-023a**: Available STT models: gpt-4o-mini-transcribe
  (default), gpt-4o-transcribe, whisper-1.
- **FR-023b**: Available LLM models: gpt-4.1-nano (default),
  gpt-4o-mini, gpt-4.1-mini, gpt-5-nano.
- **FR-023c**: Selected models MUST be applied to all
  transcription and AI formatting operations.
- **FR-023d**: Next to each model selector there MUST be
  a tooltip icon (question mark); when clicked,
  a popover with reference about available models is displayed:
  - STT: gpt-4o-mini-transcribe (default) — $0.003/min;
    gpt-4o-transcribe — $0.006/min; whisper-1 — $0.006/min.
  - LLM (price per 1M tokens input/output):
    gpt-4.1-nano — $0.10/$0.40, best choice for price/quality;
    gpt-4o-mini — $0.15/$0.60, proven model;
    gpt-4.1-mini — $0.40/$1.60, for cases requiring more quality;
    gpt-5-nano — $0.05/$0.40, cheapest, new model.

#### Data Storage

- **FR-024**: Simple settings (hotkey, audio device, recording
  limit, auto-record, auto-launch, selected models) MUST
  be stored in UserDefaults.
- **FR-024a**: Named prompts MUST be stored in a JSON file
  in the application's Application Support directory.
- **FR-024b**: The API key MUST be stored in the standard
  macOS Keychain with the access level "after first unlock",
  without repeated password prompts (see FR-011, FR-011c).
- **FR-013**: The application MUST correctly handle
  errors (no microphone, network, API key)
  with clear messages to the user.

### Key Entities

- **Recording**: audio stream, state
  (idle, recording, processing, complete), duration.
- **Recognition Result (TranscriptionResult)**:
  source text, edited text, language,
  timestamp.
- **System Prompt (SystemPrompt)**: name, Markdown
  content, "default" flag, voice language (input),
  text language (output); the user can create
  several prompts and switch between them.
- **Settings**: global hotkey, API key
  (macOS Keychain), default audio device, max.
  recording duration, auto-record on overlay open,
  reference to default prompt, auto-launch at
  macOS login, transcription model (STT), text processing
  model (LLM). Storage: UserDefaults for simple settings,
  JSON in Application Support for prompts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The overlay window appears within 300 ms
  after pressing the global hotkey.
- **SC-002**: The voice activity visual indicator
  updates in real time without noticeable delays.
- **SC-003**: 95% of recordings up to 2 minutes long
  are successfully recognized and displayed in the overlay.
- **SC-004**: The user can complete the full cycle
  (hotkey → recording → result → insertion) in less than
  30 seconds for a phrase of 2-3 sentences.
- **SC-005**: Text insertion into the target field works
  in 90% of popular macOS applications (Safari, Chrome,
  VS Code, Slack, Telegram, Notes, TextEdit).
- **SC-006**: The application consumes less than 50 MB of RAM
  in idle mode.

## Assumptions

- By default, the global hotkey is Option+Space
  (the user can change it).
- Default languages (voice and text) are set for each
  prompt. By default, both are determined by the macOS
  system language. 10 languages available: English, Russian,
  Spanish, French, German, Portuguese, Chinese, Japanese,
  Korean, Italian.
- Maximum duration of one recording — configurable
  by the user (1/5/10/20 minutes, default 5 minutes).
  Recording file size no more than 25 MB.
- The result field — WYSIWYG Markdown editor with visual
  rendering in real time (like in Notion/Bear).
- When inserting into the target field, plain text is inserted
  (without Markdown formatting), since most
  input fields do not support Markdown.
- Recording history is not stored — each recording is one-time;
  after insertion or closing the overlay, the text is deleted.
- Auto-record on overlay open is enabled by default.
- The default audio device — system input device;
  the user can select another in settings.
- The settings window is styled like System Settings
  in macOS Ventura+ with a navigation sidebar.
