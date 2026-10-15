# Quickstart: Validating Reliability, Shortcuts & Model List Update

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Contracts**: [contracts/](./contracts/)

Each scenario lists its success criteria (SC) or acceptance scenarios (AS). Expected behaviour is defined in the contracts and isn't repeated here.

## Prerequisites

- macOS 15+, Xcode 16. No Apple certificate is needed: the build is signed ad-hoc.
- Verborra has Microphone and Accessibility access (Accessibility is needed for 🌐︎ shortcuts).
- `jq` installed (for log checks).
- SwiftLint, development-only (constitution P5, never part of the app): `brew install swiftlint`. If Homebrew reports its directories aren't writable, run `sudo chown -R $(whoami) /opt/homebrew` first. Lint config: repo-root `.swiftlint.yml` (task T003).
- Log query helper:

  ```bash
  vlog() { cat ~/Library/Application\ Support/Verborra/Logs/*.jsonl | jq -c "$1"; }
  ```

## 0. Build, sign, install

```bash
xcodebuild test  -project Verborra.xcodeproj -scheme Verborra -destination 'platform=macOS'
xcodebuild build -project Verborra.xcodeproj -scheme Verborra -configuration Release -derivedDataPath build/dd
rm -rf /Applications/Verborra.app && cp -R build/dd/Build/Products/Release/Verborra.app /Applications/
codesign -dv /Applications/Verborra.app 2>&1 | grep -E 'TeamIdentifier|Signature|flags'
```

**Expected**: tests pass; the build has no warnings; `flags=0x10002(adhoc,runtime)` (ad-hoc plus Hardened Runtime, constitution P4, FR-006).

One-time cleanup of stale copies with the same bundle ID (operational, see research R4):

```bash
mdfind "kMDItemCFBundleIdentifier == 'com.apeek.Verborra'"   # remove every copy except /Applications
```

## 1. Launch at login (US1)

| # | Steps | Expected | Covers |
|---|---|---|---|
| 1.1 | Existing install (`defaults read com.apeek.Verborra launchAtLogin` → key absent). Launch the new build. | Log shows `Login item registered at launch`; Verborra appears in System Settings › General › Login Items; the Settings toggle is on. | FR-002, FR-005 |
| 1.2 | Log out and in (or restart) 10 times, once after reinstalling a rebuilt app (step 0). | Menu bar icon present and hotkey works every time. | SC-001, AS 1.1, AS 1.4 |
| 1.3 | Disable Verborra in System Settings › Login Items, then open Verborra Settings. | Toggle off, "needs approval" caption, **Open Login Items** opens the right page. Re-enable it there and return: the toggle is on. | FR-003, SC-002, AS 1.3 |
| 1.4 | Fresh-install simulation: `defaults delete com.apeek.Verborra` and remove the login item, then launch. | The onboarding Completion step shows "Start Verborra at login", **on**. Finish: registered immediately. Run it again with the toggle off: not registered. | FR-005, AS 1.2 |
| 1.5 | Force a failure, e.g. run a copy from `~/Downloads` (not signed by the team, or translocated), and flip the toggle. | Toggle reverts to the real state; red error caption; ERROR in the log. Settings also shows "Verborra is running from …/Downloads. Move it to Applications so the right copy starts at login.", and the launch log has `Login item reconcile` with `appPath` pointing at the Downloads copy. | FR-004, AS 1.5 |

## 2. No hangs at recording start (US2)

