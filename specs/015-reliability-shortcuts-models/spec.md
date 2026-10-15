# Feature Specification: Reliability, Shortcuts & Model List Update

**Feature Branch**: `015-reliability-shortcuts-models`

**Created**: 2026-10-14

**Status**: Draft

**Input**: User description: "Several fixes: (1) the app doesn't start at macOS login although the toggle is on — analyze why and fix; (2) the app sometimes hangs mid-work and must be force-quit — analyze local logs and fix; (3) the shortcut recorder is unreliable — show held modifier keys live, finish on a regular key, support Fn as a modifier, show Fn in floating-window hints; (4) floating window: key 1 = microphone, key 2 = prompt (cycle next, like the microphone), key 3 = output language; move the prompt selector (currently the 'Speech To Text' header at the top) to the bottom bar next to the microphone."

**Input (US5–US8, merged from former spec 016-add-openai-models)**: User description: "Updated OpenAI Model List for Verborra (verified October 14, 2026, OpenAI API, USD). Speech-to-text: gpt-transcribe (recommended default), gpt-live-transcribe, gpt-realtime-whisper, plus existing gpt-4o-mini-transcribe, gpt-4o-transcribe, gpt-4o-transcribe-diarize, whisper-1 (deprecated, removal 2027-02-26). Text formatting: existing GPT-4o Mini … GPT-5.5 Pro plus gpt-5.6-terra, gpt-5.6-sol, gpt-6-luna, gpt-6-sol, gpt-6.1-sol, gpt-6-astra, with input/output prices per 1M tokens. Temperature support must be tied to the exact model, not the model family. Recommended defaults: gpt-transcribe for speech-to-text, gpt-6-luna for text formatting; gpt-6.1-sol advanced; gpt-6-astra premium. Migration notice: GPT-4o, GPT-4o Mini, GPT-4.1, GPT-4.1 Mini shut down 2027-01-14; gpt-5.1 and gpt-5.4-nano on 2027-04-01 — preserve existing selections but don't make them new defaults. Verify temperature support and endpoint compatibility for each selectable model before shipping."

**Input (merged 2026-10-15 from former specs 016–018)**:
- 016: "In the floating window, move the output language to second place and the prompt to third. Limit the prompt name to about 30 characters in Settings so it displays correctly in the floating window. Add a first item to each bottom-bar dropdown that says what the setting is for: "Input device" for audio devices, "Output language" for languages, "Using prompt" for prompts."
- 017: "Move 'Simulate main-thread stall (3 s)' to the Advanced tab in Settings."
- 018: "Switching and closing windows between sources is broken. Analyze why and fix it."
- 2026-10-15 addition: "How to decrease this empty space" (above the waveform and below the timer while recording) → option C (window fits its content) was built, then the owner asked to revert to a static size of 200 pt.
- 2026-10-15 addition: "Change the behavior of the input device and output language buttons in the floating window to use dynamic sizes like the prompt; use the same logic for the input device and language as for the dynamic prompt."
- 2026-10-15 addition: "For the button on the floating window, use a dynamic size that matches the prompt name, but limit it to a maximum size that prevents overlapping or getting closer to the right buttons (Start, Stop, Exit)."

**Supporting evidence**: [investigation.md](./investigation.md) — root-cause findings from code, local logs, and crash reports (§3 covers microphone switching, added 2026-10-15).

## Clarifications

### Session 2026-10-14

- Q: When starting a recording fails, what should Verborra do? → A: Retry once automatically on the same microphone; if that fails, show the error with a "Retry" action (never switch microphone automatically).
- Q: On a fresh install, should Verborra register itself at login automatically or stay off until enabled? → A: Ask once during onboarding/first launch with "on" pre-selected, and apply the answer immediately.
- Q: Should a prompt picked in the floating window carry over to the next session? → A: No — per-session only; every new session starts with the default prompt from Settings.
- Q: How should the Fn key be shown in floating-window hints and the Settings shortcut field? → A: As the globe symbol 🌐︎ (as macOS menus show it), e.g. "🌐︎ ⌥ Space".
- Q: If the global hotkey is pressed again while a recording is still starting (including the automatic retry), what should happen? → A: Cancel the start in progress and return to the pre-recording stage.
- Q (from analysis): Does the 5-second start limit include the Bluetooth headset mode switch (AirPods etc. switching to microphone mode), which alone can take up to 5 seconds? → A: No. The Bluetooth mode switch is a separate, visible step ("Switching…" indicator, cancellable, its own 5-second limit). The 5-second start limit begins when that step ends. For non-Bluetooth microphones the limit begins at the hotkey press.

**Model list (US5–US8):**

- Q: Relation to the earlier draft of the model-list spec? → A: The final version replaced it; the model-list spec (former 016) was then merged into this one.
- Q: Are live/streaming speech-to-text models in scope? → A: No. Only models that transcribe a finished recording are added; live transcription is a separate future feature.
- Q: Should defaults change? → A: Yes. New installs start on the new defaults; existing users keep their model unless it is removed (see below).
- Q: Add the speaker-labelling (diarize) transcription model? → A: No.
- Q: What happens to models OpenAI has deprecated? → A: Remove all of them from the lists in this release (GPT-4o Mini, GPT-4.1 Mini, GPT-5.1, GPT-5.4 Nano, GPT-4o Mini Transcribe, GPT-4o Transcribe, Whisper-1), instead of keeping them labelled until shutdown.
- Q: Which model replaces a removed text model for a user who had it selected? → A: The new default, GPT-6 Luna, for all of them. (Speech-to-text users move to GPT Transcribe, the only remaining model.)
- Q: How is the user told their model was switched? → A: Silently; the switch is recorded in the diagnostic log only.
- Q: What does Settings show when the speech-to-text list has one model? → A: The same picker as today, with one entry.
- Q: What happens if OpenAI rejects GPT Transcribe for a user's account, given it's the only speech-to-text model? → A: Show the usual error only; there is no hidden fallback to another transcription model.
- Q: OpenAI's deprecations page (checked during planning) lists GPT-5 Nano and GPT-5 Mini for shutdown on 2026-12-11. Remove them too? → A: Yes; the "remove all deprecated" rule applies to them. Users on them move to GPT-6 Luna.
- Q: GPT-5.4 Pro and GPT-5.5 Pro don't support the Chat Completions API the app uses (OpenAI model pages, checked during analysis), so they have never worked in Verborra. Keep them? → A: No; remove both. Users on them move to GPT-6 Luna. Supporting the Responses API is a separate feature.

**Whole spec:**

- Q: Must all eight user stories ship in one release, or may the model-list update (US5–US8) ship first? → A: One release; all eight stories ship together.

### Session 2026-10-15

