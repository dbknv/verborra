# Investigation Notes: 015 Reliability & Shortcut Fixes

**Date**: 2026-10-14
**Purpose**: Root-cause evidence gathered before specification. Input for `/speckit-plan` (research.md).
These notes are technical on purpose; the spec itself stays implementation-agnostic.

---

## 1. Launch at login does not work

### Current implementation

- `Verborra/Models/AppSettings.swift:178-179` — `@AppStorage("launchAtLogin") var launchAtLogin: Bool = true` (default **true**, `@ObservationIgnored`).
- `Verborra/Views/SettingsView.swift:147-150` — toggle bound to the stored flag; calls `updateLaunchAtLogin` only when the user flips it.
- `Verborra/ViewModels/SettingsViewModel.swift:210-226` — the only place `SMAppService.mainApp.register()/unregister()` is called. No `SMAppService.mainApp.status` check, no `.requiresApproval` handling, no registration or re-sync at app launch.

### Evidence on this machine

- `defaults read com.apeek.Verborra` has **no** `launchAtLogin` key → the toggle was never flipped; it shows "on" purely from the code default.
- Verborra is **not** present in System Events login items.
- `/Applications/Verborra.app` (1.3.0) is **ad-hoc signed** (`Signature=adhoc`, no TeamIdentifier) — differs from `project.yml` (Apple Development, team G292C8CN3X).
- 4 additional copies with the same bundle id exist in `builds/` folders (this repo and the old `verborra-moved-to-github` repo).
- No launch-at-login / SMAppService events in JSONL logs.

### Root causes (ranked)

1. **Toggle displays an unapplied default.** Default `true`, but `register()` runs only on toggle change → the login item was never registered.
2. **Ad-hoc signing** → unstable code identity between builds; a previous registration can become stale after replacing the app.
3. **No status handling** — `.requiresApproval` (disabled in System Settings › Login Items) or `.notFound` is never reflected in UI.
4. Minor: `@ObservationIgnored` property may not refresh the toggle.

### Immediate workaround

Flip the toggle off → on once, or enable Verborra in System Settings › General › Login Items.

---

## 2. Intermittent hang (force-quit required)

Logs: `~/Library/Application Support/Verborra/Logs/*.jsonl` (2026-10-12 … 10-14). Crash reports: `~/Library/Logs/DiagnosticReports/Verborra-2026-10-11-132747.ips`, `Verborra-2026-10-13-193347.ips`. No `.hang`/`.spin` files. Logs contain only INFO/DEBUG — **zero WARN/ERROR**, i.e. the failures were invisible to logging.

### Episodes (UTC)

| Episode | Last events | Outcome |
|---|---|---|
| **Hang A** 2026-10-12 18:48 | Hotkey → `startRecording` → "Preparing audio engine" (18:48:29.985), then total silence (not even hotkey events) | Force-quit; relaunch 18:48:59 |
| **Hang B** 2026-10-13 17:33 | "Installing recording tap" (tap 48000 Hz, input node reported 44100 Hz); never reached "Recording on device" (normally ≤0.14 s). Hotkey logged 3× with no effect | Crash 17:33:43 (`.ips`), relaunch 17:33:51 |
| **Crash** 2026-10-11 13:27 local | No logs that day | `EXC_BAD_ACCESS` in `MainActor.assumeIsolated` from SwiftUI hit-test |

Both crash reports: main-thread `EXC_BAD_ACCESS` in `swift_task_isMainExecutorImpl ← MainActor.assumeIsolated`, plus a HIServices thread `SOME_OTHER_THREAD_SWALLOWED_AT_LEAST_ONE_EXCEPTION` — an Objective-C exception was swallowed by the run loop. In 10-13 it was created 11 ms after "Installing recording tap".

### Hypotheses (ranked)