| # | Steps | Expected | Covers |
|---|---|---|---|
| 2.1 | Start and stop 30 recordings on the built-in mic. | Every start succeeds; one `Audio setup timings` line (with `firstBufferMs`) and one `Recording ready` line per start; median `hotkeyToReadyMs` ≤ 300 ms (typically under 100 ms). | FR-012, Principle 3 |
| 2.2 | Leave the app idle ≥ 15 min, then press the hotkey (repeat on 3 different days or after sleep/wake). | Recording or an error appears within 5 s; the menu bar and Esc respond throughout. | SC-004, AS 2.1, FR-008 |
| 2.3 | Stale-format reproduction: in Audio MIDI Setup switch the mic between 44.1 kHz and 48 kHz, then immediately start a recording. Also try an external USB mic and AirPods. | No freeze or crash. Either it records (log shows `recreatedForStaleNode=true` when applicable) or shows `recordingStartFailed` with Retry. | FR-009, AS 2.2 |
| 2.4 | Unplug a USB mic right after pressing the hotkey. | Automatic retry on the **same** device, then an error with **Retry** within 5 s; the microphone selection is unchanged. Plug it back in and press Retry: it records. | FR-013, Edge case |
| 2.5 | Press the hotkey, then press it again immediately (and also Esc) while the window shows "Starting microphone…". | The window returns to the pre-recording stage within 1 s; `Recording start cancelled` is logged; the next hotkey press starts normally. | FR-013a, AS 2.3 |
| 2.6 | Watchdog self-test (DEBUG build only): Settings › Advanced › Developer › "Simulate main-thread stall (3 s)". Check the menu bar menu has no such item. In a Release build, check Advanced has no Developer section. | The app freezes ~3 s; one WARN `Main thread unresponsive` with `stage`/`deviceName`, then INFO `Main thread recovered`. Menu bar: only Settings and Quit. Release: no Developer section. | FR-011, FR-045, FR-046, FR-047, SC-005 |
| 2.7 | `vlog 'select(.level=="ERROR" or .level=="WARN")'` after 2.3–2.6 | Every induced failure or stall has an entry with step, device and reason. | FR-010, SC-005 |
| 2.9 | Mid-recording switch: start recording on System Default, then switch (key 1 and the menu) to the built-in mic, a USB mic, AirPods (from A2DP) and an iPhone mic, 10 times each. Speak after each switch, then stop. | Each switch shows "Switching to <name>…", the timer pauses, keys 1–3 and the menus are disabled; recording resumes within 2 s (wired/built-in/USB) or 5 s (Bluetooth/iPhone) and restarts from 0:00; the transcript contains speech from the last microphone only. One `Microphone switch outcome=ok` per switch with names, not ids. No `Previous audio host still busy` lines. | FR-048…FR-052, FR-057, SC-016 |
| 2.10 | Close during a switch: start recording, switch to AirPods, press Esc at once. Repeat with ⌘W, the close button and the global shortcut; 10 times in total. | The window closes within 1 s; the macOS microphone indicator turns off within 2 s and stays off ≥ 10 s; AirPods return to normal audio; `Microphone switch outcome=cancelled`. The next hotkey press records on the first try. | FR-054, FR-055, FR-056, SC-017, SC-018 |
| 2.11 | Failed switch: start recording, switch to a USB mic and unplug it during "Switching…". Then press 1 (or pick System Default). | Error naming the USB mic within 5 s (`outcome=failed`). Picking another microphone starts recording on it right away. | FR-053, SC-018 |
| 2.8 | Soak: normal daily use for 2 weeks. | 0 force-quits; no new `Verborra-*.ips` caused by audio setup. Any WARN entries are triaged. | SC-003 |

## 3. Shortcut recorder and Fn (US3)

