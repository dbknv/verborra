# Implementation Plan: Reliability, Shortcuts & Model List Update

**Branch**: `015-reliability-shortcuts-models` | **Date**: 2026-10-14, updated 2026-10-15 (merged follow-ups) | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/015-reliability-shortcuts-models/spec.md`; root-cause evidence in [investigation.md](./investigation.md)

## Summary

Eight changes ship together in **one release** (spec clarification; the model list update was merged in from an earlier spec 016, and on 2026-10-15 the follow-ups 016–018 were merged in as items 4, 6, 7 and 8):

1. **Launch at login (P1)**: the Settings toggle shows the real `SMAppService.mainApp.status` instead of an unapplied `@AppStorage` default. A new `LoginItemService` reconciles the user's intent at startup, since existing users never registered. Fresh installs are asked once on the onboarding Completion step, with "on" pre-selected. `.requiresApproval` gets a "Open Login Items" action. The Xcode project keeps **ad-hoc** signing (no Apple Developer certificate is available) and gains Hardened Runtime; a re-approval after an update is surfaced by the toggle.
2. **No hangs at recording start (P1)**: all `AVAudioEngine` and CoreAudio setup moves from the main actor to a dedicated serial queue (`AudioEngineHost`). The forced hardware-rate tap format that disagrees with stale nodes is replaced by `format: nil` plus a stale-node check that re-creates the engine. An Objective-C `@try/@catch` shim turns `NSException`s into recoverable errors. A start has a 5 s deadline and gets one automatic retry on the same device; after that, an error with "Retry". The hotkey or Esc cancels a start in progress. The automatic fallback to the default microphone is removed. Diagnostics added: per-attempt timing log, ERROR on every setup failure, a main-thread watchdog that writes WARN after 2 s, crash-on-exception in DEBUG builds, and an uncaught-exception log handler in all builds.
3. **Shortcut recorder and Fn (P2)**: a custom AppKit recorder field shows held modifiers live (Fn tracked from `flagsChanged` of keyCode 63), saves on the first regular key, rejects modifier-less, overlay-conflicting and system-reserved combos, and pauses the global hotkey while recording. Registration is **hybrid**: shortcuts without Fn keep using Carbon (via KeyboardShortcuts, no permission needed); shortcuts with Fn use an active `CGEventTap` on a background thread, which needs Accessibility (already requested). The overlay's key monitor only handles events for its own panel, so it no longer intercepts Settings keystrokes. One formatter renders `🌐︎ ⌃ ⌥ ⇧ ⌘ Key` everywhere.
4. **Floating-window selectors (P2)**: the top prompt header moves to the bottom bar. Order and keys: **1** microphone, **2** output language, **3** prompt (new cycle with wrap-around). Each menu starts with a non-selectable title ("Input device", "Output language", "Using prompt"). Keys and menus work while idle, recording or showing an error, and are disabled while starting, switching or processing (R29). Prompt choice stays per-session.

5. **Model list update (US5–US8, P1/P3)**: Replace the model catalog. Speech-to-text becomes GPT Transcribe only. The text model list becomes 10 models: 4 kept models (GPT-5.2, GPT-5.4 Mini, GPT-5.4, GPT-5.5) plus GPT-5.6 Terra/Sol, GPT-6 Luna/Sol, GPT-6.1 Sol and GPT-6 Astra. Eleven models are removed: nine deprecated ones, plus GPT-5.4 Pro and GPT-5.5 Pro, which don't support Chat Completions (R27). The defaults become GPT Transcribe and GPT-6 Luna. A one-shot launch migrator silently moves saved or inherited selections of removed models to the new defaults and logs each move. Request options become per-model: each new reasoning model sends its lowest supported `reasoning_effort` and omits `temperature`. GPT Transcribe sends `languages[]` instead of `language`. A new `modelUnavailable` error names the model. The broken model tests are rewritten.

6. **Microphone switching and closing (US9, P1)**: a mid-recording switch goes through the same start path as the hotkey (`StartKind.switching`): `.starting` state, retry, one 5 s budget that includes the Bluetooth step, cancel by close/Esc/hotkey/stop with A2DP restore, generation checks. The audio host is reused unless a call on it timed out, so stop and start never overlap. The Bluetooth trigger gets its own timeout instead of the 1.8 s setup limit (R31, investigation §3).
7. **Prompt name limit (US10, P3)**: 30 characters with a counter in Settings; longer stored names kept, shortened with "…" in the bar, and must be shortened before saving (R32). All three selector buttons (microphone, language, prompt) follow their title's width with no fixed cap, up to the room left before the right-hand buttons; when space runs out the microphone title shortens first, then the prompt, then the language (R34, FR-063, FR-064). The pre-recording window has a fixed height of 200 pt instead of 220 pt (R35, FR-065; a fit-to-content window was tried and reverted).
8. **Stall test in Settings (US2)**: the DEBUG-only "Simulate main-thread stall (3 s)" moves from the menu bar menu to a Developer section in Settings › Advanced (R30).

Everything stays in the existing single-target app. There are no new SPM dependencies. One small Objective-C file is added, justified in Complexity Tracking.

## Technical Context

**Language/Version**: Swift 5.9+ (Xcode 16), plus one Objective-C file (the `NSException` shim) with a bridging header

**Primary Dependencies**: SwiftUI, AppKit (NSPanel, NSView first responder), AVFoundation (AVAudioEngine), CoreAudio, ServiceManagement (`SMAppService`), CoreGraphics (`CGEventTap`), Carbon.HIToolbox (`CopySymbolicHotKeys`, `RegisterEventHotKey`), KeyboardShortcuts 2.4.0 (Carbon registration only; its `Recorder` is dropped), swift-atomics 1.3.0, swift-markdown 0.7.x. **No new packages.**

**Storage**: UserDefaults: `selectedSTTModelRawValue` / `selectedLLMModelRawValue` (model selection, migrated once at launch, R24), `launchAtLogin` (now intent only), `globalShortcut.v1` (new JSON, migrated from `KeyboardShortcuts_toggleOverlay`), `NSApplicationCrashOnExceptions` (registered default). The legacy `recordingKeyCode`/`recordingModifiers` are removed. Diagnostic JSONL logs as before (spec 007).

**Testing**: XCTest / Swift Testing in `VerborraTests` (existing). Unit tests cover the pure logic: `ShortcutValidator`, `ShortcutFormatter`, `GlobalShortcut` coding and migration, Fn-tracking state machine (fed synthetic flag and key sequences), `LoginItemService.reconcile` decision table (mock `SMAppService` wrapper), start-retry and cancel state machine in `RecordingViewModel` (via `MockAudioCaptureService` with injectable failures and delays), `cyclePrompt` wrap and fallback, the watchdog stall detector (injected clock), the model catalog (`LLMModel`/`STTModel` cases, defaults, per-model request flags), `ModelSelectionMigrator` transition table, and request shape / `modelUnavailable` mapping in the three OpenAI services via `MockURLProtocol`. Manual QA covers real audio devices, login, signing, the global Fn hotkey and real OpenAI calls, including a live per-model capability probe ([quickstart.md](./quickstart.md) §0–§5).

**Target Platform**: macOS 15 (Sequoia), macOS 26 (Tahoe) and later

**Project Type**: Single desktop app (menu-bar, `LSUIElement`), Xcode project with explicit file references, so new files must be added to `project.pbxproj` (and `project.yml` kept in sync)

**Performance Goals**: recording start succeeds or shows an error in ≤ 5 s (FR-007), with typical starts unchanged (median 44 ms, so the constitution's ≤ 300 ms hotkey-to-ready target still holds); a start cancels in ≤ 1 s (FR-013a; designed for under 50 ms); a microphone switch resumes within 2 s (wired, built-in, USB) or 5 s (Bluetooth, Continuity) and closing during it takes ≤ 1 s (FR-048, FR-054); modifier display under 100 ms (SC-007); hang detection within ≤ 2.5 s of the stall starting; watchdog overhead is 2 dispatches per second; formatting latency on the new models in line with today's (lowest reasoning effort, R20); the model migrator adds under 1 ms at launch

**Constraints**: never block main with CoreAudio or engine calls; never run the event tap on the main run loop; the watchdog never touches main-actor state; never switch microphone automatically; Fn shortcuts require Accessibility; no change to user-selectable log modes; OpenAI Chat Completions and Audio Transcriptions APIs only; no fallback model and no UI notice when a model selection is migrated

**Scale/Scope**: 11 new source files (including the Objective-C .h/.m and the bridging header), about 15 modified, 5 deleted (see Project Structure); plus 1 new file (`ModelSelectionMigrator.swift`) and about 8 modified for the model list; 10 user stories, 66 FRs (FR-001–FR-065 + FR-013a). The 2026-10-15 follow-ups add no new files except tests: they modify ControlBarView, RecordingViewModel, RecordingView, AudioCaptureService, RecordingState, AdvancedSettingsTab, SettingsView, SettingsViewModel, SystemPrompt, VerborraApp and Localizable.xcstrings

**Signing/runtime**: ad-hoc ("Sign to Run Locally"; amended 2026-10-15, owner has no Apple certificate) with **Hardened Runtime enabled** (`ENABLE_HARDENED_RUNTIME = YES`), per constitution Principle 4 (v2.0.1; unchanged in v2.0.2). The existing `com.apple.security.device.audio-input` entitlement is the Hardened Runtime microphone entitlement. CGEventTap, CGEvent paste and the Accessibility API need no extra runtime exceptions.

**Development tooling** (not part of the app): SwiftLint via Homebrew, configured by a repo-root `.swiftlint.yml`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| 1. Native macOS experience | ✅ Pass | SwiftUI plus native AppKit (an `NSView` recorder through `NSViewRepresentable`, the existing NSPanel). The global hotkey uses Carbon and CGEvent, both in the constitution's stack table. The overlay still doesn't steal focus, and the key monitor is narrowed to its own panel. Uses the HIG globe glyph for Fn. |
| 2. Swift-first development | ⚠️ Justified | All logic is in Swift with MVVM and `@Observable`. **One Objective-C file** (`ObjCExceptionCatcher.m`) is needed because Swift can't catch `NSException` thrown by AVAudioEngine, a system API with no Swift-safe wrapper. That fits the principle's ObjC allowance in spirit. Logged in Complexity Tracking. No new SPM dependencies; KeyboardShortcuts is used less. |
| 3. Minimalism and simplicity | ✅ Pass | No new windows. The bottom bar gains one menu while the top header goes away, so the element count is unchanged. Menu titles reuse the native menu section header; the prompt-name counter is one caption under an existing field; the stall test leaves the menu bar menu. Onboarding gains one toggle on an existing step. Settings stay in UserDefaults. Hotkey-to-ready latency is unchanged in the normal path. |
| 4. Security and privacy (v2.0.1) | ✅ Pass | No audio is saved, and no keys or telemetry are added. Constitution v2.0.1 runs the app without App Sandbox and requires compensating controls instead. This feature meets each of them: **no new entitlements** (`Verborra.entitlements` stays audio input + app-scoped bookmarks); **Hardened Runtime on an ad-hoc build** (team signing dropped 2026-10-15: no certificate; re-approval states are surfaced in Settings); the event tap **doesn't log or store keystrokes** (it logs only "hotkey triggered" and its own enable/disable state); and the tap **runs on a dedicated background thread**, never main. The tap uses the Accessibility permission the app already requests, and revocation is shown in Settings. |
| 5. Code quality and testing (v2.0.1) | ✅ Pass | New logic sits behind protocols (`LoginItemServiceProtocol`, `GlobalHotkeyServiceProtocol`, an `AudioEngineHosting` seam) and is unit-tested (see Testing). Errors reach the user with clear messages (`recordingStartFailed` now naming the microphone, login item errors, shortcut rejection reasons). Switching reuses the tested start state machine instead of a second path; `PromptNameRule` and the switch transitions are unit-tested. Zero warnings is required. SwiftLint is a **development-only** tool (Homebrew on the developer machine; repo-root `.swiftlint.yml`). It is never an SPM package, build plugin or bundled resource. Lint is required for every file this feature changes. |
| 6. Logging and observability (v2.0.1) | ✅ Pass | Adds ERROR for every audio setup failure with method, parameters and reason; INFO step timings; INFO for login item changes; INFO for shortcut changes `old → new`; INFO for prompt changes; INFO/ERROR `Microphone switch` with names, outcome and duration (E16). **WARN** for main-thread stalls uses the WARN severity the constitution allows (since v2.0.0), written whenever ERROR is; the four modes don't change (research R12). Each new service gets its own `os.Logger` category: `.hotkey` (GlobalHotkeyService, FnEventTap, recorder), `.loginItem` (LoginItemService), `.watchdog` (MainThreadWatchdog). `AudioEngineHost` uses the existing `.engine` category, which is defined as AVAudioEngine lifecycle. No keystrokes, transcripts or keys are logged. |

**Model list (US5–US8)**: P1 same SwiftUI pickers, the info popover gains a `ScrollView`; P2 Swift only, `URLSession` async/await, no new packages; P3 no new settings or UI elements; P4 API key handling unchanged, no new entitlements; P5 catalog, migrator, request shape and error mapping are unit-tested, and this work fixes the test target that doesn't compile today (R26); P6 migration logged at INFO with old → new, `modelUnavailable` logged at ERROR with method, model, code and OpenAI's message. The tech-stack wording ("OpenAI Whisper API") was amended to "OpenAI Audio Transcriptions API" in constitution **v2.0.2** (PATCH), because `whisper-1` is removed.

**Gate result (pre-research)**: PASS against constitution **v2.0.1**, re-checked against **v2.0.2** (wording-only PATCH for the speech-to-text API name) (v2.0.0 amended 2026-10-14: no App Sandbox, development-only SwiftLint, WARN severity; v2.0.1 clarifies which input observers must stay off the main thread), with one justified item (Objective-C shim).

**Re-check after Phase 1 design** (including the 2026-10-15 follow-ups, R29–R34): PASS. The design adds no persistence beyond UserDefaults, no network surface, and no dependency. The contracts confirm that the watchdog and the tap never call main-actor code and that tap logs contain no key data.

## Project Structure

### Documentation (this feature)

```text
specs/015-reliability-shortcuts-models/
├── spec.md                         # Feature spec (clarified)
├── investigation.md                # Root-cause evidence (pre-spec)
├── plan.md                         # This file
├── research.md                     # Phase 0: decisions R1–R17 (Areas A–D), R18–R28 (Area E, model list)
├── data-model.md                   # Phase 1: entities and state machines
├── quickstart.md                   # Phase 1: validation guide
├── contracts/
│   ├── login-item.md               # LoginItemService API + reconcile table + UI states
│   ├── recording-start.md          # Start state machine, budget, retry, cancel, errors
│   ├── global-shortcut.md          # GlobalShortcut model, recorder behaviour, validator, registration
│   ├── floating-window-keys.md     # Bottom bar layout + 1/2/3 key contract + hint glyphs
│   ├── diagnostic-events.md        # New log events (timings, setup ERROR, WARN stall, login, shortcut, prompt, model migration)
│   ├── openai-requests.md          # Per-model request shape + model-unavailable error mapping (US5, US6, FR-040)
│   └── model-selection.md          # Settings model pickers, launch migration guarantees, migration log event (US7, US8)
├── checklists/
│   └── requirements.md
└── tasks.md                        # Phase 2 (/speckit-tasks; not created here)
```

### Source Code (repository root)

```text
Verborra/
├── VerborraApp.swift                          # MOD: launch → uncaught-exception handler (all builds) + crash-on-exception (DEBUG only),
│                                              #      ModelSelectionMigrator.run() after logging setup, before AppController,
│                                              #      watchdog start, LoginItemService.reconcile, GlobalHotkeyService;
│                                              #      AppDelegate owns GlobalHotkeyService (Settings scene needs it before launch);
│                                              #      stall test moved out of the menu bar menu (R30)
├── Verborra-Bridging-Header.h                 # NEW: imports ObjCExceptionCatcher.h
├── Support/
│   ├── ObjCExceptionCatcher.h                 # NEW: VBRTryCatch(void(^)(void)) -> NSError*
│   └── ObjCExceptionCatcher.m                 # NEW: @try/@catch NSException shim
├── Models/
│   ├── AppSettings.swift                      # MOD: launchAtLogin = intent (+ "never set" detection);
│   │                                          #      remove recordingKeyCode/recordingModifiers/recordingKeyDisplayName
│   ├── RecordingState.swift                   # MOD: + .starting(attempt:), + RecordingError.recordingStartFailed(StartFailureReason, deviceName:),
│   │                                          #      + RecordingError.modelUnavailable(modelName:kind:) (US5–US8)
│   ├── LLMModel.swift                         # MOD: 10 cases, per-case supportsTemperature + reasoningEffort, default .gpt6Luna
│   ├── STTModel.swift                         # MOD: 1 case (gpt-transcribe), languageField, default .gptTranscribe
│   ├── ModelSelectionMigrator.swift           # NEW: one-shot launch migration of removed/inherited model selections
│   ├── SystemPrompt.swift                     # MOD: maxNameLength = 30, PromptNameRule (clamp, display) (R32)
│   ├── TokenEstimator.swift                   # MOD: context limits for the new models (922_000)
│   ├── GlobalShortcut.swift                   # NEW: GlobalShortcut, ShortcutModifiers, ShortcutFormatter, GlobalShortcutStore
│   ├── ShortcutValidator.swift                # NEW: ShortcutValidator, ShortcutRejection, ShortcutValidationResult
│   ├── LogEntry.swift                         # MOD: severity label supports "WARN"
│   └── LogCategory.swift                      # MOD: + .hotkey, .loginItem, .watchdog
├── Services/
│   ├── AudioCaptureService.swift              # MOD: becomes facade over AudioEngineHost; deadline + generation;
│   │                                          #      remove default-device fallback + onDeviceFallback;
│   │                                          #      hostIsStuck instead of isBusy; bluetoothTimeout; device name resolved up front (R31)
│   ├── AudioEngineHost.swift                  # NEW: serial-queue engine owner, stale-node check, timings, ObjC-safe calls
│   ├── HotkeyService.swift                    # REPLACED by GlobalHotkeyService.swift (Carbon path + Fn CGEventTap path)
│   ├── GlobalHotkeyService.swift              # NEW
│   ├── FnEventTap.swift                       # NEW: background-thread CGEventTap + Fn tracking state machine
│   ├── LoginItemService.swift                 # NEW: SMAppService wrapper + reconcile
│   ├── FormattingService.swift                # MOD: reasoning_effort per model; modelUnavailable mapping
│   ├── StreamingFormattingService.swift       # MOD: same request shape + mapping
│   ├── TranscriptionService.swift             # MOD: languages[] per languageField; modelUnavailable mapping
│   └── Logging/
│       ├── DiagnosticLogger.swift             # MOD: + warn(_:metadata:); thread-safe LogFilterSnapshot for shouldLog
│       │                                      #      (no provider closures off main; app state only on main)
│       └── MainThreadWatchdog.swift           # NEW: ping/pong stall detector + HangContext
├── ViewModels/
│   ├── RecordingViewModel.swift               # MOD: startTask + retry + cancel; StartKind, switch via beginStart (R31); cyclePrompt;
│   │                                          #      1 mic / 2 language / 3 prompt; keys in idle/recording/error; window-scoped keys;
│   │                                          #      HangContext updates; prompt-change logging
│   ├── SettingsViewModel.swift                # MOD: login status/intent/approval; shortcut set/reset/validation; remove hasRecordingHotkeyConflict;
│   │                                          #      prompt name clamp + save guard (R32)
│   └── OnboardingViewModel.swift              # MOD: launchAtLogin choice applied on completeOnboarding()
├── Views/
│   ├── OverlayContentView.swift               # MOD: remove top PromptSelectorView; key monitor moved to OverlayManager
│   ├── OverlayPanel.swift                     # MOD: OverlayManager installs/removes window-scoped key monitor with show/dismiss
│   ├── ControlBarView.swift                   # MOD: mic [1], language [2], prompt [3]; Section titles; prompt title via PromptNameRule; left/right groups with min gap + layout priorities (R34);
│   │                                          #      formattedShortcutLabel → ShortcutFormatter
│   ├── RecordingView.swift                    # MOD: .starting UI ("Starting microphone…" / "Switching to <name>…"); recordingStartFailed retryable
│   ├── SettingsView.swift                     # MOD: login row bound to real status + approval action + error;
│   │                                          #      prompt name counter n/30, over-limit message, Save disabled (R32)
│   ├── AdvancedSettingsTab.swift              # MOD: #if DEBUG Developer section with the stall test (R30)
│   ├── HotkeysSettingsTab.swift               # MOD: new recorder + reset + warnings (Accessibility needed for 🌐︎)
│   ├── LLMSettingsTab.swift                   # MOD: model info popover in a ScrollView (maxHeight 420)
│   ├── Onboarding/CompletionStep.swift        # MOD: "Start Verborra at login" toggle (on by default)
│   └── Components/
│       ├── HotkeyRecorder.swift               # REPLACED by ShortcutRecorderField.swift
│       ├── ShortcutRecorderField.swift        # NEW: NSView recorder + NSViewRepresentable wrapper
│       ├── PromptSelectorView.swift           # DELETE (moved into ControlBarView)
│       ├── MicrophoneSelectorButton.swift     # DELETE (unused)
│       └── LanguageSelectorView.swift         # DELETE (unused)
└── Localizable.xcstrings                      # MOD: new strings (en + ru): login states, shortcut hints/warnings,
                                               #      "Starting microphone…", recordingStartFailed, onboarding toggle;
                                               #      model descriptions (+7 / −11 keys), error.modelUnavailable.{text,stt}