1. **Objective-C exception during audio engine setup on the main actor.** `AudioCaptureService` is `@MainActor` (`AudioCaptureService.swift:41`); recording start runs in `Task { @MainActor }` (`RecordingViewModel.swift:538-559`). `installTap` (`:762`) uses a format based on hardware sample rate (`:662-669`) while `inputNode.outputFormat` is stale (44100 vs 48000 in 71/75 sessions) → format mismatch raises an NSException (uncatchable in Swift). The exception unwinds through the main-actor job and is swallowed; main-queue work stops being serviced (hotkey closure logs but its `DispatchQueue.main.async` never runs — `HotkeyService.swift:24-27`) and the next `assumeIsolated` crashes.
2. **Blocking CoreAudio calls on the main thread.** `selectDevice` / `AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)` (`:991-999`) and `AVAudioEngine()`/`inputNode` creation (`:156`) run on main. Hang A stalled in this window; outliers of 3.03 s and 0.78 s vs median 0.044 s. Both hangs followed 3.5–12 min idle (device/coreaudiod wake-up).
3. Same unguarded calls in teardown/retry paths (`:152-154`, `:250-251`, `:293-294`, `:695-733`).

### Diagnostics to add

- Main-thread watchdog (ping main queue every 1 s; WARN + context if no reply within 2 s).
- Objective-C `@try/@catch` shim around `installTap` / `prepare` / `start`, logging exception name and reason.
- `NSSetUncaughtExceptionHandler` + `NSApplicationCrashOnExceptions=YES` to fail fast with a real backtrace instead of a corrupted state.
- Log node output format vs tap format before `installTap`.
- Timing logs around `setInputDevice` and engine creation.

---

## 3. Shortcut recorder & floating window

### Hotkey recording

- Capture is delegated entirely to `sindresorhus/KeyboardShortcuts` 2.4.0: `Views/Components/HotkeyRecorder.swift:11` wraps `KeyboardShortcuts.Recorder(for: .toggleOverlay)`; `Views/HotkeysSettingsTab.swift:10-11`.
- Single global hotkey `.toggleOverlay`, default ⌥Space (`Services/HotkeyService.swift:7`), registered via `KeyboardShortcuts.onKeyDown` (`:23`).
- Dead code: `AppSettings.recordingKeyCode/recordingModifiers` (`Models/AppSettings.swift:182-187`), used only by `SettingsViewModel.hasRecordingHotkeyConflict` (`:191-198`).
- **Fn/Globe not supported anywhere** (no `.function` handling, no glyph). The library recorder (Carbon-based) cannot record Fn.
- Unreliability suspects:
  1. Overlay's local `.keyDown` monitor (`OverlayContentView.swift:93`) is removed only on `onDisappear`; while alive it also sees Settings window key events and **swallows all ⌥ / ⌥⇧ combos** (`RecordingViewModel.swift:850-864`), Esc, ⌘W, 1/2.
  2. Overlay panel is `.nonactivatingPanel` with `canBecomeKey = true` (`OverlayPanel.swift:14,38,65`) — can steal key status from Settings.
  3. `stopListening` → `KeyboardShortcuts.disable` only from `deinit`.

### Floating window (pre-processing stage)

- **Top**: `PromptSelectorView` (`OverlayContentView.swift:14-18`, `Components/PromptSelectorView.swift:27`) — menu labelled with the prompt name (e.g. "Speech To Text"), no number shortcut.
- **Bottom** `ControlBarView.preProcessingButtons` (`ControlBarView.swift:94-167`): microphone menu (hint "1"), output language menu (hint "2"); right side Start/Stop with formatted global shortcut, Exit "Esc".
- Key handling `RecordingViewModel.handleKeyDown` (`:842-907`): key code 18 ("1") → `cycleMicrophone()`, 19 ("2") → `cycleTextLanguage()`.
- Microphone cycle (`:209-221`): next index with wrap in `audioDeviceManager.devices` raw order (may differ from menu order).
- Shortcut hint glyphs are text pills (`ControlBarView.swift:275-300`); `formattedShortcutLabel` (`:175-201`) splits on `⌃⌥⇧⌘` only — no Fn.
- Unused stale components: `Components/MicrophoneSelectorButton.swift`, `Components/LanguageSelectorView.swift`.
- Prompts: `Services/PromptsStore.swift` (`prompts.json`), built-in `SystemPromptRegistry.all = [.simpleVoiceToText]` ("Speech To Text"). Overlay resets to `defaultPrompt` each session (`RecordingViewModel.swift:86-87, 489`).