| # | Steps | Expected | Covers |
|---|---|---|---|
| 3.1 | Settings › Hotkeys: click the field, hold ⌥, then add ⇧, then release both. | Shows `⌥`, then `⌥ ⇧` with no visible delay, then the placeholder. | FR-014, SC-007, AS 3.1/3.2/3.5 |
| 3.2 | Hold ⌃⌥ and press K. | Saves `⌃ ⌥ K`, the field loses focus, ⌃⌥K opens the overlay from Safari, Notes and Terminal. Log `Global shortcut changed` old → new. | FR-016, FR-022, AS 3.3 |
| 3.3 | Hold 🌐︎ and press Space (Fn+Space). | Saves `🌐︎ Space`. From any app it opens the overlay 10/10 times, and **no space character is typed** in the target app. | FR-015, FR-019, SC-008, AS 3.4 |
| 3.4 | Press ↑, F5 and Home alone (no Fn held) while the 🌐︎ shortcut is active. | They work normally in the frontmost app and don't trigger Verborra. | R14 false-positive guard |
| 3.5 | In the field: press `K` alone; press Esc; press ⌥1; press ⌘Q; press ⌃↑ (Mission Control). | Hint "modifier required"; cancel and keep the previous; "used inside the Verborra window"; "used by Verborra's menu"; "reserved by macOS". The previous shortcut is kept each time. | FR-017, FR-018, FR-021, AS 3.6/3.7/3.9 |
| 3.6 | Click **Reset to default**. | Shortcut is `⌥ Space`. | FR-018 |
| 3.7 | Open the overlay (and leave it open), switch to Settings, record shortcuts 20 times with varied ⌥ and ⌥⇧ combos. | 20/20 captured on the first try; the overlay doesn't react. | FR-020, SC-006, AS 3.8 |
| 3.8 | Revoke Accessibility while a 🌐︎ shortcut is set. | Settings shows "🌐︎ shortcuts need Accessibility access". Grant it again: the shortcut works again without restarting. | Principle 4 |

## 4. Floating window (US4)

| # | Steps | Expected | Covers |
|---|---|---|---|
| 4.1 | Open the overlay. | No header at the top. The bottom bar shows Microphone `1`, Language `2`, Prompt (e.g. "Speech To Text") `3`, and Start shows the formatter output (e.g. `🌐︎ Space`). | FR-023, FR-025, FR-028, AS 4.1/4.6 |
| 4.2 | Create 3 prompts in Settings. Press 3 four times. | Cycles in menu order and wraps around; `Prompt changed source=key` is logged each time. | FR-024, FR-026, FR-029, AS 4.2 |
| 4.3 | With a single prompt, press 3. | Nothing changes and nothing breaks. | AS 4.3 |
| 4.4 | Press 1 and 2. | Next microphone and next language, both in menu order. | AS 4.4 |
| 4.5 | Click the prompt menu and pick a prompt. | Same effect as key 3 (`source=menu`). | AS 4.5, FR-027 |
| 4.6 | Pick a non-default prompt, close the overlay, reopen it. | The Settings default prompt is selected again. | FR-027 |
| 4.7 | During starting, a microphone switch and processing, press 1, 2 and 3. Then press them while recording (Auto-record on). | No selection changes while starting, switching or processing. While recording they work (1 starts a switch). | AS 4.7, FR-052 |
| 4.8 | With the overlay open, delete the selected prompt in Settings, then press 3. | Falls back to the default prompt; no crash. | Edge case |
| 4.9 | Use only the keyboard: 1, 2, 3, then the hotkey to record. | All selections are made without the mouse. | SC-009 |
| 4.10 | Open each of the three menus in English, then switch the interface to Russian and repeat. Click each title line. With only "System Default" available, open the microphone menu. | First lines: "Input device" / "Output language" / "Using prompt" (ru: "Устройство ввода" / "Язык вывода" / "Используемый промпт"), shown as non-selectable titles with a separator; clicking does nothing; no two separators touch. | FR-043, FR-044, SC-019 |
| 4.11 | Settings › Prompts: create a prompt, type 45 characters, then paste 45 characters. Name one exactly 30 Latin and one 30 CJK characters; select each in the overlay. | Typing stops at 30, paste is cut to 30, counter `30/30`. Both 30-character names show in full in the bar; the microphone title shrinks first if needed. | FR-058, FR-059, FR-061, SC-019, SC-020 |
| 4.13 | Switch between prompts named "Ask", "Rewrite with info-style" and a 30-character name. Then select a USB mic with a long name and a 30-character CJK prompt; set a long shortcut (e.g. `🌐︎ ⌃ ⌥ ⌘ Space`); start recording (Start → Cancel → Stop). | The prompt button's width follows each name. In every case there is at least the normal gap before Start/Stop/Cancel and Exit; nothing overlaps. When space runs out the microphone title shortens first, then the prompt name with "…". | FR-063, SC-019 |
| 4.14 | Switch the microphone between a short and a long name (e.g. "AirPods" ↔ "MacBook Pro Microphone" ↔ a USB mic with a 40-character name) and the output language between "English" and "Русский". | Each button's width follows its title like the prompt button (no fixed width); the 40-character microphone name shows in full when there's room, otherwise it is the first to shorten with "…"; there is always at least the normal gap before Start/Stop/Cancel and Exit. | FR-064, SC-019 |
| 4.15 | Open the window (idle), start recording, stop, and cancel a start; then cause an error with Retry (e.g. unplug the selected USB mic during start) and revoke microphone access. | The window is 200 pt tall in every state and never changes height; the error and "no microphone access" views are fully visible (nothing clipped). | FR-065, SC-021 |
| 4.12 | Edit `prompts.json` (app quit) to give a prompt a 42-character name; relaunch; open it in Settings and select it in the overlay. | Settings: `42/30` in red, "shorten the name" message, Save disabled until ≤ 30. Overlay: first 29 characters + "…". The file is unchanged until saved. | FR-060 |