VerborraTests/
├── LLMModelTests.swift                        # REWRITE: catalog, order, defaults, per-model flags (doesn't compile today)
├── STTModelTests.swift                        # NEW
├── Models/ModelSelectionMigratorTests.swift   # NEW: transition table + idempotency
├── Models/TokenEstimatorTests.swift           # MOD: new cases
├── Services/FormattingServiceTests.swift      # MOD: removed cases; reasoning_effort/temperature per model; 404 mapping
├── Services/StreamingFormattingServiceTests.swift # MOD: same
├── Services/TranscriptionServiceTests.swift   # MOD: languages[]; 404 mapping
├── ViewModels/SettingsViewModelTests.swift    # MOD: new defaults
├── Models/GlobalShortcutTests.swift           # NEW: coding, migration, formatter
├── Models/ShortcutValidatorTests.swift        # NEW: validation rules in order
├── Services/FnTrackingTests.swift             # NEW: Fn state machine incl. arrow/F-key false-positive cases
├── Services/LoginItemServiceTests.swift       # NEW: reconcile decision table
├── Logging/MainThreadWatchdogTests.swift      # NEW: stall/recover with injected clock
├── Logging/DiagnosticLoggerTests.swift        # MOD: WARN filtering, off-main calls never invoke providers
├── ViewModels/RecordingStartTests.swift       # NEW: retry, deadline, cancel-by-hotkey, no device switch
├── ViewModels/RecordingViewModelTests.swift   # MOD: 1 mic / 2 language / 3 prompt, cyclePrompt wrap/single/deleted, state guards;
│                                              #      new startRecording signature
├── ViewModels/MicrophoneSwitchTests.swift     # NEW: switch → starting, retry, budget, cancel by close/stop, A2DP restore,
│                                              #      keys disabled, pick after failed switch (R31)
├── Models/PromptNameRuleTests.swift           # NEW: clamp, display, built-in names ≤ 30 (R32)
├── ViewModels/DictationFlowTests.swift        # MOD: new startRecording signature; .gpt41Nano → .gpt52
└── Mocks/MockAudioCaptureService.swift        # MOD: scripted failures / delays / cancellation observation
Verborra.xcodeproj/project.pbxproj             # MOD: signing stays ad-hoc + ENABLE_HARDENED_RUNTIME; new files;
                                               #      SWIFT_OBJC_BRIDGING_HEADER
