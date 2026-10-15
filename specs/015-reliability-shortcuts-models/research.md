# Phase 0 Research — Reliability & Shortcut Fixes

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Evidence**: [investigation.md](./investigation.md) | **Date**: 2026-10-14

Seventeen decisions (R1–R17). Every unknown from the Technical Context is resolved; none remain open.

---

## Area A — Launch at login (US1, FR-001…FR-006)

### R1 — Source of truth for the toggle

**Decision**: The Settings control shows `SMAppService.mainApp.status` (`.enabled`, `.notRegistered`, `.requiresApproval`, `.notFound`), not the stored flag. The stored `@AppStorage("launchAtLogin")` value becomes the user's **intent** only. A new `LoginItemService` (protocol `LoginItemServiceProtocol`, so it can be mocked) wraps `SMAppService.mainApp` and exposes `status`, `register()`, `unregister()`, `refresh()` and `openSystemSettings()` (`SMAppService.openSystemSettingsLoginItems()`).

**Rationale**: The investigation showed the toggle showing "on" while no login item existed, because it was bound to an unapplied default. Reading the status from the system each time Settings appears, and again on `NSApplication.didBecomeActiveNotification`, keeps the control truthful even after changes in System Settings › Login Items (SC-002). `status` is a cheap synchronous call.

**Alternatives considered**: *Keep the stored flag and register on toggle only.* This is today's behaviour and the bug. *Poll the status on a timer.* Unnecessary, because reading it on appear and on activation covers every way the user can reach the control.

### R2 — Reconcile at startup

**Decision**: In `applicationDidFinishLaunching`, after logging starts and **only if onboarding is completed**, run `LoginItemService.reconcile(intent:)`:

| Intent | Status | Action |
|---|---|---|
| on | `.enabled` | none |
| on | `.notRegistered` / `.notFound` | `register()`; log the result |
| on | `.requiresApproval` | none (only the user can approve); log INFO, Settings shows "needs approval" |
| off | `.enabled` | none (the user may have enabled it in System Settings, and we don't override system state silently); intent is updated to on |
| off | other | none |

A missing `launchAtLogin` key (existing user who never touched the toggle) counts as intent **on** (FR-005, second sentence).

**App location check** (spec edge case "multiple copies"): during reconcile the service also records `Bundle.main.bundleURL` (INFO `Login item reconcile`, metadata `appPath`, `status`, `intent`). It sets `isRunningFromApplications = bundleURL.path.hasPrefix("/Applications/")` (also accepting `~/Applications/`). When that's false, Settings shows a caption under the toggle: "Verborra is running from <folder>. Move it to Applications so the right copy starts at login." The app never moves itself, because silently relocating the bundle would surprise the user.

**Rationale**: This covers FR-002 (re-register after updates or failures) without asking existing users again. Skipping reconcile until onboarding is completed keeps fresh installs from registering before the user has been asked (FR-005).

**Alternatives considered**: *Always register when intent is on, even with `.requiresApproval`.* `register()` can't approve on the user's behalf and only produces repeated errors.

### R3 — Ask once during onboarding

**Decision**: Add a "Start Verborra at login" toggle, on by default, to the existing **Completion** onboarding step (`Views/Onboarding/CompletionStep.swift`). When the user finishes onboarding (`OnboardingViewModel.completeOnboarding()`), the answer is written to the intent and `register()` or `unregister()` runs right away. A failure is shown inline on the Completion step and logged, the same way as in Settings.

**Rationale**: This reuses an existing screen, adds no new onboarding step, and applies the answer immediately (clarification Q2). The Completion step is the last screen, so the choice is made once.

**Alternatives considered**: *A separate onboarding step.* That adds a click and its own state for one toggle. *An NSAlert at first launch.* It's intrusive and doesn't follow the HIG pattern for onboarding.

### R4 — Stable signing identity

**Amendment 2026-10-15**: the owner has no Apple certificate, so the decision below is replaced: the project stays **ad-hoc** (`CODE_SIGN_IDENTITY = "-"`, `Manual`, no team) with `ENABLE_HARDENED_RUNTIME = YES`. Consequence: after installing a new build, the login item may need re-approval and Accessibility may need re-granting; both are surfaced in Settings. The original decision is kept below for history.

**Decision**: Fix the actual Xcode project (`Verborra.xcodeproj/project.pbxproj`, both Debug and Release of the app target), which today is ad-hoc (`CODE_SIGN_IDENTITY = "-"`, `CODE_SIGN_STYLE = Manual`, `DEVELOPMENT_TEAM = ""`) and doesn't match `project.yml`. Set it to `CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY = "Apple Development"` and `DEVELOPMENT_TEAM = G292C8CN3X`. The local keychain has a valid identity: an `Apple Development` identity, OU `G292C8CN3X`. Also sync `project.yml` (it lacks the `swift-atomics` package that the pbxproj has) so regenerating doesn't reintroduce drift. Also enable **Hardened Runtime** (`ENABLE_HARDENED_RUNTIME = YES`), which constitution v2.0.0 (Principle 4) requires release builds to be compatible with. The existing `com.apple.security.device.audio-input` entitlement is exactly the Hardened Runtime microphone entitlement. CGEventTap (Accessibility-gated), CGEvent posting and the AX API need no runtime exceptions, so no new entitlement is added. The quickstart release check verifies `codesign -dv` shows `TeamIdentifier=G292C8CN3X` and the `runtime` flag.

**Rationale**: An ad-hoc signature changes its code identity (cdhash) with every build. `SMAppService` and BTM record the item against the app's designated requirement, so a replaced ad-hoc app can leave a stale registration behind. A team-signed build keeps a designated requirement based on bundle ID and team across releases (FR-006, SC-001 "including after installing a new app version").

**Alternatives considered**: *Developer ID plus notarization.* Better for distributing to others, but the spec assumes the user's own machines and it needs a paid Developer ID certificate. The design leaves room for it later. *Keep ad-hoc and re-register at every launch.* R2 already re-registers when needed, but ad-hoc signing would still cause registrations to churn and `.requiresApproval` prompts to repeat after each update.

**Operational note**: Stale copies with the same bundle ID (`builds/…/Verborra.app` and the old repo) can confuse LaunchServices. The quickstart includes a cleanup step (delete them or run `lsregister -u`). This is a documented manual step, not code.

---

## Area B — Hangs at recording start (US2, FR-007…FR-013a)

### R5 — Move AVAudioEngine setup off the main thread

**Decision**: Add an `AudioEngineHost`: a `final class` that owns the `AVAudioEngine` and does **all** engine work (creation, `inputNode` access, `AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)`, `installTap`, `prepare`, `start`, `stop`, `removeTap`) on a private serial `DispatchQueue` (`dev.apeek.verborra.audio-engine`, QoS `.userInitiated`). `AudioCaptureService` stays the `@MainActor` facade and its public protocol doesn't change. It calls the host through `async` wrappers (`withCheckedThrowingContinuation` plus a deadline, see R7). The host never touches main-actor state. Results come back as value types: resolved device ID, node format, hardware rate, and per-step timings.

**Rationale**: Hang A stalled between "Preparing audio engine" and the next log line, and outliers reached 3.03 s. CoreAudio and HAL calls that wait on `coreaudiod`, especially after 3.5–12 minutes of idle, block whichever thread calls them. Today that thread is main, so the hotkey closure's `DispatchQueue.main.async`, Esc, and the menu bar all stop (investigation, hypothesis 2). On a dedicated queue a stall only delays the start, and the main thread keeps servicing input (FR-008).

**Alternatives considered**: *A Swift `actor`.* Its executor is the cooperative pool, so a blocking CoreAudio call would hold a cooperative thread, which is discouraged and can starve other tasks. A serial GCD queue is the right tool for blocking C APIs. *`Task.detached`.* Same cooperative-pool problem, and it wouldn't serialize access to the engine.

### R6 — Fix the format mismatch and stop Objective-C exceptions

**Decision**, in three layers:

1. **Stop forcing a tap format that can disagree with the node.** After the device is set, the host reads `inputNode.outputFormat(forBus: 0)` (node rate) and the device's `kAudioDevicePropertyNominalSampleRate` (hardware rate). If they match, it installs the tap with **`format: nil`**, so the node's own format is used and can't mismatch. If they differ, the node is stale (seen in 71 of 75 sessions: 44100 vs 48000). The host throws away the engine, creates a fresh `AVAudioEngine`, sets the device again, and checks once more. If they still differ, it fails with `RecordingError.recordingStartFailed(.formatMismatch)` and logs an ERROR with both formats.
2. **Exception shim as a safety net.** A small Objective-C helper `VBRTryCatch(void (^)(void)) -> NSError?` (`@try/@catch NSException`) wraps `installTap`, `prepare` and `start`. A caught exception becomes `AudioSetupError.objcException(name, reason, step)`, logged at ERROR with context (FR-010), and the attempt counts as failed so R8 retries it.
3. **Downstream already copes with any input format.** `convertToWAV` uses `buffers[0].format` with `AVAudioConverter` to 16 kHz mono, and the level meter reads channel 0. A multichannel or 44.1/48 kHz tap format needs no other changes. `AudioFileWriter` already writes in the node format.

**Rationale**: Hang B's log shows a tap installed at 48000 Hz on a node reporting 44100 Hz, and an Objective-C exception was swallowed 11 ms later. Afterwards main-queue work stopped and `MainActor.assumeIsolated` crashed (investigation, hypothesis 1). Removing the forced format removes the cause, and the shim keeps any other `AVAudioEngine` `NSException` from corrupting app state (FR-009, FR-010).

**Alternatives considered**: *Keep the hardware-rate tap format.* This is the root cause. *Only add the shim.* It would hide the bug while every start on a stale node failed and retried. *Listen for `AVAudioEngineConfigurationChange` before installing.* It doesn't fire reliably for the stale-node case after idle, and the existing CoreAudio sample-rate listener (installed after start) still covers mid-recording changes.

**Constitution note**: Principle 2 allows Objective-C only for system interaction without a Swift wrapper. Swift can't catch `NSException`, so the shim is the only option. It's recorded in Complexity Tracking.

### R7 — Time budget and cancellation

> **Amended by R31 (2026-10-15)**: the Bluetooth trigger now gets its own `bluetoothTimeout` (it was wrongly limited by the 1.8 s `setupTimeout`), and a microphone switch uses the same start path with a single 5 s budget that includes the Bluetooth step.

**Decision**: Recording start runs as a single `startTask` owned by `RecordingViewModel`, with a **5.0 s overall deadline** (FR-007) split as follows:

| Step | Budget |
|---|---|
| Attempt 1: engine setup on the host queue (create → device → tap → prepare → start) | 1.8 s |
| Attempt 1: wait for first buffer | 0.6 s (today 5 s); if the engine is running but no buffer has arrived, the start counts as **successful** (unchanged semantics: Bluetooth devices may be silent at first) |
| Attempt 2 (same device, fresh engine) | whatever remains, at most 2.4 s |
| Headroom for UI and state | ≥ 0.2 s |

Each host call is raced against a deadline (`withThrowingTaskGroup` with a sleep child, or a `DispatchWorkItem` timer that resumes the continuation once, guarded by a flag). On timeout or cancellation the **generation token** of that attempt is invalidated. Whenever the stalled host call eventually returns, it sees the stale generation and tears the engine down (`removeTap` + `stop`) on the host queue without touching UI state. If the host queue is still stuck when attempt 2 starts, attempt 2 gets a **new host instance and queue**, so one stalled HAL call can't serialize the retry behind it.

**Bluetooth**: the existing A2DP→HFP stabilization (up to 5 s, shown in the UI as "Switching…") happens *before* the engine start and is not part of this budget. The 5 s clock starts when stabilization ends. Stabilization keeps its own 5 s timeout, and the whole start remains cancellable (R9). This is how FR-007's "within 5 seconds" applies to Bluetooth devices, where the profile switch is a user-visible step that already shows progress. The spec now states this explicitly (Clarifications, FR-007 and Edge Cases).

**Who owns the retry**: `AudioCaptureService.startRecording` performs **one** attempt per call, with the timeouts passed in. `RecordingViewModel` runs attempt 1, then attempt 2, and enforces the overall 5 s deadline. This keeps the user-visible state (`.starting(attempt:)`) and the retry policy in one place and makes them unit-testable with `MockAudioCaptureService`.

**Rationale**: Healthy starts take a median of 0.044 s and a p99 of about 0.14 s, so 1.8 s per attempt leaves room for slow-wake outliers (0.78 s seen) while two attempts plus headroom still fit in 5 s (SC-004).

**Alternatives considered**: *A 5 s timeout per attempt.* That breaks FR-007's total. *No timeout, cancel only.* A stuck HAL call would leave the UI in "starting" forever.

### R8 — Automatic retry and the error UX

**Decision**: When attempt 1 fails (thrown error, Objective-C exception, format mismatch after re-create, or timeout), it's logged at ERROR. Then attempt 2 runs **on the same device** with a fresh engine. If attempt 2 fails, the state becomes `.error(.recordingStartFailed(reason))`. `RecordingView.isRetryableError` treats that case as retryable, so the existing "Retry" button (`recording.error.retry`) appears and `retryFromError()` calls `startRecording()` again in the same session (FR-013). The current **automatic fallback to the system default device** in `AudioCaptureService.prepareAndStartEngine` (lines 687-748) and the `onDeviceFallback` callback are **removed** (clarification Q1: never switch microphone automatically).

**Rationale**: One silent retry covers the transient post-idle failures, and the explicit Retry button covers persistent ones without restarting the app.

**Alternatives considered**: *Keep the fallback to the default device.* The clarification rules it out. *Several retries with backoff.* They don't fit the 5 s budget, and a persistent failure should reach the user quickly.

### R9 — Cancelling a start with the hotkey or Esc (FR-013a)

**Decision**: Add `RecordingState.starting(attempt: Int)`. `handleRecordingKey()` in `.starting` calls `cancelStart()`, which cancels `startTask`, invalidates the current generation, asks the host to tear down asynchronously (it doesn't wait), cancels Bluetooth preparation if any (`bluetoothProfileManager.cancelPreparation()`), and sets `state = .idle` synchronously on main. The window is back in the pre-recording stage immediately, well within the 1 s limit. Esc and window close (`dismissOverlay` → `cleanup`) call the same path. Hotkey presses during `.starting` don't queue: each press is handled synchronously against the current state.

**Rationale**: Because cancellation never waits on the host queue, it stays fast even while a HAL call is stuck.

### R10 — Detecting an unresponsive main thread (FR-011)

**Decision**: Add a `MainThreadWatchdog` running on its own utility `DispatchQueue` with a `DispatchSourceTimer` every 0.5 s. Each tick posts `DispatchQueue.main.async { lastPong = now }` (stored in a `ManagedAtomic<UInt64>`, since `swift-atomics` is already a dependency). If `now − lastPong > 2.0 s` and no stall is open, it writes **one WARN** with context (below) and opens a stall episode. When the pong returns it writes INFO `"Main thread recovered"` with the total stall duration.

Context comes from a `HangContext` snapshot (`stage`, `deviceName`, `deviceID`, `stageEnteredAt`) that `RecordingViewModel` and `AudioCaptureService` update on main at each stage transition, stored in `OSAllocatedUnfairLock<HangContext>`. The watchdog reads only that snapshot and **never calls into main-actor code**, including `DiagnosticLogger.appStateProvider`, which would need main (see R12). The watchdog starts in `applicationDidFinishLaunching` and is suspended while logging is OFF.

**Rationale**: This is the standard ping-pong watchdog. It's cheap (two dispatches per second) and catches any cause of a hang, not only audio. That's the "diagnostics for remaining causes" in the spec's Assumptions. A 0.5 s tick detects a stall within about 2.5 s.

**Alternatives considered**: *`MXHangDiagnostic` (MetricKit).* Delivered once a day, after the fact, and not in the JSONL log. *A run-loop observer on main.* It can't report while main is blocked.

### R11 — Crash on uncaught exceptions instead of corrupting state

**Decision**:

- **All builds**: install `NSSetUncaughtExceptionHandler`. The handler writes an ERROR (`name`, `reason`, top `callStackSymbols`) and calls `JSONLFileWriter.shared.flushSync()`.
- **DEBUG builds only**: register `NSApplicationCrashOnExceptions = true` (`UserDefaults.standard.register(defaults:)`), so any exception that reaches the run loop crashes right away with a real backtrace during development.
- **Release builds** keep AppKit's default (log and continue). The known harmful source, AVAudioEngine, is contained by the shim (R6). If a swallowed exception still leaves the main thread stuck, the watchdog (R10) records it with context.

**Rationale**: AppKit's default is to log and *swallow* exceptions that reach the run loop. That's the "swallowed at least one exception" state in both crash reports, and there it came from audio setup, which R5 and R6 now contain. Making every exception fatal in Release would also crash the app for harmless AppKit or SwiftUI exceptions that are swallowed today without visible effect. That would raise the crash count during the SC-003 soak and lose the user's session for no benefit. In DEBUG, failing fast is the better trade-off: it surfaces any remaining source during development and QA.

**Alternatives considered**: *Crash on exceptions in all builds* (first draft). Rejected for the reason above. *Subclass `NSApplication` to override `reportException:`.* That needs an `NSPrincipalClass` change for a SwiftUI app and gives little beyond the watchdog and uncaught handler.

### R12 — WARN entries within the constitution's logging levels

**Decision**: Add `DiagnosticLogger.warn(_:metadata:)`, which writes a `LogEntry` with `level: "WARN"`. It's **written whenever ERROR entries would be** (active mode ERROR, INFO or DEBUG; nothing in OFF), and goes to `os.Logger` at `.error` (os_log has no warn). It doesn't call `appStateProvider` (safe off main). The four user-selectable **modes** (OFF/ERROR/INFO/DEBUG) stay the same, and `LogLevel` gets no new case. A separate `LogEntry` severity label carries "WARN".

**Rationale**: The spec requires WARN entries (FR-011, SC-005). Constitution v2.0.0, Principle 6, explicitly allows a WARN severity written whenever ERROR is, with the four modes unchanged.

**Logger categories**: following Principle 6 ("each module/service MUST create its own `os.Logger` instance with a unique category"), the new services get new `LogCategory` cases: `.hotkey` (GlobalHotkeyService, FnEventTap, recorder), `.loginItem` (LoginItemService) and `.watchdog` (MainThreadWatchdog). `AudioEngineHost` uses the existing `.engine` category, which is defined as AVAudioEngine lifecycle. Gating it with ERROR keeps hang reports visible even when the user picks ERROR mode.

**Alternatives considered**: *Log hangs as ERROR with `errorCode: mainThreadUnresponsive`.* That works but blurs "something failed" with "something was slow", and `error()` calls `appStateProvider` (main-actor), which is unsafe from the watchdog thread. *Add `LogLevel.warn` as a fifth mode.* That would change the constitution's mode set and needs an amendment.

### R13 — Per-step timing logs (FR-012)

**Decision**: The host measures each setup step with `ContinuousClock` (`engineCreate`, `setDevice`, `readFormats`, `installTap`, `prepare`, `start`, `firstBuffer`) and returns them as `AudioSetupTimings`. `AudioCaptureService` writes **one INFO line per attempt**: `"Audio setup timings"` with each step in ms plus `attempt`, `deviceName`, `deviceID`, `nodeSampleRate`, `hwSampleRate`, `tapFormat`, `outcome`. Failures get an ERROR (`step`, `device`, `formats`, `reason`). See [contracts/diagnostic-events.md](./contracts/diagnostic-events.md).

**Rationale**: One structured line per attempt is easy to grep and aggregate, and doesn't flood INFO.

---

## Area C — Shortcut recorder and global Fn hotkey (US3, FR-014…FR-022, FR-028)

### R14 — Recording and registering shortcuts that include Fn

**Findings** (from the KeyboardShortcuts 2.4.0 source in DerivedData):

- `KeyboardShortcuts.Shortcut(event:)` removes Fn: `event.modifierFlags.subtracting(.function)` (`Shortcut.swift:65`). The bundled `Recorder` therefore can't record Fn.
- Registration uses Carbon `RegisterEventHotKey` (`CarbonKeyboardShortcuts.swift:137`), whose modifier mask has no Fn bit. Fn shortcuts can't be registered through Carbon at all.
- The library already uses `"🌐\u{FE0E}"` as the Fn glyph, which matches clarification Q4.
- `NSEvent.ModifierFlags.function` / `CGEventFlags.maskSecondaryFn` are **also set on arrow keys, F1–F12, Home/End/PgUp/PgDn and Forward Delete without Fn held**. Using the flag on keyDown to detect Fn would give false positives.

**Decision**:

1. **Own model and recorder.** A new `GlobalShortcut` value type (`keyCode: UInt16`, `modifiers: ShortcutModifiers` OptionSet `{fn, control, option, shift, command}`) is persisted as JSON in UserDefaults (`globalShortcut.v1`). On first launch it migrates from the KeyboardShortcuts store (`KeyboardShortcuts_toggleOverlay`); the default stays ⌥Space. A new `ShortcutRecorderField` (AppKit `NSView`, first responder, wrapped in `NSViewRepresentable`) replaces `KeyboardShortcuts.Recorder`:
   - `flagsChanged(with:)` updates the live modifier display (FR-014, under 100 ms because it's a synchronous redraw). Fn counts as held **only** from the `flagsChanged` transitions of `kVK_Function` (keyCode 63), never from the `.function` flag on keyDown.
   - `keyDown(with:)`: Esc cancels (FR-018). A non-modifier key with ≥1 modifier is validated (R15), saved, and focus is released (FR-016). With no modifier it shows the hint "Add at least one modifier (🌐︎ ⌃ ⌥ ⇧ ⌘)" (FR-017).
   - Releasing all modifiers without a key resets to the placeholder (AS 3.5).
   - A small "Reset to default" button sits next to the field (FR-018).
   - While the field is recording, global hotkey handling is **paused** (`GlobalHotkeyService.isPaused = true`) so pressing the current shortcut doesn't open the overlay.
2. **Hybrid registration in `GlobalHotkeyService`** (replacing `HotkeyService`):
   - **Without Fn**: keep Carbon via KeyboardShortcuts. Call `KeyboardShortcuts.setShortcut(.init(carbonKeyCode:carbonModifiers:), for: .toggleOverlay)` plus `onKeyDown`. This needs no permission and is unchanged from today, so ⌥Space users see no difference.
   - **With Fn**: clear the Carbon shortcut and install a **`CGEventTap`** (`.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`, mask `keyDown | flagsChanged`) on a **dedicated background thread with its own run loop**, never main. The tap tracks Fn from `flagsChanged` keyCode 63 (plus `maskSecondaryFn` transitions on that key). On keyDown it compares keyCode and the effective modifiers (`flags` without `maskSecondaryFn`, plus `fnHeld`). On a match it **swallows** the event (returns `nil`) and dispatches `onToggle` to main. Autorepeat (`kCGKeyboardEventAutorepeat`) is ignored. If the tap receives `tapDisabledByTimeout` or `tapDisabledByUserInput`, it re-enables itself and logs.
   - An active tap needs **Accessibility**, which Verborra already asks for in onboarding for paste (`AXIsProcessTrusted`). If it isn't granted, the Settings field shows "🌐︎ shortcuts require Accessibility access" with a link to the existing permission row, and the hotkey isn't active. Status: `HotkeyRegistrationStatus.needsAccessibility`. The app is **not sandboxed** today (`Verborra.entitlements` has no `app-sandbox`), so active taps are allowed.
3. **One formatter.** `ShortcutFormatter.symbols(for:)` produces `"🌐︎ ⌃ ⌥ ⇧ ⌘ Key"` (space-separated, fixed order). It's used by the Settings field and by `ControlBarView.formattedShortcutLabel`, replacing the string-splitting at `ControlBarView.swift:175-201` (FR-028).

**Rationale**: Carbon is the most reliable mechanism for ordinary shortcuts and needs no permission, so keeping it there avoids regressions for current users. Fn can only be detected below Carbon, and an active session tap is the documented way to see and consume it. Running the tap off main is essential: an active tap on a blocked main run loop delays *all* keyboard input system-wide until macOS disables the tap, which would make the hang bugs this feature fixes worse. Tracking Fn from `flagsChanged` avoids the arrow/F-key false positives.

**Alternatives considered**:
- *Patch or fork KeyboardShortcuts to record Fn.* Registration would still go through Carbon, which can't express Fn, and a fork adds maintenance (Principle 2).
- *`NSEvent.addGlobalMonitorForEvents`.* Listen-only, so it can't swallow the event: Fn+Space would also type a space into the frontmost app. It also needs Input Monitoring or Accessibility.
- *Use the CGEventTap for all shortcuts.* That would make the default ⌥Space depend on Accessibility, regressing users who haven't granted it, and route every keystroke through the tap even when Fn isn't used.
- *Drop KeyboardShortcuts and call `RegisterEventHotKey` directly.* Feasible, but it adds ~100 lines for no user benefit. Keeping the library minimizes churn. Its `Recorder` is no longer used, only `setShortcut`/`onKeyDown`/`disable`.

**Known macOS interaction**: Pressing and releasing Globe *alone* triggers the system "Press 🌐 key to…" action (emoji picker, input source, dictation). Fn+key combos don't trigger it, so this doesn't affect FR-019. The quickstart notes that users who want Fn shortcuts can set that system option to "Do Nothing"; Verborra doesn't change system settings.

### R15 — Validating shortcuts (FR-016, FR-017, FR-021)

**Decision**: `ShortcutValidator.validate(_:)` returns `.ok` or `.rejected(reason)`, checked in this order:

1. No modifier → `.modifierRequired` (FR-017). Fn on its own as the key (keyCode 63) or any modifier-only press is never a "regular key".
2. **In-window keys**: Esc (53), 1 (18), 2 (19), 3 (20) with no modifiers other than Fn or Shift, and ⌥C, ⌥V, ⌥⇧C, ⌥⇧V, ⌘W → `.conflictsWithOverlay` (FR-021).
3. **Reserved by the app menu**: ⌘Q, ⌘, → `.reservedByApp`.
4. **System symbolic hotkeys**: `CopySymbolicHotKeys` (Carbon, enabled entries only; KeyboardShortcuts already reads it at `CarbonKeyboardShortcuts.swift:339`) → `.reservedBySystem` (FR-021, AS 3.9).
5. For non-Fn shortcuts, **registration failure**: if `RegisterEventHotKey` reports the shortcut as taken (KeyboardShortcuts doesn't expose this, so `GlobalHotkeyService` does a trial `RegisterEventHotKey`/`UnregisterEventHotKey` with a throwaway ID before committing) → `.inUseByAnotherApp`.

When a shortcut is rejected, the previous shortcut is kept, a warning appears under the field, and an INFO line is logged. When one is accepted, the change is logged as `"Global shortcut changed"` with `old` and `new` in symbol form (FR-022).

### R16 — Stopping the overlay from intercepting Settings keys (FR-020)

**Decision**:

1. The overlay's local `keyDown` monitor (`OverlayContentView.swift:93`) handles an event **only if `event.window === overlayPanel`**. Anything else, such as Settings keystrokes, passes through untouched. `RecordingViewModel.handleKeyDown` also stops blocking all ⌥ and ⌥⇧ combos for other windows, since the window check makes that safe.
2. The monitor is created and removed with the panel's show/dismiss in `OverlayManager` (not SwiftUI `onAppear`/`onDisappear`), so it can't outlive a dismissed panel.
3. `GlobalHotkeyService` is paused while the Settings shortcut field is recording (R14), and `KeyboardShortcuts.disable` no longer depends on `deinit`.

**Rationale**: The investigation found the overlay monitor swallowing every ⌥ and ⌥⇧ combination, Esc, ⌘W and 1/2 *app-wide* while it was alive. That explains "the recorder is unreliable when the floating window is or was open" (AS 3.8, SC-006).

---

## Area D — Floating window selectors (US4, FR-023…FR-029)

### R17 — Layout and key mapping

> **Superseded in part by R29 (2026-10-15)**: order is microphone 1, language 2, prompt 3; keys also work while recording; menus have titles.

**Decision**:

- Remove `PromptSelectorView` from the top of `OverlayContentView` (lines 13-18). The prompt becomes a `controlBarMenu` in `ControlBarView.preProcessingButtons`, between microphone and language: SF Symbol `text.quote`, title = `selectedPrompt.name`, hint `"2"`, items = `promptsStore.prompts` in store order with a checkmark on the selection. The language menu hint changes from `"2"` to `"3"`.
- `RecordingViewModel.handleKeyDown`: 18 → `cycleMicrophone()`, 19 → `cyclePrompt()` (new), 20 → `cycleTextLanguage()`. They apply only when `windowPhase == .preProcessing`, `state` is `.idle` or `.error`, and there are no modifiers (AS 4.7: not during `.starting`, `.recording`, `.transcribing`, `.formatting`).
- `cyclePrompt()`: `prompts = promptsStore.prompts` (live list). If it's empty, do nothing. Find `selectedPrompt.id`; if it's missing (deleted), select `promptsStore.defaultPrompt`; otherwise select `prompts[(i+1) % count]`. A single prompt stays selected (AS 4.3). It goes through `changePrompt(_:)`, the same path as a menu pick (FR-027).
- `changePrompt(_:)` also updates `chatSession?.systemPrompt`, matching the language-mirroring pattern from 014, and logs `userAction` INFO `"Prompt changed"` with `from`, `to`, `source: key|menu` (FR-029). Microphone and language changes get the same log line if they don't have one yet.
- Microphone cycling already follows menu order: `AudioDeviceManager.devices = [systemDefault] + alphabetical`, which is how the menu renders them (FR-026). No change.
- Per-session only: `showOverlay()` already resets `selectedPrompt = promptsStore.defaultPrompt` (`RecordingViewModel.swift:489`), and nothing writes back to Settings (FR-027). No change.
- Delete the unused `Components/MicrophoneSelectorButton.swift`, `Components/LanguageSelectorView.swift` and the now-unused `Components/PromptSelectorView.swift`.

**Rationale**: This puts the three session options in one row with consistent number keys, as requested. It reuses `controlBarMenu`, so styling and hints stay consistent (FR-025).

---

## Area E — Model list (US5–US8, FR-030…FR-042)

Sources were checked on 2026-10-14 against OpenAI's developer docs: the model pages for `gpt-6-luna`, `gpt-6-sol`, `gpt-6.1-sol`, `gpt-6-astra`, `gpt-5.6-terra` and `gpt-transcribe`, the model catalog, the reasoning guide, the speech-to-text guide and the deprecations page. Third-party pricing pages were used only to cross-check prices.

### R18 — Model IDs, prices and context sizes

**Decision**: Use these IDs. All new text models have a 1,050,000-token context with **922,000 max input** and 128,000 max output.

| ID | Input / Output per 1M | Source |
|---|---|---|
| `gpt-5.6-terra` | $2.00 / $12.00 | model page |
| `gpt-5.6-sol` | $4.00 / $20.00 | `gpt-5.6-terra` page comparison table (no own page fetched; confirm in quickstart 5.2) |
| `gpt-6-luna` | $0.10 / $0.50 | model page + catalog |
| `gpt-6-sol` | $2.00 / $10.00 | model page ("See GPT-6.1 Sol for the newer Sol model"; not deprecated) |
| `gpt-6.1-sol` | $2.00 / $10.00 | model page + catalog |
| `gpt-6-astra` | $10.00 / $50.00 | model page + catalog |
| `gpt-transcribe` | $0.0045 / min | model page |

Prices for the kept models (`gpt-5.2`, `gpt-5.4-mini`, `gpt-5.4`, `gpt-5.5`) are unchanged from today's descriptions.

**Rationale**: All IDs and prices in the user's list match the official pages. Prompts above 272K input tokens cost more; dictation never gets close, so descriptions show the standard rate only.

**Alternatives considered**: Adding `gpt-5.6-luna` (named on the deprecations page as the replacement for `gpt-5-nano`). Rejected: not in the user's list and not in the catalog page; GPT-6 Luna is cheaper.

### R19 — Deprecations (input to the removal list)

**Decision**: Remove these from the app, per the spec's "remove all deprecated" rule.

| Model | OpenAI shutdown | OpenAI's suggested replacement | App moves users to |
|---|---|---|---|
| `gpt-4o-mini` | 2027-01-14 | `gpt-6-luna` | `gpt-6-luna` |
| `gpt-4.1-mini` | 2027-01-14 | `gpt-6-luna` | `gpt-6-luna` |
| `gpt-5-nano` | **2026-12-11** | `gpt-5.6-luna` | `gpt-6-luna` |
| `gpt-5-mini` | **2026-12-11** | `gpt-5.6-terra` | `gpt-6-luna` |
| `gpt-5.1` | 2027-04-01 | `gpt-6-sol` | `gpt-6-luna` (user decision) |
| `gpt-5.4-nano` | 2027-04-01 | `gpt-6-luna` | `gpt-6-luna` |
| `gpt-4o-mini-transcribe`, `gpt-4o-transcribe`, `whisper-1` | 2027-02-26 | `gpt-transcribe` / `gpt-live-transcribe` | `gpt-transcribe` |
| `gpt-5.4-pro`, `gpt-5.5-pro` | not deprecated, but not usable through Chat Completions (R27) | — | `gpt-6-luna` |

**Rationale**: `gpt-5-nano` and `gpt-5-mini` weren't in the user's deprecation notice but are on OpenAI's page with an earlier date. The user confirmed removing them (spec Clarifications). For `gpt-5.1`, OpenAI suggests `gpt-6-sol`; the user chose GPT-6 Luna for everyone.

The kept models aren't deprecated: only the `gpt-5.2-chat-latest` and `gpt-5.2-codex` variants and `gpt-5.4-cyber` are, not the base IDs the app uses.

### R20 — Reasoning effort (speed and output budget)

**Finding**: Every new text model is a reasoning model that **defaults to `medium` effort** when the request doesn't set one. Reasoning tokens count against `max_completion_tokens` (the app sends 4000), so a medium-effort request can use up the budget and return empty or truncated text. It is also slower, which matters for dictation.

Supported effort values:

| Model | Supports `none` | Lowest supported |
|---|---|---|
| `gpt-6-luna`, `gpt-6-sol`, `gpt-5.6-terra` | yes | `none` |
| `gpt-5.6-sol` | yes (same family as Terra; "GPT-5.6 defaults to medium") | `none`, confirm in quickstart 5.2 |
| `gpt-6.1-sol` | **no** ("does not support `none` or `minimal`") | `low` |
| `gpt-6-astra` | **no** (`none` returns HTTP 400) | `low` |

**Decision**: Each new text model sends an explicit `reasoning_effort` set to its lowest supported value: `none` for Luna, GPT-6 Sol and both GPT-5.6 models; `low` for GPT-6.1 Sol and Astra. The kept models start with today's request shape (no `reasoning_effort`). The same risk applies to them: `gpt-5.5` also "defaults to `medium`" and supports `none`. So the live probe (quickstart 5.2) records `finish_reason` and latency for each kept model. If a model returns `length`, an empty reply, or takes more than 2× the slowest new model's latency, its `reasoningEffort` is set to its lowest supported value (`none` where supported, otherwise `low`).

**Rationale**: Text cleanup doesn't need deep reasoning. The lowest effort keeps latency near today's and leaves the 4000-token budget for visible text. It must be set per model, because sending `none` to 6.1 Sol or Astra fails.

**Alternatives considered**: Leaving the effort unset. Rejected: medium is slower and risks empty responses within 4000 tokens. Raising `max_completion_tokens` to 25,000, as the reasoning guide suggests for experiments. Rejected: it doesn't fix latency.

### R21 — Temperature (FR-035)

**Finding**: None of the official pages say whether the GPT-5.6 or GPT-6 models accept `temperature`. The existing code comment already notes that the GPT-5 reasoning tier rejects non-default values with a 400 error.

**Decision**: A per-model capability table (exact ID → `supportsTemperature`, `reasoningEffort`) replaces the family heuristic.
- New models: `supportsTemperature = false` (not confirmed, so the setting is omitted).
- Kept models: keep today's values (`true` for `gpt-5.2`, `gpt-5.4`, `gpt-5.5`; `false` for `gpt-5.4-mini`), and confirm them with the live probe in quickstart 5.2. Any kept model whose probe returns a `temperature` 400 error is flipped to `false` before release.

**Rationale**: FR-035 says a setting is sent only when confirmed. Omitting it never causes a 400; sending an unconfirmed one can.

### R22 — GPT Transcribe request shape

**Finding**: It uses the same `POST /v1/audio/transcriptions` endpoint, accepts `wav`, and has a 25 MB limit, all as today. The JSON response has `text`, which the existing parser reads, plus a new `languages` array that is ignored. Unlike the old models, it takes **`languages[]`** (multiple language hints) instead of the singular `language` ("replaces the singular `language` field… don't send both").

**Decision**: For `gpt-transcribe`, send the chosen recognition language as a single `languages[]` form field. With "auto", send no language field. Keep `response_format=json`. The request shape is chosen per model (`STTModel.languageField`), so it stays correct if more models are added later.

**Rationale**: It follows the documented parameter. Whether the server also tolerates `language` is unknown, so the plan doesn't rely on it.

**Vocabularies**: Today vocabularies go into the text model's system prompt, not the transcription request (`TranscriptionService` sends only file, model, language and format). That stays unchanged. Sending vocabulary terms as `keywords[]` would be a new behaviour, so it's out of scope and noted as a follow-up.

### R23 — Error when a model is unavailable (FR-040)

**Finding**: Today a 4xx error shows `Transcription error: <raw OpenAI JSON>` or `Formatting error: <raw JSON>`. That doesn't reliably name the model or suggest a fix.

**Decision**: A new `RecordingError.modelUnavailable(modelName: String, kind: .speechToText | .text)`, raised when OpenAI returns 404, or 400/403 with `error.code` of `model_not_found` or `model_not_available`. Localized messages:
- text: "%@ isn't available for your OpenAI account. Choose another text model in Settings."
- speech-to-text: "%@ isn't available for your OpenAI account."

No retry and no fallback. The failure is logged at ERROR with the model ID and OpenAI's error code.

### R24 — Moving saved selections (FR-037, FR-038)

**Finding**: Selections are saved as raw strings (`selectedSTTModelRawValue`, `selectedLLMModelRawValue`). A missing key means "use `Model.default`", so changing `.default` alone silently moves users who never chose a model. A saved removed ID decodes to `nil` and falls back to `.default`, but nothing is logged and the stale string stays.

**Decision**: Add a one-shot `ModelSelectionMigrator`, run at launch before any UI or request reads the settings:
1. Saved value present but not a current case → write the new default and log `Model selection migrated` (old, new, reason `removed`).
2. No saved value but `onboardingCompleted` is saved (an existing install that inherited the old default) → write the new default and log it (old = previous default `gpt-4o-mini-transcribe` / `gpt-5.1`, reason `inheritedDefault`).
3. Fresh install (no keys) → write nothing.

It doesn't need a version flag: steps 1–2 are idempotent, because after the write the value is a current case. The silent switch matches the clarification; no UI is involved.

**Alternatives considered**: Resolving lazily in the getter. Rejected: it logs on every read and never cleans up the stored value.

### R25 — Info popover size

**Finding**: The popover is a fixed 280 pt wide `VStack` with no scrolling. Ten entries, each with two lines of description, is about 600 pt tall.

**Decision**: Wrap the list in a `ScrollView` capped at 420 pt tall. The STT popover with one entry is unaffected.

### R26 — Existing test breakage

**Finding**: `VerborraTests/LLMModelTests.swift` refers to `.gpt53` and `.gpt41Nano`, and `FormattingServiceTests.swift` uses `.gpt41Nano`. None of these exist, so the test target doesn't compile today.

**Decision**: Rewrite these tests against the new catalog as part of this feature (constitution P5 requires a passing build).

### R27 — GPT-5.4 Pro and GPT-5.5 Pro don't work with Chat Completions

**Finding** (found during `/speckit-analyze`): Both model pages list `v1/chat/completions` as "Not supported"; they're available only through the Responses API (`v1/responses`). GPT-5.5 Pro: "Reasoning.effort supports: medium, high (default) and xhigh". GPT-5.4 Pro: "medium (default), high and xhigh". Verborra only calls Chat Completions, so both have failed for every request since they were added. GPT-5.5 itself is supported on Chat Completions (effort: none, low, medium (default), high, xhigh).

**Decision**: Remove both from the list (spec Clarifications). Users on them move to GPT-6 Luna through the same launch migration (R24, reason `removed`).

**Alternatives considered**: Adding a Responses API client for these two models. Rejected for this feature: it's a second request and streaming format in two services, for $30/$180 models that are poor value for dictation cleanup. It can be a separate feature.

### R28 — If the live probe finds a model unusable

**Decision**: If a model in the final list fails the quickstart 5.2 probe with its planned request shape (not just because of `temperature` or effort, which R20/R21 fix), remove it the same way as R27: delete the enum case, its localization key and test rows; its users migrate to the default automatically, because the migrator treats any unknown saved value as `removed`. Record it in this file and tell the user. If the failing model is a default (`gpt-6-luna` or `gpt-transcribe`), stop and ask the user instead of choosing a new default.

## Area F — Follow-ups merged on 2026-10-15 (US4 amendment, US2 stall test, US9, US10)

Evidence for R31: [investigation.md §3](./investigation.md) (log of 2026-10-15 and code review).

### R29 — Bar order, key mapping and menu titles (FR-023, FR-024, FR-043, FR-044)

**Decision**:

- `ControlBarView.preProcessingButtons` renders microphone `[1]`, output language `[2]`, prompt `[3]`. `handleKeyDown`: 18 → `cycleMicrophone()`, 19 → `cycleTextLanguage()`, 20 → `cyclePrompt()`.
- Keys and menus are enabled in the pre-recording phase while `.idle`, `.recording` or `.error`, and disabled in `.starting` (which now also covers a microphone switch, R31), `.transcribing` and `.formatting`. `canCycleSelections` and the menus' `isEnabled` use the same rule, so they can't drift apart.
- Each menu's content is wrapped in `Section(title) { … }`. On macOS a `Menu` renders a section header as a disabled, non-selectable title line, and adds the separator below it. The microphone menu keeps its existing `Divider()` between "System Default" and the devices inside the section, so no two separators touch. Titles come from `Localizable.xcstrings`: `controlbar.menu.inputDevice` "Input device" / "Устройство ввода", `controlbar.menu.outputLanguage` "Output language" / "Язык вывода", `controlbar.menu.prompt` "Using prompt" / "Используемый промпт".
- Cycling reads the model lists (`audioDeviceManager.devices`, `SupportedLanguage.allCases`, `promptsStore.prompts`), never the menu items, so a title can't be selected by a key (FR-044).
- `ShortcutValidator`'s overlay-key rule is unchanged (1, 2, 3 are still the window's keys).

**Rationale**: Positions and keys match, as requested. `Section` gives the native menu title look without a fake disabled `Button`.

**Alternatives considered**: *A disabled `Button` as the first item*: renders as greyed text that looks like an unavailable option, not a title. *`Text` as the first item*: SwiftUI turns it into an enabled item on some macOS versions.

### R30 — Stall test in Settings › Advanced (FR-045…FR-047)

**Decision**: Remove the `#if DEBUG` "Simulate main-thread stall (3 s)" button from `MenuBarView` (`VerborraApp.swift`). Add, inside `#if DEBUG`, a last `Section` "Developer" to `AdvancedSettingsTab` with the same button (`Thread.sleep(forTimeInterval: 3)` on main) and a caption. Strings: `settings.advanced.developer`, `settings.advanced.simulateStall`, `settings.advanced.simulateStallHint` (en + ru).

**Rationale**: Same behaviour, out of the everyday menu, and compiled out of Release builds.

### R31 — Microphone switching through the start path (FR-048…FR-057)

**Root causes** (investigation §3): (1) `startRecording` treats a host with a merely *queued* teardown as stuck and creates a second host, so two engines overlap; (2) a switch gets one 1.8 s attempt with no retry; (3) the Bluetooth trigger is limited by `setupTimeout` (1.8 s) instead of its own budget; (4) the view model stays `.recording` during a switch, so close, Esc and stop don't cancel it and it can turn the microphone on after the window is gone.

**Decision**:

1. **Host reuse.** Replace the `host.isBusy` test with an explicit `hostIsStuck` flag on the facade, set only when `raceWithTimeout` fires for a call on that host (and cleared when a new host is created). A teardown queued by `resetRecording`/`cancelStart` simply runs before the next start on the same serial queue, so stop and start never overlap (FR-050). A host is abandoned only after one of its calls actually timed out.
2. **One start path.** `RecordingViewModel` gains `beginStart(kind: StartKind)` with `StartKind = .initial | .switching(to: deviceName)`. `startRecording()` calls it with `.initial`. `switchAudioDevice` while `.recording` (or in `.error` after a failed switch, see 5) calls `stopTimers()`, `audioCaptureService.resetRecording()`, then `beginStart(.switching(to:))`. Both kinds share `.starting(attempt:)`, the retry loop, the generation checks and `cancelStart`. `switchTask` is removed.
3. **Budgets.** `.initial` keeps R7 (Bluetooth mode switch has its own 5 s, then 5 s for the start). `.switching` has one 5 s budget that starts at the switch request and includes the Bluetooth preparation and trigger (FR-049). `AudioCaptureService.startRecording` gains a `bluetoothTimeout: Duration` parameter used by `runBluetoothSwitch` instead of `setupTimeout`: 5 s for `.initial`, the remaining budget for `.switching`. This also fixes the `.initial` Bluetooth trigger, which today is cut off at 1.8 s.
4. **Cancel and close.** Because a switch is `.starting`, the existing `cancelStart(trigger:)` path handles the hotkey, Esc, ⌘W, the close button and `cleanup()` (FR-054, FR-056). `cancelStart` additionally calls `bluetoothProfileManager.restoreA2DP(device:)` when the start's target is a Bluetooth device that was prepared (FR-055). A late host result is dropped by the generation check (existing).
5. **Failure.** After two failed attempts, state becomes `.error(.recordingStartFailed(reason, deviceName:))` and `lastStartKind = .switching`. In that state `switchAudioDevice` (menu or key 1) starts `beginStart(.switching(to:))` on the new device (FR-053). After a failed `.initial` start, picking a microphone only changes the selection, as before. A failed switch to a Bluetooth device restores A2DP on it.
6. **UI.** `.starting` with `.switching(to: name)` shows "Switching to <name>…" (`recording.switching`), otherwise "Starting microphone…". The timer is stopped while starting, the Start/Stop button reads Cancel, and keys 1–3 and the menus are disabled (R29, FR-051, FR-052).
7. **Logging.** The facade resolves the device name with `CoreAudioQuery.name` before starting, so E1/E2 show names, not ids. New event E16 `Microphone switch` (see contracts/diagnostic-events.md) with `from`, `to`, `outcome` (`ok`/`failed`/`cancelled`), `durationMs`, `attempts` (FR-057).

**Rationale**: Reusing the start path gives switching the retry, budget, cancel and generation guarantees already tested for US2, instead of a second, weaker path.

**Alternatives considered**: *Keep `switchTask` and add cancel/retry to it*: duplicates the start state machine and its bugs. *Keep a new host per switch*: two engines overlapping is what makes the switch fail. *Keep the audio from before the switch*: rejected in Clarifications 2026-10-15.

### R32 — Prompt name limit (FR-058…FR-062)

**Decision**:

- `SystemPrompt.maxNameLength = 30`, counted with `String.count` (grapheme clusters, so emoji, accented letters and CJK each count as 1).
- Pure helper `PromptNameRule.clamp(new:old:) -> String`: if `new.count > 30` and `old.count <= 30`, return `String(new.prefix(30))` (typing past the limit or pasting); otherwise return `new` unchanged (so a legacy over-long name isn't silently cut while the user edits it). `SettingsViewModel.editingPromptName` applies it in `didSet`.
- Settings prompt editor: a counter `n/30` under the name field (`.secondary`, or `.red` when over the limit) and, when over, the caption `settings.prompts.nameTooLong`. The Save button is disabled and `saveCurrentPrompt()` refuses while `editingPromptName.count > 30`.
- Floating window: the prompt menu title uses `PromptNameRule.display(_:)`, which returns the name unchanged up to 30 characters and `prefix(29) + "…"` above. The prompt button sizes to its title (R34), so its width follows the name.
- A unit test checks every built-in prompt name in every language and the "New prompt" string in en and ru are ≤ 30.

**Rationale**: Enforces the limit where names are typed, without rewriting stored data (FR-060).

**Alternatives considered**: *Migrate long names at launch*: changes user data silently. *Truncate in `didSet` always*: would cut legacy names the moment the editor opens.

### R34 — Selector button widths (FR-063, FR-064)

**Decision**: The bottom bar's left group (microphone, language, prompt) and right group (Start/Stop/Cancel, Exit) are laid out in one `HStack` with a `Spacer(minLength: gap)` between them, where `gap` is the bar's normal button spacing. Each of the three left buttons (microphone, language, prompt) sizes to its title with no fixed width cap: the title asks for its ideal width and may be compressed, with `lineLimit(1)` and `truncationMode(.tail)`. Layout priorities decide who gives way when the row is too narrow: right group `layoutPriority(3)` (never shrinks), language `2`, prompt `1`, microphone `0`. So when space runs out the microphone title truncates first, then the prompt title, then (only in extreme cases) the language, and the spacer never goes below `gap`, so nothing overlaps or touches the right group. *Amended 2026-10-15 (FR-064)*: the microphone's former fixed 180 pt cap is removed and the language may now truncate too, so all three buttons follow the same rule. The right group's width is measured live, so a label change (Start ↔ Cancel ↔ Stop) or a long shortcut hint changes the room for the prompt immediately. No fixed point-width cap is used for any selector button.

**Rationale**: Gives exactly the requested behaviour (width follows the name; a maximum set by the right-hand buttons, not a constant) with SwiftUI's own layout negotiation, so it adapts to localisation and shortcut length without numbers to tune.

**Alternatives considered**: *A fixed `maxWidth` on the prompt button*: either too small (truncates names that would fit) or too large (can collide when the microphone name or shortcut is long). *Measuring text with `NSString.size` and computing widths by hand*: duplicates what the layout system does and breaks with font or language changes.

### R35 — Pre-recording window height (FR-065)

**Cause of the empty space**: the panel was a fixed 800 × 220 in the pre-recording stage; the content area (~163 pt inside the padding) was sized for the error and "no microphone" views, so the 128 pt waveform + timer block sat centered with ~17 pt of empty space above and below.

**Decision (final, 2026-10-15)**: keep a static height, reduced to **800 × 200** (`OverlayPanel.initialSize`). With the bottom bar measured at 45 pt, the content area is 155 pt: the tallest pre-recording view, "no microphone access", measured 154 pt (offscreen `NSHostingView` probe), so nothing clips; the recording block (waveform 110 + gap 2 + timer ~16) leaves ~6 pt extra above and below, on top of the 6/8 pt padding. The chat stage is unchanged; its minimum height follows `initialSize` as before.

**Tried and reverted**: *Window fits its content* (option C): one compact 189 pt height for idle/recording, growing upward for taller content. Built and tested, then reverted at the owner's request in favour of a fixed size. *Waveform fills the space* (option A) and *shrink only while recording* (option B) were not chosen.

### R33 — Bar width check

The panel is 800 pt wide. Microphone (sized to its name, ~140 pt for "MacBook Pro Microphone"), language (~110 pt), a 30-character prompt (~200 pt Latin, ~390 pt CJK at 13 pt), Start/Cancel and Exit fit in 800 pt for Latin names. For the CJK worst case the microphone title shrinks first, then the prompt title, then the language (R34). Checked manually in quickstart 4.11, 4.13 and 4.14; window height in 4.15.

## Dependencies

No new third-party dependencies. KeyboardShortcuts (2.4.0) stays, but only for Carbon registration; its `Recorder` is no longer used. New system frameworks: `ServiceManagement` (already used), `CoreGraphics` event taps (already linked through AppKit), and `Carbon.HIToolbox` for `CopySymbolicHotKeys`/`RegisterEventHotKey` (already used indirectly through KeyboardShortcuts). One new Objective-C file (the exception shim) plus a bridging header. See Complexity Tracking in plan.md.