## 5. Model list (US5–US8)


### Prerequisites (in addition to the ones above)

- Same toolchain as above (Xcode 16, SwiftLint development-only); nothing extra to install.
- An OpenAI API key with access to the GPT-6, GPT-5.6 and `gpt-transcribe` models, saved in the app (Keychain) and exported as `OPENAI_API_KEY` for 5.2.
- Diagnostic log level set to **DEBUG** (Advanced Settings).
- Logs: `~/Library/Application Support/Verborra/Logs/`.

### 5.1 Build, lint, unit tests

```sh
xcodebuild test -project Verborra.xcodeproj -scheme Verborra -destination 'platform=macOS'
swiftlint lint Verborra VerborraTests
```

Expected: the build has no warnings, all tests pass (including the rewritten `LLMModelTests` and `FormattingServiceTests`), and SwiftLint is clean on the changed files.

### 5.2 Live capability probe (before release, FR-035, SC-011)

Check every model on the [request contract](./contracts/openai-requests.md) table once, using its exact planned request shape:

```sh
# model|temperature|reasoning_effort ("-" = omit), per the request contract
for row in gpt-5.2'|0.2|-' gpt-5.4-mini'|-|-' gpt-5.4'|0.2|-' gpt-5.5'|0.2|-' \
           gpt-5.6-terra'|-|none' gpt-5.6-sol'|-|none' gpt-6-luna'|-|none' \
           gpt-6-sol'|-|none' gpt-6.1-sol'|-|low' gpt-6-astra'|-|low'; do
  IFS='|' read -r m t e <<<"$row"
  body=$(jq -n --arg m "$m" --arg t "$t" --arg e "$e" '{model:$m, max_completion_tokens:4000,
    messages:[{role:"system",content:"Fix punctuation."},{role:"user",content:"привет как дела"}]}
    + (if $t=="-" then {} else {temperature:($t|tonumber)} end)
    + (if $e=="-" then {} else {reasoning_effort:$e} end)')
  out=$(curl -s -w '\n%{time_total}' https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer $OPENAI_API_KEY" -H 'Content-Type: application/json' -d "$body")
  secs=${out##*$'\n'}; resp=${out%$'\n'*}
  echo "$resp" | jq -r --arg m "$m" --arg s "$secs" \
    '"\($m): \(.error.code // .choices[0].finish_reason) len=\(.choices[0].message.content // "" | length) \($s)s"'
done
```