project.yml                                    # MOD: add swift-atomics package; bridging header; keep signing in sync
.swiftlint.yml                                 # NEW: development-only lint config (not part of the app bundle)
```

**Structure Decision**: Keep the existing single Xcode target layout (`Verborra/` Models, Services, ViewModels and Views; `VerborraTests/` mirrored). The only new folder is `Verborra/Support/` for the Objective-C shim, which keeps non-Swift code isolated and easy to spot.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Objective-C source file (`ObjCExceptionCatcher.m`) plus bridging header (Principle 2: Swift-first) | `AVAudioEngine.installTap`/`prepare`/`start` raise `NSException` on format or HAL errors. Swift can't catch it, and it gets swallowed by the run loop, leaving the app hung or crashing in `MainActor.assumeIsolated` (investigation §2). About 15 lines of `@try/@catch` is the only way to make these failures recoverable (FR-010). | *Prevent only (tap `format: nil` + stale-node check)*: removes the known trigger but leaves other AVAudioEngine exceptions fatal. *Crash-on-exception only*: turns hangs into crashes, but the user still loses the session, which fails FR-013's "recoverable error". |
| Hotkey to ready can exceed 300 ms on recovery paths (Principle 3: "MUST NOT exceed 300 ms") | The **normal path** stays well within 300 ms (median 44 ms; checked in T097). Two paths take longer by design: (1) the **automatic retry** after a failed first attempt (FR-013), ready after up to about 5 s; (2) the **Bluetooth mode switch** (existing since feature 009), up to 5 s before the engine starts. Both are recovery or hardware-bound steps that the user can see ("Starting microphone…" / "Switching…") and cancel with the hotkey or Esc (FR-013a). | *Fail at 300 ms without retrying*: turns transient post-idle failures (the cause of today's hangs) into errors the user has to retry by hand, which is worse. *Skip the Bluetooth mode switch*: records at the wrong sample rate or gets no audio from AirPods. Neither path can be made faster than the hardware allows. |
| Second global-hotkey mechanism (CGEventTap) alongside Carbon | Carbon `RegisterEventHotKey` has no Fn modifier bit, and FR-015/FR-019 require global Fn shortcuts. | *Event tap for every shortcut*: makes the default ⌥Space depend on Accessibility and routes all keystrokes through a tap. *Global NSEvent monitor*: listen-only, so it can't swallow the event and Fn+Space would type into the target app. |

## Phase 0 — Research

See [research.md](./research.md). Resolved decisions:

- **Login item** (R1–R4): system status is the source of truth; reconcile at launch after onboarding; onboarding Completion toggle; team signing in the actual pbxproj.
- **Hang prevention** (R5–R13): `AudioEngineHost` serial queue; tap `format: nil` plus stale-node re-create plus ObjC shim; 5 s budget split 1.8 s + 0.6 s + up to 2.4 s, starting after any Bluetooth mode switch (spec clarification); generation tokens; one same-device retry orchestrated by `RecordingViewModel`, then Retry UI; remove default-device fallback; `.starting` state cancellable by hotkey or Esc; main-thread watchdog with lock-protected `HangContext`; `NSApplicationCrashOnExceptions` in DEBUG builds only, plus an uncaught-exception log handler in all builds; `warn()` severity filtered like ERROR; one timing line per attempt.
- **Shortcuts** (R14–R16): own `GlobalShortcut` model and AppKit recorder; Fn from `flagsChanged` keyCode 63 only; hybrid Carbon / background `CGEventTap`; validator (modifier required, overlay keys, app menu keys, symbolic hotkeys, taken by another app); overlay key monitor scoped to its panel; hotkey paused while recording a shortcut.
- **Model list** (R18–R28): IDs, prices and context sizes; deprecation and removal list; lowest reasoning effort per new model; per-model temperature; `languages[]` for GPT Transcribe; `modelUnavailable` error; launch migrator; popover scrolling; broken model tests; Pro models are Responses-only; what to do when the live probe finds an unusable model.
- **Floating window** (R17, amended by R29): order microphone `[1]`, language `[2]`, prompt `[3]`; `Section` menu titles; `cyclePrompt` with live list and default fallback; keys and menus in idle, recording or error.
- **Follow-ups merged 2026-10-15** (R30–R35): stall test in Settings › Advanced (DEBUG); microphone switch through the start path with host reuse, own Bluetooth timeout and cancel on close; prompt name limit with `PromptNameRule`; bar width check; selector button widths follow their titles with a maximum set by the right-hand buttons (R34).

## Phase 1 — Design & Contracts

- [data-model.md](./data-model.md): `LoginItemState`, `GlobalShortcut`/`ShortcutModifiers`, `HotkeyRegistrationStatus`, `RecordingState.starting` + `StartFailureReason`, `StartAttempt`/`AudioSetupTimings`, `HangContext`, session selection, model catalog and `ModelSelectionMigrator` (§6).
- [contracts/login-item.md](./contracts/login-item.md)
- [contracts/recording-start.md](./contracts/recording-start.md)
- [contracts/global-shortcut.md](./contracts/global-shortcut.md)
- [contracts/floating-window-keys.md](./contracts/floating-window-keys.md)
- [contracts/diagnostic-events.md](./contracts/diagnostic-events.md)
- [contracts/openai-requests.md](./contracts/openai-requests.md)
- [contracts/model-selection.md](./contracts/model-selection.md)
- [quickstart.md](./quickstart.md): validation scenarios mapped to SC-001…SC-020 (§5 covers the model list; 2.9–2.11 switching and closing; 4.10–4.15 menu titles, prompt names, selector button widths and window height).

**Implementation order** (as in [tasks.md](./tasks.md), IDs T001–T098 follow it): setup, including the signing config, then Foundational (diagnostics: WARN logging; the shortcut model; the model catalog, which also fixes the test target). Then the P1 stories: US5, US6, US7 (model list, tested early because of the 2026-12-11 shutdown), US1 (login item), US2 (audio host, retry, cancel). Then the P2 stories: US4 (selectors, low risk) and US3 (recorder plus Fn tap, which has the most new surface). Then US8 (P3) and Phase 11 (model-unavailable error, docs, release validation). The 2026-10-15 follow-ups are appended as new phases after T098 (IDs from T099): US4 amendment, US9 switching (P1), US10 prompt names, stall test move, then their docs and manual checks. Existing task IDs and their completion marks are kept. The stories are independent and can be tested in any order; everything ships in one release.

**Model list placement**: the model catalog replacement goes into Foundational, because the test target doesn't compile today (stale model cases, R26), which blocks every story's tests. US5–US7 should be built right after Foundational so they're tested early: GPT-5 Nano/Mini shut down on 2026-12-11, and since everything ships in one release, the whole release should be ready before then (spec Assumptions accept the risk if it isn't). The live capability probe (quickstart 5.2) is a release gate. The 2-week soak (quickstart 2.8, SC-003) runs after the release and doesn't gate it.

### Model list risks

| Risk | Mitigation |
|---|---|
| Kept models (GPT-5.5 etc.) may already reject `temperature: 0.2`, or run slowly or truncate at their default medium effort | 5.2 probe records the error code, `finish_reason` and latency; flip `temperature` (R21) or set the lowest effort (R20) |
| A model fails the probe for another reason | Remove it (R28); if it's a default, stop and ask the user |
| `gpt-5.6-sol` effort values were taken from the Terra page | 5.2 probe; fall back to `low` |
| GPT-5.1 users (old default, probably most users) get noticeably different formatting from GPT-6 Luna | Accepted by the user (spec Assumptions); logged in the migration event |
| Users lose the removed models before OpenAI's shutdown dates | Accepted by the user (spec Clarifications) |

## Phase 2 — Out of /speckit-plan scope

`tasks.md` is produced by `/speckit-tasks`.