## 3. Microphone switching and closing the floating window (added 2026-10-15)

**Date**: 2026-10-15
**Source**: diagnostic log `~/Library/Application Support/Verborra/Logs/verborra-2026-10-15T10.jsonl` (sessions after 08:15 UTC, Debug build of this feature) and the code on this branch. Covers US9.

### What the log shows

Every switch to a specific microphone during a recording failed; only "System Default" worked.

| Time (UTC) | Action | Result |
|---|---|---|
| 08:16:28 | Key 1 while recording: System Default → AntennaPhone Microphone (Continuity) | `Previous audio host still busy, using a new one` → `Audio setup failed`, `timeout at engineCreate` after 1.9 s |
| 08:16:37 | Menu: → AntennaPods (Bluetooth, already HFP) | trigger engine started and settled, then `timeout at engineCreate` |
| 08:16:50 | Menu: → System Default | works (engine ready in ~420 ms) |
| 08:16:56 | Menu: → AntennaPods (needs A2DP → HFP) | `Previous audio host still busy` → `timeout at btTrigger` after 1.85 s |
| 08:26:58 | Menu: → AntennaPods | same: `still busy` → `timeout at btTrigger` |

Each failure was followed by the window being closed (`Reset ignored — not recording` twice).

Normal starts on System Default take 250–350 ms to create the engine, so a 1.8 s limit is tight even without contention.

### Causes found in the code

1. **A just-queued teardown is mistaken for a stuck host.** A mid-recording switch calls `resetRecording()`, which queues `host.teardown` on the audio host's serial queue, and immediately calls `startRecording`. `startRecording` sees `host.isBusy == true` (the teardown hasn't run yet), logs "still busy", and creates a second `AudioEngineHost`. The old engine is then being stopped on one queue while a new engine is created on another, and the new engine's creation stalls past the limit. `isBusy` was meant to detect a host whose call never returned, not one with work merely queued. (`AudioCaptureService.startRecording`, `AudioEngineHost.isBusy`)
2. **Switches get one short attempt.** The hotkey start (feature 015) has a retry and a 5 s budget, but `switchAudioDevice` calls `startRecording` with the protocol defaults: attempt 1, 1.8 s setup limit, no retry. (`RecordingViewModel.switchAudioDevice`, `AudioCaptureServiceProtocol` extension)
3. **The Bluetooth profile switch gets the same 1.8 s.** A2DP → HFP usually takes 1–3 s; the comment says "own 5 s budget", but `runBluetoothSwitch` uses `setupTimeout` (1.8 s). The engine start that follows also gets only 1.8 s while the headset is still reconfiguring.
4. **During a switch the window still says "recording".** The view model stays in `.recording` while capture is stopped and restarting. So:
   - The timer keeps counting; the stop key/button calls `stopRecording` on a capture that isn't running.
   - **Closing the window doesn't stop the switch.** `cleanup()`/`dismissOverlay()` call `cancelStart`, which only acts in `.starting`, and `resetRecording`, which is ignored because capture isn't running. `switchTask` is never cancelled, so a slow switch can turn the microphone on after the window has closed (the mic indicator stays on, with nothing to stop it until the next window).
5. **Minor:** while a switch is in flight the log shows the numeric device id (`deviceName: "138"`) instead of the name, because the name is only filled in after a successful start.

### Also seen in the log (out of scope)

- Logger tests write into the real app log (`warn <UUID>` lines with `k: v` metadata at 08:14:42), and one line is truncated/corrupt (line 399). Test isolation issue; tracked separately.
- Main-thread stalls of 6–13 s while idle and the app inactive (08:16:11, 08:21:07, 08:22:25), each around granting Accessibility in System Settings. Separate investigation.