Expected: every planned request returns `stop` with non-empty text. Record the error code, `finish_reason`, text length and time for each model in `research.md` R21:
- A kept model with `temperature` that returns 400 → set `supportsTemperature = false` for that case.
- A new model that accepts `temperature` → leave it `false` (not needed; it stays omitted).
- `gpt-5.6-sol` must accept `reasoning_effort: "none"`; if it doesn't, change it to `low` in the data model.
- A kept model that returns `length`, empty text, or takes more than 2× the slowest new model's time → set its `reasoningEffort` to its lowest supported value and probe again (R20).
- Any other failure → remove the model per research R28. If it's `gpt-6-luna` or `gpt-transcribe`, stop and ask the user.

Transcription: send one short WAV with `model=gpt-transcribe`, `languages[]=ru`, `response_format=json`. Expected: HTTP 200 with a non-empty `text`.

### 5.3 Fresh install defaults (US7, FR-036, SC-014)

```sh
defaults delete com.apeek.Verborra
```

Launch and finish onboarding. Expected: Settings shows **GPT Transcribe** and **GPT-6 Luna**, and the log has no `Model selection migrated` events.

### 5.4 Upgrade migration (US7, FR-037, FR-038, FR-039, SC-013)

| Setup before launching the new build | Expected after launch |
|---|---|
| `defaults write com.apeek.Verborra onboardingCompleted -bool YES` and no model keys | GPT Transcribe and GPT-6 Luna; 2 events with `reason=inheritedDefault`, `old=gpt-4o-mini-transcribe` / `gpt-5.1` |
| `selectedLLMModelRawValue gpt-5-mini`, `selectedSTTModelRawValue whisper-1` | GPT Transcribe and GPT-6 Luna; 2 events with `reason=removed` |
| `onboardingCompleted -bool YES`, `selectedLLMModelRawValue gpt-5.4`, no STT key | GPT-5.4 is unchanged; STT becomes GPT Transcribe (1 event, `reason=inheritedDefault`) |
| `selectedLLMModelRawValue gpt-5.5-pro` | GPT-6 Luna (1 event, `reason=removed`) |

In every case: no alert is shown, dictation works on the first try, and relaunching produces no new migration events (G3).

### 5.5 End-to-end dictation (US5, US6, FR-033, SC-010)

For each of the 7 new models (GPT Transcribe plus the 6 text models): run 10 dictations, and for each of the 4 kept text models one dictation (SC-011) (record → transcribe → format → paste), including a follow-up message in the floating window, with English and Russian recognition languages and an output language different from the input language.

Expected: 10 out of 10 with no model-caused errors. The DEBUG log shows `reasoningEffort` and `temperature` matching the contract, and the transcription request includes `languages[]` and not `language`.

### 5.6 Settings and popovers (US8, FR-030, FR-031, FR-032, FR-034, FR-041, FR-042, SC-012)

Open both info popovers in English and Russian UI. Expected: the STT popover has 1 entry; the text popover has 10 entries in order and scrolls; every entry shows a price; none of the removed models appear.

### 5.7 Model unavailable (FR-040)

Temporarily point a debug build at a non-existent model ID (or use a key without GPT-6 access). Expected: a text model shows "…isn't available for your OpenAI account. Choose another text model in Settings."; speech-to-text shows the message without the suggestion. There is no retry, and an ERROR log entry includes the model ID and the error code.

### 5.8 Transcription quality (SC-015)

On the same 10 recordings (5 EN, 5 RU), compare word errors between GPT Transcribe (new build) and GPT-4o Mini Transcribe (previous release build or curl). Expected: GPT Transcribe ≤ GPT-4o Mini Transcribe.

## Done when

All rows and §5 checks pass, `xcodebuild test` is green, the build has 0 warnings and SwiftLint is clean. Row 2.8 (2-week soak) is tracked after merge.