- Q: Should the follow-up specs 016 (bar order, prompt name limit, menu titles), 017 (stall test in Settings) and 018 (microphone switching) ship separately? → A: No; they are merged into this spec and ship in the same release. 016 amends US4, 017 is part of US2, 018 is US9, the prompt name limit is US10.
- Q: The owner has no Apple Developer certificate; how are builds signed? → A: Ad-hoc ("Sign to Run Locally") with Hardened Runtime; FR-006 and SC-001 were amended accordingly.
- Q: With Auto-record on, keys 1–3 never worked because they were limited to the idle state. Allow them while recording? → A: Yes; they work while idle, recording or showing an error (US4 scenario 7).
- Q: In which order should the bottom-bar selectors appear, and which key changes which? → A: Microphone (1), output language (2), prompt (3); the keys follow the positions. This swaps keys 2 and 3 compared with the 2026-10-14 version of US4.
- Q: What is the first line of each bottom-bar menu? → A: A non-selectable title saying what the menu sets: "Input device", "Output language", "Using prompt".
- Q: How long may a prompt name be? → A: 30 user-visible characters, enforced when creating and editing prompts in Settings. Longer names saved earlier are kept until edited.
- Q: Should the stall-test button also appear in Release builds? → A: No; Debug builds only, in a Developer section at the bottom of Settings › Advanced. It is removed from the menu bar menu.
- Q: When the microphone is switched mid-recording, what happens to what was said before the switch? → A: It is discarded (as before): recording restarts from zero on the new microphone.
- Q: While a microphone switch is in progress, can the user start another switch (key 1 or the microphone menu)? → A: No. Only one switch runs at a time: keys 1–3 and the bottom-bar menus are disabled until the switch finishes or fails; cancel (and closing the window) stays available. Chosen for stability.
- Q: How wide is the prompt button in the bottom bar? → A: As wide as the prompt name needs, up to a maximum that keeps it from overlapping or crowding the buttons on the right (Start/Stop/Cancel, Exit). If the name doesn't fit, the microphone title is shortened first, then the prompt name with "…".
- Q: Do the microphone and output-language buttons size the same way? → A: Yes. All three selector buttons follow their title's width (no fixed width cap on the microphone), share the room left before the right-hand buttons, and are shortened with "…" only when the row runs out of space: microphone first, then prompt, then output language.
- Q: How should the empty space above the waveform and below the timer be reduced? → A: With a fixed, shorter window: 200 pt instead of 220 pt in the pre-recording stage (a window that fits its content was tried and reverted at the owner's request).
- Q: After a failed switch, does picking another microphone start recording again? → A: Yes; it starts recording on the chosen microphone with the same limits and retry as a switch. (In an error that didn't come from a switch, picking a microphone only changes the selection, as before.)

## Model list (decision for US5–US8)

The app has two model lists in Settings: the **speech-to-text model** (turns the recording into text) and the **text model** (formats the text and answers follow-ups). Verborra records a clip, sends the finished recording for transcription, then formats the text.

### Speech-to-text list (final)

| Model | Price / min | Change |
|---|---|---|
| GPT Transcribe | $0.0045 | Added — **new default** |

### Text model list (final, in display order)

| Model | Input / 1M | Output / 1M | Change |
|---|---|---|---|
| GPT-5.2 | $1.75 | $14.00 | Kept |
| GPT-5.4 Mini | $0.75 | $4.50 | Kept |
| GPT-5.4 | $2.50 | $15.00 | Kept |
| GPT-5.5 | $5.00 | $30.00 | Kept |
| GPT-5.6 Terra | $2.00 | $12.00 | Added |
| GPT-5.6 Sol | $4.00 | $20.00 | Added |
| GPT-6 Luna | $0.10 | $0.50 | Added — **new default** |
| GPT-6 Sol | $2.00 | $10.00 | Added |
| GPT-6.1 Sol | $2.00 | $10.00 | Added — recommended for advanced formatting |
| GPT-6 Astra | $10.00 | $50.00 | Added — recommended premium option |

### Removed in this release

| Model | List | Reason | Users who had it selected move to |
|---|---|---|---|
| GPT-4o Mini Transcribe (current default) | Speech-to-text | Deprecated, OpenAI shutdown 2027-02-26 | GPT Transcribe |
| GPT-4o Transcribe | Speech-to-text | Deprecated, OpenAI shutdown 2027-02-26 | GPT Transcribe |
| Whisper-1 | Speech-to-text | Deprecated, OpenAI shutdown 2027-02-26 | GPT Transcribe |
| GPT-4o Mini | Text | Deprecated, OpenAI shutdown 2027-01-14 | GPT-6 Luna |
| GPT-4.1 Mini | Text | Deprecated, OpenAI shutdown 2027-01-14 | GPT-6 Luna |
| GPT-5 Nano | Text | Deprecated, OpenAI shutdown 2026-12-11 | GPT-6 Luna |
| GPT-5 Mini | Text | Deprecated, OpenAI shutdown 2026-12-11 | GPT-6 Luna |
| GPT-5.1 (current default) | Text | Deprecated, OpenAI shutdown 2027-04-01 | GPT-6 Luna |
| GPT-5.4 Nano | Text | Deprecated, OpenAI shutdown 2027-04-01 | GPT-6 Luna |
| GPT-5.4 Pro | Text | Not supported by Chat Completions (Responses API only) | GPT-6 Luna |
| GPT-5.5 Pro | Text | Not supported by Chat Completions (Responses API only) | GPT-6 Luna |

### Not added, with the reason

| Candidate | Reason |
|---|---|
| GPT Live Transcribe, GPT Realtime Whisper | Live transcription while the user speaks. Verborra sends the finished recording, so these need a different recording flow (separate feature). |
| GPT-4o Transcribe Diarize | Speaker labels aren't useful for single-person dictation, and the model is already deprecated. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - App starts automatically at login (Priority: P1)

As a user who enabled "Launch at login", I expect Verborra to be running (menu bar icon present, global hotkey working) after I restart or log in to my Mac, without starting it manually. The setting I see must always reflect what will actually happen.

**Why this priority**: The app is a global voice-input tool; if it isn't running, the hotkey silently does nothing. Today the toggle shows "on" while no login item exists, which is both a functional bug and a misleading UI.

**Independent Test**: Enable the setting, log out and back in (or restart) → Verborra is running. Disable it, log out/in → Verborra is not running.

**Acceptance Scenarios**:

1. **Given** the "Launch at login" setting shows enabled, **When** the user logs in to macOS, **Then** Verborra starts automatically and its global hotkey works.
2. **Given** a fresh install, **When** the user goes through onboarding/first launch, **Then** the user is asked once whether to start Verborra at login (pre-selected "on"), and the answer is applied immediately so that the displayed state is truthful.
3. **Given** the user has disabled Verborra in macOS System Settings › Login Items, **When** the user opens Verborra Settings, **Then** the toggle shows the real (disabled / needs-approval) state and offers a one-click way to open the relevant system settings page.
4. **Given** the user replaces the app with a newer build, **When** the user next logs in, **Then** the app still starts at login (the setting survives updates).
5. **Given** registering the app as a login item fails, **When** the user toggles the setting, **Then** the toggle reverts to the real state and a clear error message is shown and logged.

---

### User Story 2 - App never freezes during recording (Priority: P1)

As a user dictating text, I expect the app to stay responsive at all times. If starting a recording fails (e.g. audio device problems after idle, device format mismatch), I want a clear message and the ability to retry or close the window — never a frozen app that requires Activity Monitor.

**Why this priority**: A hang loses the user's work and trust and forces a manual force-quit. Local logs show two hangs and two related crashes in the last 4 days, all at recording start during audio setup.

**Independent Test**: Simulate an audio setup failure / slow audio device (e.g. switch devices or sample rates, start recording after long idle, unplug a device during start) repeatedly → the app either records or shows an error within the time limit; the global hotkey, menu bar menu, and floating window keep responding.

**Acceptance Scenarios**:

1. **Given** the app has been idle for a long time, **When** the user presses the hotkey to start recording, **Then** recording starts or a clear error is shown within 5 seconds, and the app remains responsive.
2. **Given** the audio device reports a format that does not match the expected recording format, **When** recording starts, **Then** the app adapts or fails gracefully with an error message instead of freezing or crashing.
3. **Given** an audio setup step fails or stalls, **When** the user presses the hotkey, Esc, or uses the menu bar menu, **Then** the app responds to each action (cancel / close / quit) normally.
4. **Given** the app becomes unresponsive for more than 2 seconds for any reason, **When** this happens, **Then** a warning with context (current stage, active device, timing) is written to the diagnostic log so the cause can be analyzed later.
5. **Given** any audio setup failure occurs, **When** it is handled, **Then** an ERROR entry with the failing step, device, and reason is written to the diagnostic log (today such failures leave no trace).
6. **Given** a Debug build, **When** the developer opens Settings › Advanced, **Then** a "Developer" section at the bottom offers "Simulate main-thread stall (3 s)" with a one-line explanation; clicking it freezes the app for about 3 seconds and the stall warning from scenario 4 appears in the log. The menu bar menu has no such item, and Release builds show no Developer section.

---

### User Story 3 - Reliable shortcut recording with live modifier feedback and Fn support (Priority: P2)

As a user configuring the global hotkey in Settings, I click the shortcut field and press keys. While the field is focused, I see the modifier keys I'm currently holding (e.g. "⌥", then "⌥ ⇧" when I add Shift). As soon as I press a regular (non-modifier) key, the shortcut is saved and the field loses focus. I can use Fn (Globe), Shift, Control, Option, and Command as modifiers.

**Why this priority**: The hotkey is the entry point to the app; unreliable recording blocks customization. Fn support is a new capability many keyboard-centric users expect.

**Independent Test**: Open Settings › Hotkeys, focus the field, press and hold modifiers in various orders, add a letter → the field shows modifiers live, saves the combo, exits focus; the new shortcut opens the floating window from any app. Repeat 20 times, including while the floating window is open.

**Acceptance Scenarios**:

1. **Given** the shortcut field is focused, **When** the user presses and holds Option, **Then** the field immediately shows "⌥".
2. **Given** the user holds Option, **When** they additionally press Shift, **Then** the field shows both modifiers using standard macOS ordering (🌐︎ ⌃ ⌥ ⇧ ⌘), i.e. "⌥⇧".
3. **Given** the user holds one or more modifiers, **When** they press a regular key (letter, digit, Space, function key, etc.), **Then** the shortcut is saved, displayed in the field, the field loses focus, and the new shortcut is active immediately.
4. **Given** the field is focused, **When** the user holds Fn (Globe) and presses a regular key, **Then** the shortcut is saved with Fn and works globally.
5. **Given** the user releases all modifiers without pressing a regular key, **When** this happens, **Then** the field returns to its "recording" placeholder state and nothing is saved.
6. **Given** the field is focused, **When** the user presses a regular key without any modifier, **Then** the shortcut is not saved and the user sees a hint that at least one modifier is required.
7. **Given** the field is focused, **When** the user presses Esc, **Then** recording is cancelled and the previous shortcut is kept.
8. **Given** the floating window is open (or was open earlier), **When** the user records a shortcut in Settings, **Then** every key press reaches the shortcut field (no keys are intercepted by the floating window).
9. **Given** the chosen combination is already used by macOS or is reserved, **When** the user records it, **Then** the user is warned and the previous shortcut is kept.

---

### User Story 4 - Floating window: selectors in the bottom bar with number shortcuts 1-2-3 (Priority: P2)

As a user in the first (pre-recording) stage of the floating window, I want all session options in one place in the bottom bar, in this order, with matching number shortcuts: **1** cycles the microphone, **2** cycles the output language, **3** cycles the prompt. The prompt name currently shown as a header at the top of the window (e.g. "Speech To Text") moves into the bottom bar. Each selector's menu starts with a title saying what it sets. All shortcut hints in the window display Fn correctly when the global hotkey uses it.

**Why this priority**: Improves speed and consistency of the most frequent flow; depends on nothing else but is lower risk than the P1 fixes.

**Independent Test**: Open the floating window → the top prompt header is gone; the bottom bar shows microphone [1], output language [2], prompt [3]. Pressing 3 repeatedly cycles through all prompts and wraps around; 1 and 2 behave as described. Opening each menu shows its title as the first line.

**Acceptance Scenarios**:

1. **Given** the floating window is in the pre-recording stage, **When** it appears, **Then** there is no prompt header at the top, and the bottom bar shows, in order: microphone selector with hint "1", output language selector with hint "2", prompt selector (showing the current prompt name, e.g. "Speech To Text") with hint "3".
2. **Given** the current prompt is the default one, **When** the user presses 3, **Then** the next prompt in the list becomes selected and its name is shown; pressing 3 on the last prompt wraps to the first — the same cycling behavior as the microphone selector.
3. **Given** only one prompt exists, **When** the user presses 3, **Then** the selection stays the same and nothing breaks.
4. **Given** the pre-recording stage, **When** the user presses 1, **Then** the next microphone is selected (unchanged behavior); **When** the user presses 2, **Then** the next output language is selected.
5. **Given** the user clicks the prompt selector, **When** the menu opens, **Then** all prompts are listed and the user can pick any of them directly.
6. **Given** the global hotkey includes Fn, **When** the floating window shows the Start/Stop hint, **Then** the Fn key is displayed as the globe symbol 🌐︎ before the other modifier symbols (e.g. "🌐︎ ⌥ Space").
7. **Given** a recording is starting, switching microphone (US9) or being processed (or the window is in the post-processing stage), **When** the user presses 1, 2, or 3, **Then** the selections do not change. Keys 1–3 work in the pre-recording stage while idle, recording or showing an error, the same states in which the bottom-bar menus are enabled (amended 2026-10-15: with Auto-record on, the window is always recording, so the stricter rule made the keys unusable).
8. **Given** the user opens the microphone, output language or prompt menu, **When** it appears, **Then** its first line is a non-selectable title — "Input device", "Output language" or "Using prompt" — followed by a separator and the options; in Russian the titles are translated.
9. **Given** any of these menus is open, **When** the user clicks the title line, **Then** the selection does not change; cycling with keys 1–3 never selects a title.
10. **Given** the user switches microphones (e.g. "AirPods" ↔ "MacBook Pro Microphone") or output languages (e.g. "English" ↔ "Русский"), **When** the selection changes, **Then** each button's width follows its title, the same way the prompt button does (FR-063, FR-064): no fixed width, the same padding on both sides, and never closer to the right-hand buttons than the normal gap.
11. **Given** the floating window is open in the pre-recording stage (idle, starting, switching, recording, processing, an error, or "no microphone access"), **When** it is shown, **Then** it is 200 pt tall in every one of these states, nothing is clipped, and its height doesn't change when recording starts or stops.

---

### User Story 5 - Choose a new text model (Priority: P1)

As a user, I open Settings and pick one of the new text models (GPT-5.6 Terra/Sol, GPT-6 Luna/Sol/Astra, GPT-6.1 Sol). My next dictation is formatted with that model, and the model's info shows what it is good for and what it costs, so I can trade quality for cost.

**Why this priority**: These are the newest text models. GPT-6 Luna is the cheapest listed model, and GPT-6.1 Sol / GPT-6 Astra cover harder formatting jobs.

**Independent Test**: Select each new text model in Settings, dictate a short text with a formatting prompt → formatted text is produced with no error; the info popover shows the description and price.

**Acceptance Scenarios**:

1. **Given** the Settings text model list, **When** the user opens it, **Then** it shows exactly the 10 models of the "Text model list" table, in that order.
2. **Given** a new text model is selected, **When** the user dictates and formatting runs, **Then** the formatted text is produced without errors, both on the first response and on follow-up messages in the same session.
3. **Given** the model info popover, **When** the user opens it, **Then** each new model shows a one-line description and its input/output price per 1M tokens, in the same style as existing entries.
4. **Given** a new text model was selected, **When** the user quits and relaunches the app, **Then** the same model is still selected.

---

### User Story 6 - Transcribe with GPT Transcribe (Priority: P1)

As a user, my recordings are transcribed with GPT Transcribe, the only speech-to-text model left. Its info shows its purpose and per-minute price.

**Why this priority**: Every other transcription model is removed in this release, so all dictation depends on it.

**Independent Test**: Dictate in English and in Russian → correct text appears; the speech-to-text picker shows one entry, GPT Transcribe; the info popover shows the description and "$0.0045 / min".

**Acceptance Scenarios**:

1. **Given** the Settings speech-to-text picker, **When** the user opens it, **Then** it contains one entry, GPT Transcribe, and the picker looks the same as before.
2. **Given** GPT Transcribe is selected, **When** the user records and stops, **Then** the recording is transcribed and the normal flow (formatting, paste) continues as before.
3. **Given** the user has vocabularies or a chosen recognition language, **When** transcription runs, **Then** those inputs are used the same way they were for the previous transcription models.
4. **Given** the model info popover, **When** the user opens it, **Then** GPT Transcribe shows a one-line description and its price per minute.

---

### User Story 7 - Move users off removed models (Priority: P1)

As a new user, the app starts with GPT Transcribe and GPT-6 Luna, without opening Settings. As an existing user who had a removed model selected (including the old defaults), after the update the app quietly uses the new default instead, and dictation keeps working. As an existing user on a kept text model, nothing changes.

**Why this priority**: The old defaults are removed, so most existing users are affected; dictation must not break after the update.

**Independent Test**: Fresh install → Settings shows GPT Transcribe and GPT-6 Luna. Upgrade an install that used GPT-4o Mini Transcribe and GPT-5.1 (explicitly or by default) → Settings shows GPT Transcribe and GPT-6 Luna, dictation works, no alert appears, and the log records both switches. Upgrade an install with GPT-5.4 selected → still GPT-5.4.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** the user opens Settings for the first time, **Then** the speech-to-text model is GPT Transcribe and the text model is GPT-6 Luna.
2. **Given** an existing install whose speech-to-text model is removed (explicitly selected or inherited from the old default), **When** the updated app starts, **Then** the speech-to-text model becomes GPT Transcribe.
3. **Given** an existing install whose text model is removed (explicitly selected or inherited from the old default), **When** the updated app starts, **Then** the text model becomes GPT-6 Luna.
4. **Given** a model was switched, **When** it happens, **Then** no alert or notice is shown to the user, and the diagnostic log records the old and new model.
5. **Given** an existing install with a kept text model selected, **When** the app is updated, **Then** that selection is unchanged.

---

### User Story 8 - See the price of every model (Priority: P3)

As a user comparing models, I see the current price of every model in the info popovers, so I can choose by cost.

**Why this priority**: Informational; it doesn't change what the app does.

**Independent Test**: Open the info popovers for both lists → every entry shows a price.

**Acceptance Scenarios**:

1. **Given** either info popover, **When** the user opens it, **Then** every entry shows its price (text: input/output per 1M tokens; speech-to-text: per minute).

---

### User Story 9 - Switch microphone while recording, and close the window at any moment (Priority: P1)

While recording in the floating window, the user picks another microphone (key 1 or the microphone menu): a built-in, USB or iPhone (Continuity) microphone, or Bluetooth headphones. Recording continues on the new microphone. The user can also close the window (Esc, ⌘W, the close button, or the global shortcut where it closes) or stop at any moment, including during a switch, and the microphone is then off. Today every switch to a specific microphone fails after about 2 seconds (only "System Default" works), and closing the window during a switch doesn't stop it, so the microphone can turn on after the window is gone. See [investigation.md §3](./investigation.md).

**Why this priority**: The microphone selector is unusable while recording, and a microphone that turns on after the window is closed is a privacy problem.

**Independent Test**: Start recording on System Default, press 1 to switch to each available microphone in turn, speak on each, then stop: each switch resumes recording and the result contains speech from the last microphone. Then start recording, switch to Bluetooth headphones and press Esc at once: the window closes within 1 second and the system microphone indicator turns off within 2 seconds and stays off.

**Acceptance Scenarios**:

1. **Given** a recording on System Default, **When** the user switches to a wired, built-in or USB microphone, **Then** recording restarts from zero on that microphone within 2 seconds; what was said before the switch is discarded.
2. **Given** a recording, **When** the user switches to Bluetooth headphones (including ones that must change to their microphone mode) or an iPhone microphone, **Then** recording resumes on it within 5 seconds.
3. **Given** a switch is in progress, **When** the window shows its state, **Then** it says the microphone is being switched (not "recording"), the timer pauses, and a cancel action is available.
4. **Given** the new microphone cannot be started within 5 seconds (including one automatic retry), **When** the time runs out, **Then** the window shows an error naming the microphone, and the user can pick another microphone from the menu or with key 1; picking one starts recording on it right away, with the same limits and retry as a switch.
5. **Given** a switch is in progress, **When** the user presses 1, 2 or 3 or tries to open a bottom-bar menu, **Then** nothing changes (the menus are disabled); the user can cancel the switch and then pick another microphone.
6. **Given** a switch is in progress or has just failed, **When** the user closes the window, **Then** the switch is cancelled, the window closes within 1 second, and the microphone is not turned on afterwards.
7. **Given** the user closed the window during a switch, **When** they open it again, **Then** recording starts normally on the selected microphone, with no leftover state from the cancelled switch.
8. **Given** Bluetooth headphones were switched to microphone mode for a switch that was then cancelled, **When** the window closes, **Then** the headphones return to their normal audio mode, as after a normal recording.
9. **Given** a switch is in progress, **When** the user presses stop, **Then** the switch is cancelled, the window returns to the ready-to-record state with the new microphone selected, and nothing is sent for transcription.

---

### User Story 10 - Prompt names fit in the floating window (Priority: P3)

When creating or editing a prompt in Settings, the user can enter a name of at most 30 characters. The field shows how many characters are used out of 30, so the limit is clear before it is reached. The prompt button in the floating window is as wide as the name needs, so a short name gives a short button, but it never grows into the buttons on the right (Start/Stop/Cancel, Exit).

**Why this priority**: Long names are cut off in the bottom bar, making prompts hard to tell apart; most existing names are already short.

**Independent Test**: In Settings › Prompts, create a prompt and type or paste a 45-character name: only the first 30 characters are kept, the counter shows 30/30, and the floating window shows the full name without truncation.

**Acceptance Scenarios**:

1. **Given** the user is editing a prompt name in Settings, **When** they type past 30 characters, **Then** further characters are not added and the counter shows "30/30".
2. **Given** the user pastes text longer than 30 characters into the name field, **When** the paste completes, **Then** only the first 30 characters are kept.
3. **Given** the user creates a new prompt, **When** the editor opens, **Then** the default name (e.g. "New prompt") is within the limit and the counter shows its length.
4. **Given** a prompt name of 30 characters, **When** it is selected in the floating window, **Then** the full name is visible in the bottom bar, with no truncation, in both interface languages (for wide characters such as CJK, see scenario 8).
7. **Given** prompts with names of different lengths (e.g. "Ask", "Rewrite with info-style"), **When** the user switches between them, **Then** the prompt button's width follows the name: short names give a narrow button, longer names a wider one, with the same padding on both sides.
8. **Given** a long microphone name and a long prompt name that together don't fit, **When** the bar is shown, **Then** the prompt button never overlaps or comes closer to the right-hand buttons (Start/Stop/Cancel, Exit) than the normal gap between bar buttons; the microphone title is shortened first, then the prompt name, and the output language last, each with "…".
5. **Given** a prompt saved before this release with a name longer than 30 characters, **When** the floating window shows it, **Then** the name is shortened with "…" and the stored name is not changed until the user edits it.
6. **Given** the user opens such a prompt in Settings, **When** the editor shows it, **Then** the counter shows the real length in a warning color (e.g. "42/30"), a short message asks to shorten the name, and saving is blocked until it is 30 characters or fewer.

---

### Edge Cases

- Login item registration requires user approval in System Settings → UI shows "needs approval" with a link; no false "on" state.
- Multiple copies of the app with the same identity exist on disk (e.g. old builds) → the copy the user runs from Applications is the one that starts at login. If Verborra is running from outside the Applications folder, Settings says so next to the "Launch at login" control and the diagnostic log records the app's location.
- Bluetooth microphone selected → the headset mode switch is shown as "Switching…" and has its own 5-second limit; the 5-second recording start limit (FR-007) begins after it. The switch can be cancelled with the hotkey or Esc like any other start.
- The user changes the login setting while macOS System Settings › Login Items is open → state stays consistent after reopening Verborra Settings.
- Audio device disappears or changes format while recording is starting → one automatic retry on the same microphone, then error with "Retry"; no hang, no automatic microphone switch.
- The user presses the hotkey while a start is in progress (including the automatic retry) → the start is cancelled and the window returns to the pre-recording stage; further presses behave as in that stage; no queue of stuck actions.
- The user presses only Fn and releases it in the shortcut field → nothing is saved (Fn alone is not a valid shortcut).
- The user chooses a shortcut that conflicts with an existing in-window shortcut (e.g. Esc, 1, 2, 3, ⌥C, ⌥V) → warned and rejected.
- Keyboards without a dedicated Fn key / external keyboards → Fn-based shortcut simply cannot be pressed there; other modifiers work.
- A prompt is deleted/renamed in Settings while the floating window is open → cycling uses the up-to-date list and falls back to the default if the selected prompt no longer exists.
- The microphone menu has only "System Default" → its title and separator are still shown; no two separators appear next to each other.
- The chosen microphone is unplugged during a switch → the switch fails with the US9 error, not a hang.
- Switching back to System Default after a failed switch works on the first try.
- The user switches microphone while not recording → only the selection changes; nothing starts.
- Audio recorded before a mid-recording switch is discarded (confirmed 2026-10-15); recording restarts on the new microphone, the timer and the maximum-length countdown start from zero, and stopping during a switch sends nothing for transcription.
- The right-hand button changes width (e.g. "Start" ↔ "Cancel" ↔ "Stop", or a longer global shortcut such as "🌐︎ ⌃ ⌥ ⌘ Space"): the space left for the prompt button shrinks or grows with it, so the gap is kept at all times.
- A prompt name made only of spaces or empty → handled as before (existing rules for empty names unchanged). Characters such as emoji, accented letters and CJK count as one character each, as the user sees them; a 30-character name in wide characters must still fit (the bar may grow wider).
- Clicking the stall test several times runs it once per click, one after another; the Settings window freezes during each run, which is expected.

**Model list (US5–US8)**

- OpenAI rejects a request to a new text model (not available for the user's account or region) → the user sees the existing clear API error message, which names the model and suggests choosing another one in Settings; the failure is logged with the model name.
- OpenAI rejects GPT Transcribe for the user's account → the user sees the same clear error naming the model, and the failure is logged. There is no other speech-to-text model to choose and the app does not retry with a hidden one, so dictation stays blocked for that user until their OpenAI access allows the model.
- A model accepts an optional request setting (for example, creativity/temperature) only in some configurations → the app sends that setting only when it is confirmed for that exact model and request; otherwise it leaves the setting out, so no request fails because of it.
- A saved selection refers to any model that isn't in the current list (a removed model, or an unknown value) → the app uses the current default for that list and logs the switch, without telling the user.
- The user switched to a new model, then downgrades to an older app version that doesn't know it → out of scope; the older version falls back to its own default.
- A new text model has a different context size → long sessions are trimmed to fit that model's context, as for existing models.
- Prices in OpenAI's list change after release → shown prices are informational; live price updates are not required.

## Requirements *(mandatory)*

### Functional Requirements

**Launch at login**

- **FR-001**: The "Launch at login" control MUST always display the actual system state of the login registration, not a stored preference value.
- **FR-002**: When the user's preference is "enabled" but the app is not registered (after an update or a previous failure), the app MUST attempt to register itself at startup.
- **FR-003**: When macOS requires user approval for the login item, the app MUST show this state in Settings and provide an action that opens the corresponding macOS settings page.
- **FR-004**: Registration and unregistration results, including failures and the resulting state, MUST be logged and, on failure, shown to the user.
- **FR-005**: On a fresh install, the app MUST ask the user once (during onboarding/first launch) whether to start at login, with "on" pre-selected, and MUST apply the answer immediately when the user completes onboarding. Existing users who never touched the setting (stored default "on", never registered) MUST be treated as "enabled" and registered per FR-002, without being asked again.
- **FR-006**: The app build MUST use local ad-hoc signing with Hardened Runtime (the owner has no Apple Developer team certificate). Because ad-hoc identity changes with each build, if login registration needs re-approval after an update, the Settings toggle MUST show "needs approval" with **Open Login Items** (FR-003).

**Responsiveness / hang prevention**

- **FR-007**: Starting a recording MUST either succeed or fail with a user-visible error within 5 seconds; the app MUST NOT freeze while doing so. For Bluetooth microphones the 5 seconds start after the headset mode switch, which is shown separately and has its own 5-second limit.
- **FR-008**: Audio setup steps (device selection, engine creation, format setup, start) MUST NOT block user input handling — hotkey, Esc, window buttons, and menu bar menu MUST remain responsive during and after a failure.
- **FR-009**: A mismatch between the audio device's actual format and the expected recording format MUST be detected and handled (adapt or fail gracefully), never leading to a freeze or crash.
- **FR-010**: Low-level failures raised by the audio subsystem MUST be caught, logged at ERROR level with context (step, device, formats, reason), and converted into a recoverable error state.
- **FR-011**: The app MUST detect when its main user interface is unresponsive for more than 2 seconds and write a WARN entry with context (current stage, active device, elapsed time) to the diagnostic log.
- **FR-012**: The diagnostic log MUST record the duration of each audio setup step at INFO level so that slow steps can be identified retrospectively.
- **FR-013**: When recording start fails, the app MUST automatically retry once on the same microphone (within the FR-007 time limit). If the retry also fails, the floating window MUST show the error with a "Retry" action; the user MUST be able to retry in the same session without restarting the app. The app MUST NOT switch to a different microphone automatically.
- **FR-013a**: Pressing the global hotkey while a recording start is in progress (including the automatic retry) MUST cancel the start, release any partially started audio capture, and return the floating window to the pre-recording stage within 1 second.
- **FR-045**: In Debug builds, Settings › Advanced MUST show a "Developer" section, placed last, with a "Simulate main-thread stall (3 s)" button and a one-line explanation (the app freezes for 3 seconds; a warning is logged). The button MUST freeze the main thread for 3 seconds so that FR-011 can be checked.
- **FR-046**: The stall test MUST NOT appear in the menu bar menu, and Release builds MUST NOT show the Developer section or the stall test anywhere.
- **FR-047**: The Developer section's title and explanation MUST be available in English and Russian.

**Microphone switching and closing (US9)**

- **FR-048**: Switching to any available microphone during a recording MUST resume recording on it: within 2 seconds for wired, built-in and USB microphones; within 5 seconds for Bluetooth and Continuity microphones.
- **FR-049**: A switch MUST follow the same start rules as FR-013: one automatic retry on the same microphone within a 5-second total limit, then an error. The Bluetooth headset mode change for a switch MUST fit within that limit, not be cut off by a shorter one.
- **FR-050**: Stopping the previous microphone and starting the new one MUST NOT run at the same time, and a switch MUST NOT fail merely because the previous microphone was still being stopped.
- **FR-051**: While a switch is in progress, the window MUST show a "switching microphone" state instead of "recording": the timer pauses and a cancel action is available.
- **FR-052**: Only one switch MAY run at a time. While a switch is in progress, keys 1–3 and the bottom-bar menus MUST be disabled; cancel and closing the window MUST stay available. A cancelled switch MUST NOT complete later.
- **FR-053**: A failed switch MUST show an error that names the microphone, and the user MUST be able to choose another microphone from that state (menu or key 1). Choosing one MUST start recording on it under the same rules as a switch (FR-048, FR-049).
- **FR-054**: Closing the window MUST cancel any switch or start in progress and close within 1 second. After the window is closed, no switch or start that began before closing MUST turn the microphone on.
- **FR-055**: Cancelling a switch MUST return Bluetooth headphones to normal audio mode if the switch had changed it.
- **FR-056**: Stopping during a switch MUST cancel the switch and MUST NOT send audio for transcription.
- **FR-057**: Each switch MUST be logged with the microphone name (not only its numeric id), the outcome (ok, failed, cancelled) and its duration.

**Shortcut recorder**

- **FR-014**: While the shortcut field is focused, the field MUST show the currently held modifier keys in real time, updating as modifiers are added or released.
- **FR-015**: Supported modifiers MUST be Fn (Globe), Control, Option, Shift, and Command, in any combination.
- **FR-016**: A shortcut MUST consist of at least one modifier plus exactly one regular (non-modifier) key; pressing the regular key MUST save the shortcut and end focus.
- **FR-017**: A regular key pressed without modifiers MUST NOT be saved; the user MUST see a hint explaining that a modifier is required.
- **FR-018**: Esc while recording MUST cancel and keep the previous shortcut; the field MUST also offer a way to reset to the default shortcut.
- **FR-019**: Shortcuts that include Fn MUST work globally (from any application), the same as other shortcuts.
- **FR-020**: Key events intended for the shortcut field MUST NOT be intercepted by the floating window or any other part of the app, regardless of whether the floating window is open.
- **FR-021**: Shortcuts that conflict with macOS reserved shortcuts or the floating window's own keys (Esc, 1, 2, 3, ⌥C, ⌥V) MUST be rejected with a warning.
- **FR-022**: Shortcut changes MUST be logged (old → new value).

**Floating window**

- **FR-023**: The prompt selector MUST be removed from the top of the floating window and placed in the bottom bar. The bottom bar MUST show the selectors in this order, left to right: microphone, output language, prompt.
- **FR-024**: In the pre-recording stage, number keys MUST match the selector positions: 1 = next microphone, 2 = next output language, 3 = next prompt; each with wrap-around from last to first.
- **FR-025**: Each of the three selectors MUST display its number hint (1, 2, 3) consistently with existing hint styling.
- **FR-026**: Prompt cycling order MUST match the order of prompts shown in the prompt selector menu; microphone cycling order MUST match the order shown in the microphone menu.
- **FR-027**: Selecting a prompt via key 3 MUST have the same effect as selecting it from the menu. The choice applies to the current session only; every new session MUST start with the default prompt configured in Settings, and the floating window MUST NOT change that default.
- **FR-028**: Shortcut hints in the floating window (including Start/Stop) and the Settings shortcut field MUST display Fn as the globe symbol 🌐︎ (as macOS menus show it), placed first in the modifier order (🌐︎ ⌃ ⌥ ⇧ ⌘), e.g. "🌐︎ ⌥ Space".
- **FR-029**: Prompt changes via key 3 MUST be logged as user actions, like microphone and language changes.
- **FR-043**: Each of the three bottom-bar menus MUST begin with a non-selectable title line followed by a separator: "Input device" (microphone), "Output language" (language), "Using prompt" (prompt), translated into English and Russian.
- **FR-044**: Choosing a menu title MUST NOT change any selection, and cycling with keys 1–3 MUST skip it.

**Prompt names (US10)**

- **FR-058**: Prompt names MUST be limited to 30 user-visible characters when creating a prompt and when editing a prompt's name in Settings. The name field MUST NOT accept input beyond 30 characters; pasted text MUST be cut to the first 30.
- **FR-059**: The name field MUST show a counter of used characters out of 30 (e.g. "14/30").
- **FR-060**: Prompts saved earlier with names longer than 30 characters MUST NOT be changed automatically. The floating window MUST shorten them for display with "…". In Settings the counter MUST show the real length in a warning color, a message MUST ask to shorten the name, and saving MUST be blocked until it is within the limit.
- **FR-061**: A prompt name of up to 30 characters MUST be shown in full in the floating window's prompt selector whenever the bar has room for it after the other buttons; for 30 Latin characters with a typical microphone name it always does.
- **FR-063**: The prompt button's width MUST follow the selected prompt's name (narrow for short names, wider for long ones), up to a maximum. The maximum MUST keep at least the normal gap between bar buttons to the right-hand buttons (Start/Stop/Cancel, Exit) at all times, including when those buttons change label or the global shortcut is long. When space runs out, the microphone title MUST be shortened first, then the prompt name, then the output language, each with "…"; buttons MUST never overlap.
- **FR-065**: In the pre-recording stage the window MUST have a fixed height of 200 pt (previously 220 pt) in every state, and every pre-recording view (including errors and "no microphone access") MUST fit without clipping. The chat stage keeps its existing behaviour (expands to half the screen height).
- **FR-064**: The microphone and output-language buttons MUST follow the same width rule as the prompt button (FR-063): width follows the selected title with no fixed cap, the three buttons share the room left before the right-hand buttons, and a title is shortened with "…" only when the row runs out of space, in the order microphone, prompt, output language.
- **FR-062**: The default name for a new prompt and all built-in prompt names, in every supported language, MUST be 30 characters or fewer.

**Model list (US5–US8)**

- **FR-030**: The text model list MUST contain exactly the 10 models in the "Text model list" table, in that order.
- **FR-031**: The speech-to-text list MUST contain exactly one model, GPT Transcribe, shown in the same picker as today.
- **FR-032**: The models in the "Removed in this release" table MUST NOT be selectable or used for requests after the update.
- **FR-033**: Each new model MUST work end to end wherever the app uses that kind of model: text models — formatting, streaming output, follow-up messages and translation to the chosen output language; GPT Transcribe — transcription with the chosen recognition language and vocabularies.
- **FR-034**: Every listed model MUST show a one-line description and its price (text: input/output per 1M tokens; speech-to-text: per minute) in the model info popover.
- **FR-035**: Whether a model accepts each optional request setting MUST be defined per exact model (not per model family) and confirmed for every selectable model before release. A setting that isn't confirmed for a model MUST be left out of that model's requests.
- **FR-036**: For new installs, the default speech-to-text model MUST be GPT Transcribe and the default text model MUST be GPT-6 Luna.
- **FR-037**: On the first start after the update, any user whose effective model (explicitly selected or inherited from the old default) is not in the current list MUST be moved to the default of that list: GPT Transcribe for speech-to-text, GPT-6 Luna for text. Users on a kept text model MUST keep it.
- **FR-038**: A model switch under FR-037 MUST happen without any alert or notice to the user, and MUST be logged with the old and new model.
- **FR-039**: The selected model MUST persist across app restarts, including the new models.
- **FR-040**: When a request fails because the selected model is unavailable, the error shown to the user MUST name the model, and the failure MUST be logged with the model name. For text models the error MUST also suggest choosing another model in Settings. The app MUST NOT retry with a model the user didn't select.
- **FR-041**: New descriptions MUST be available in every language the app supports (English and Russian); descriptions of removed models MUST be removed.
- **FR-042**: The models in the "Not added" table MUST NOT be added by this feature.

### Key Entities

- **Login Item State**: The real registration status of the app as a login item (enabled / not registered / requires approval / not found) and the user's intent (want enabled or not).
- **Global Shortcut**: A set of modifiers (Fn, Control, Option, Shift, Command; at least one) plus one regular key; persisted, displayed with standard macOS symbols.
- **Session Selection**: The current session's microphone, output language, and prompt in the floating window; each cyclable via its number key (1, 2, 3).
- **Microphone switch**: A request to move a running recording to another microphone: target microphone, start time, state (in progress, done, failed, cancelled); belongs to one floating-window session, and closing the window ends it.
- **Prompt name**: The label of a saved prompt; at most 30 user-visible characters for new and edited names; older longer names are kept until edited.
- **Diagnostic Event**: Log entries for audio setup steps (with durations), audio failures (ERROR), unresponsiveness warnings (WARN), login item changes, and shortcut/prompt changes, and model-selection migrations.
- **Text model option**: a selectable formatting model — name, one-line description, input/output price per 1M tokens, context size, and the optional request settings it accepts.
- **Speech-to-text model option**: a selectable transcription model — name, one-line description, price per minute.
- **Model selection**: the user's chosen model of each kind. If it doesn't match a listed model, the list's default is used.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With "Launch at login" enabled, the app is running after 10 out of 10 consecutive logins/restarts, on the same installed build. After installing a new build, at most one re-approval in Login Items is needed, and Settings points to it.
- **SC-002**: The "Launch at login" control matches the actual system state in 100% of checks (including after the user changes it in macOS System Settings).
- **SC-003**: Over 2 weeks of normal daily use, the number of force-quits required is 0 (baseline: 2 hangs + 2 crashes in 4 days).
- **SC-004**: 100% of recording starts either begin recording or show an error within 5 seconds, including after 15+ minutes of idle.
- **SC-005**: Every hang longer than 2 seconds and every audio setup failure leaves a WARN/ERROR entry in the local diagnostic log (baseline: 0 entries for the observed incidents).
- **SC-006**: In 20 consecutive attempts, the shortcut field captures the intended combination on the first try in 20/20 cases, with and without the floating window open.
- **SC-007**: Held modifiers appear in the shortcut field with no perceptible delay (under 100 ms).
- **SC-008**: A shortcut using Fn + key opens the floating window from any app in 10/10 attempts.
- **SC-009**: In the floating window, the user can change microphone, output language, and prompt using only keys 1, 2, 3 (in that order, matching the bar) without touching the mouse.
- **SC-016**: 10 out of 10 mid-recording switches to each of a built-in or USB microphone, Bluetooth headphones and an iPhone microphone resume recording within the FR-048 limits.
- **SC-017**: In 10 out of 10 tries of closing the window during a switch, the window closes within 1 second and the system microphone indicator is off within 2 seconds and stays off for at least 10 seconds.
- **SC-018**: After any failed or cancelled switch, the next recording starts on the first try in 10 out of 10 tries; no test-session log shows a switch that failed because the previous microphone was still being stopped.
- **SC-019**: All three bottom-bar menus show the correct title first in English and Russian, and every prompt name of up to 30 Latin characters is shown in full. In 100% of checks (names of 3, 15, 30 Latin and 30 CJK characters; short and long microphone names; English and Russian language names; Start, Cancel and Stop labels; short and long global shortcuts), each of the three selector buttons fits its title or the room left and never overlaps or touches the right-hand buttons.
- **SC-020**: It is impossible to save a prompt name longer than 30 characters from Settings.
- **SC-021**: The pre-recording window is 200 pt tall in every state (0 pt change across idle, starting, recording and errors in 10 of 10 checks), and every error and permission view is fully visible without clipping.

- **SC-010**: Each of the 7 new models completes 10 out of 10 dictations (record → transcribe → format → paste) without an error caused by the model choice.
- **SC-011**: Every one of the 11 selectable models completes at least one dictation with no request rejected because of an unsupported setting.
- **SC-012**: 100% of entries in both info popovers show a price.
- **SC-013**: After upgrading, 100% of users who were on a removed model (including the old defaults) can dictate on their first try, with GPT Transcribe and GPT-6 Luna selected, and 100% of users on a kept text model still have it selected.
- **SC-014**: A fresh install starts with GPT Transcribe and GPT-6 Luna selected without any user action.
- **SC-015**: Transcription quality with GPT Transcribe is at least as good as with GPT-4o Mini Transcribe on the same 10 test recordings (English and Russian), judged by word errors (measured before release).

## Assumptions

- "Launch at login" is offered during onboarding/first launch with "on" pre-selected; existing installs keep their current "enabled" intent and get registered without an extra prompt.
- Fn is supported only as a modifier combined with a regular key; Fn alone (or any modifier alone) is not a valid global shortcut.
- Only the single existing global shortcut (open/toggle the floating window) is affected; the unused legacy "recording key" setting may be removed.
- In-window shortcuts (1, 2, 3, Esc, ⌥C, ⌥V) stay fixed and are not user-configurable in this feature.
- The menu titles use the owner's wording ("Input device", "Output language", "Using prompt"); Russian: "Устройство ввода", "Язык вывода", "Используемый промпт". They are labels, not options.
- The prompt name limit is exactly 30 characters and applies to the two places where names are entered: creating and editing a prompt in Settings.
- In US9, "sources" means microphones and "windows" means the floating window, as the 2026-10-15 log shows. Keeping audio from before a switch (joining two microphones) is out of scope.
- Two other problems seen in the 2026-10-15 log — tests writing into the real app log, and long main-thread stalls while granting Accessibility — are out of scope (noted in investigation.md §3).
- The hang root cause is most likely in audio setup at recording start (see [investigation.md](./investigation.md)); the requirements cover both prevention and diagnostics so that any remaining cause becomes visible in logs.
- Hang diagnostics follow existing logging rules (levels, rotation, retention, no sensitive data).
- The app is distributed to the user's own machine(s); a stable development or distribution signing identity is available.
- Respecting the constitution: changes stay within the existing native macOS stack and the minimalist floating window design.
- All ten user stories (US1–US10) ship together in one release; no story ships on its own (US9, US10 and the US2/US4 amendments were merged from former specs 016–018 on 2026-10-15). The 2-week soak (SC-003) is measured after that release and doesn't hold it back. If the release comes out after 2026-12-11, users still on GPT-5 Nano or GPT-5 Mini get an OpenAI error in the current app version from that date until they install the release; this risk is accepted.

**Model list (US5–US8)**

- Model names, IDs, prices and shutdown dates come from the user's description (stated as verified against OpenAI's documentation on 2026-10-14). Planning re-confirms them, plus each model's context size, endpoint compatibility and accepted request settings. A model that turns out not to work with the way the app sends requests is dropped from this feature and the user is told.
- GPT Transcribe accepts a finished recording the same way the previous transcription models did.
- GPT-5.4 Pro and GPT-5.5 Pro are removed because the app only uses Chat Completions; adding Responses API support to bring them back is a separate feature.
- Removing all deprecated models now is deliberate, even though OpenAI keeps them running until 2027; users lose access to them earlier than OpenAI requires.
- Moving every removed text model to GPT-6 Luna is deliberate: users of GPT-5.1 move to a cheaper model that may format differently on hard prompts.
- Prices are shown for information only; the app doesn't calculate or track spending.
- The "advanced" (GPT-6.1 Sol) and "premium" (GPT-6 Astra) recommendations are shown in the model descriptions only; the app doesn't get separate advanced/premium settings.
- Live transcription, voice conversation and speaker labelling are out of scope.
