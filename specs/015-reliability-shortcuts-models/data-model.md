# Data Model — Reliability & Shortcut Fixes

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Research**: [research.md](./research.md)

Persistent data stays in UserDefaults. Everything else is in-memory.

---

## 1. Login Item State (US1)

### `LoginItemIntent` (persisted)

| Field | Type | Storage | Notes |
|---|---|---|---|
| `launchAtLogin` | `Bool?` | UserDefaults key `launchAtLogin` (existing) | `nil` (key absent) means "never chosen" and is **treated as `true`** for existing users (FR-005). Written by the Settings toggle and the onboarding Completion step. |

### `LoginItemStatus` (derived, never persisted)

Mirrors `SMAppService.Status`:

| Case | Meaning | Settings UI |
|---|---|---|
| `.enabled` | Registered and allowed | Toggle **on** |
| `.notRegistered` | Not registered | Toggle **off** |
| `.requiresApproval` | Registered but disabled in System Settings › Login Items | Toggle **off**, caption "Needs approval in System Settings", button **Open Login Items** (FR-003) |
| `.notFound` | The system can't find the app's service, e.g. a stale or unsigned copy | Toggle **off**, caption with the error, button **Open Login Items** |

Plus a transient `lastError: String?` (last register/unregister failure, shown under the toggle; FR-004), and `isRunningFromApplications: Bool` (derived from `Bundle.main.bundleURL`; when false, Settings shows a "move to Applications" caption; spec edge case "multiple copies").

**Validation and rules**

- The toggle's displayed value is `status == .enabled` (FR-001), never the intent.
- Flipping the toggle writes the intent first, then calls `register()`/`unregister()`, then refreshes `status`. If the call fails, the toggle snaps back to the real status and shows the error (AS 1.5).
- `status` is refreshed when Settings appears and on `NSApplication.didBecomeActiveNotification` (SC-002).
- The startup reconcile table is in [contracts/login-item.md](./contracts/login-item.md).

---

## 2. Global Shortcut (US3)

### `ShortcutModifiers` (OptionSet, `UInt8`)

| Bit | Member | Glyph | Display order |
|---|---|---|---|
| 1 << 0 | `fn` | `🌐︎` (U+1F310 U+FE0E) | 1 |
| 1 << 1 | `control` | `⌃` | 2 |
| 1 << 2 | `option` | `⌥` | 3 |
| 1 << 3 | `shift` | `⇧` | 4 |
| 1 << 4 | `command` | `⌘` | 5 |

The order follows FR-028 (🌐︎ ⌃ ⌥ ⇧ ⌘). Conversions: `carbonFlags` (excluding `fn`), `CGEventFlags` (`fn` → handled separately, see FnTracker), `NSEvent.ModifierFlags`.

### `GlobalShortcut` (persisted, `Codable`, `Equatable`)

| Field | Type | Notes |
|---|---|---|
| `keyCode` | `UInt16` | Virtual key code (`kVK_*`). Must not be a modifier key code (54–63, 179). |
| `modifiers` | `ShortcutModifiers` | Must not be empty. |

- **Storage**: UserDefaults `globalShortcut.v1` (JSON `{"keyCode":49,"modifiers":4}`).
- **Default**: `{ keyCode: 49 /* Space */, modifiers: [.option] }`, which is ⌥Space as today.
- **Migration** (once, if `globalShortcut.v1` is absent): read `KeyboardShortcuts_toggleOverlay` (JSON `{"carbonKeyCode":…,"carbonModifiers":…}`), map Carbon modifiers to `ShortcutModifiers`, and save. If it's missing or unreadable, use the default. Log INFO `"Global shortcut migrated"`.
- **Derived**: `requiresEventTap = modifiers.contains(.fn)`; `displayString` produced by `ShortcutFormatter` (e.g. `"🌐︎ ⌥ Space"`).
- **Removed**: `AppSettings.recordingKeyCode`, `recordingModifiers`, `recordingKeyDisplayName`, and `SettingsViewModel.hasRecordingHotkeyConflict`.

### `ShortcutValidationResult`

`ok` or `rejected(ShortcutRejection)`, where `ShortcutRejection` is one of:
`modifierRequired`, `conflictsWithOverlay`, `reservedByApp`, `reservedBySystem`, `inUseByAnotherApp`. Each maps to one localized warning string. The order of checks is in [contracts/global-shortcut.md](./contracts/global-shortcut.md).

### `HotkeyRegistrationStatus` (in-memory, observable by Settings)

| Case | When |
|---|---|
| `.active(mechanism: .carbon / .eventTap)` | Registered and listening |
| `.needsAccessibility` | The shortcut contains Fn and `AXIsProcessTrusted() == false` |
| `.failed(String)` | Carbon registration failed or the event tap couldn't be created |
| `.paused` | The Settings recorder is capturing |

### Recorder field state machine (`ShortcutRecorderField`)

```text
idle ──click/focus──▶ recording(held: [])
recording(held) ──flagsChanged──▶ recording(held')            # live display (FR-014)
recording(held≠∅) ──flagsChanged → all released──▶ recording(held: [])   # placeholder (AS 3.5)
recording(held) ──keyDown Esc──▶ idle (previous kept)         # FR-018
recording(held=∅) ──keyDown key──▶ recording + hint "modifier required"   # FR-017
recording(held≠∅) ──keyDown key──▶ validate
        ok       ──▶ save, log old→new, resign focus ──▶ idle  # FR-016, FR-022
        rejected ──▶ warning, previous kept ──▶ idle           # FR-021
recording ──focus lost──▶ idle (previous kept)
```

While in `recording`, `GlobalHotkeyService.isPaused == true`.

### `FnTracker` (pure state machine, unit-tested)

| Input | Effect |
|---|---|
| `flagsChanged(keyCode: 63 or 179, fnFlag: true)` | `fnHeld = true` |
| `flagsChanged(keyCode: 63 or 179, fnFlag: false)` | `fnHeld = false` |
| `flagsChanged(other keyCode)` | Fn unchanged; other modifiers taken from the flags |
| `keyDown(keyCode, flags)` | Effective modifiers = `flags` without `secondaryFn`, mapped, **plus `.fn` iff `fnHeld`** |

This is why ↑/F5/Home on their own (which report `secondaryFn`) are **not** treated as Fn shortcuts.

---

## 3. Recording start (US2)

### `RecordingState` (modified)

```swift
enum RecordingState: Equatable {
    case idle
    case starting(attempt: Int)          // NEW: 1 or 2
    case recording(duration: TimeInterval, remaining: TimeInterval)
    case transcribing
    case formatting
    case error(RecordingError)
}
```

### `RecordingError` (extended)

- New case `recordingStartFailed(StartFailureReason, deviceName: String)`, which is retryable in `RecordingView`. `deviceName` is the microphone's display name ("System Default" for the default), so the message names the microphone (FR-053).
- `StartFailureReason`: `timeout(step: String)`, `formatMismatch(node: Double, hardware: Double)`, `audioException(name: String, reason: String)`, `engineStartFailed(String)`, `deviceUnavailable`.
- User-facing message: "Couldn't start <deviceName> (<short reason>). Press Retry or close the window." 
- US5–US8 add one more case, `modelUnavailable(modelName:kind:)`; see [section 6](#6-model-catalog-and-selection-us5us8).

### `StartKind` (in-memory, on `RecordingViewModel`, R31)

```swift
enum StartKind: Equatable {
    case initial                       // hotkey, Start button, Retry, auto-record
    case switching(to: String)         // microphone switch during recording; display name of the target
}
```

`startKind` describes the current or last `.starting`. The UI shows "Starting microphone…" or "Switching to <name>…". `lastStartKind == .switching` in `.error(.recordingStartFailed)` means picking a microphone starts a new switch (FR-053).

### State transitions (pre-recording phase)

```text
idle ──hotkey/Start──▶ starting(1)
starting(1) ──success──▶ recording
starting(1) ──fail/timeout──▶ starting(2)               # same device, fresh engine (FR-013)
starting(2) ──success──▶ recording
starting(2) ──fail/timeout──▶ error(recordingStartFailed) # Retry button
starting(n) ──hotkey / Esc / close──▶ idle               # cancel ≤1 s (FR-013a)
error(recordingStartFailed) ──Retry / hotkey──▶ starting(1)
recording ──pick another microphone──▶ starting(1) [switching]          # capture stopped first, timer stopped (R31)
error(recordingStartFailed) [after a switch] ──pick a microphone──▶ starting(1) [switching]
```

A switch uses the same `starting(1) → starting(2) → recording | error` path and the same cancel rule. Its 5 s budget starts at the request and includes the Bluetooth step (FR-049); `.initial` keeps the budget below.

Rules: no transition ever changes `selectedAudioDeviceID` (FR-013, no automatic switch). The whole `idle → recording/error` path completes within 5 s, Bluetooth stabilization excluded (research R7).

### `StartAttempt` (in-memory, inside `AudioCaptureService`)

| Field | Type | Notes |
|---|---|---|
| `generation` | `UInt64` | Monotonic. Late results from an older generation are torn down and ignored. |
| `attempt` | `Int` | 1 or 2 |
| `deviceID` | `String?` | `nil` = System Default |
| `deadline` | `ContinuousClock.Instant` | Per-attempt budget |
| `host` | `AudioEngineHost` | Reused while healthy, so a queued teardown runs before the next start (FR-050). Replaced only when a call on it timed out (`hostIsStuck`, R31). |

### `AudioSetupTimings` (value, returned by the host)

`engineCreateMs`, `setDeviceMs`, `readFormatsMs`, `installTapMs`, `prepareMs`, `startMs`, `firstBufferMs?` (Double), plus `nodeSampleRate`, `hwSampleRate`, `channels`, `recreatedForStaleNode: Bool`. Logged once per attempt ([contracts/diagnostic-events.md](./contracts/diagnostic-events.md)).

---

## 4. Hang diagnostics (US2)

### `HangContext` (in-memory, `OSAllocatedUnfairLock`-protected snapshot)

| Field | Type | Updated by |
|---|---|---|
| `stage` | `String` (`idle`, `overlayShown`, `starting.1`, `starting.2`, `recording`, `transcribing`, `formatting`, `postProcessing`, `settings`) | `RecordingViewModel` on every state change (main) |
| `deviceName` | `String?` | `AudioCaptureService` at the start of an attempt |
| `deviceID` | `String?` | same |
| `stageEnteredAt` | `Date` | same as `stage` |

The watchdog thread only reads it. Nothing in it is sensitive.

### `MainThreadWatchdog`

| Field | Notes |
|---|---|
| `tickInterval` | 0.5 s |
| `stallThreshold` | 2.0 s (FR-011) |
| `lastPong` | `ManagedAtomic<UInt64>` (uptime ns) |
| `openStall` | `{ startedAt, warned: Bool }?`. Only one WARN per stall; INFO on recovery. |

---

## 5. Session Selection (US4)

Existing in-memory fields on `RecordingViewModel` keep the same semantics:

| Field | Cycle key | Order source | Wrap |
|---|---|---|---|
| `audioDeviceManager.selectedDevice` | **1** | `audioDeviceManager.devices` (System Default, then alphabetical, the same as the menu) | yes |
| `selectedTextLanguage` | **2** | `SupportedLanguage.allCases` | yes |
| `selectedPrompt` | **3** | `promptsStore.prompts` (the same as the menu) | yes; a single prompt is a no-op; a deleted selection falls back to `promptsStore.defaultPrompt` |

- Bar order matches the keys: microphone, output language, prompt (R29). Each menu starts with a non-selectable title (`Input device`, `Output language`, `Using prompt`).
- The cycle keys and the menus are active when `windowPhase == .preProcessing`, `state ∈ {.idle, .recording, .error}`, and there are no modifiers. They are disabled in `.starting` (including a switch), `.transcribing` and `.formatting`.
- `selectedPrompt` resets to `promptsStore.defaultPrompt` on every `showOverlay()` and is never written back to Settings (FR-027). `changePrompt` mirrors into `chatSession?.systemPrompt`.

## 6. Model catalog and selection (US5–US8)


### LLMModel (`Verborra/Models/LLMModel.swift`)

`enum LLMModel: String, Codable, CaseIterable`. The case order is the display order (FR-030).

| Case | rawValue | displayName | contextLimit | supportsTemperature | reasoningEffort |
|---|---|---|---|---|---|
| `gpt52` | `gpt-5.2` | GPT-5.2 | 1_048_576 (unchanged) | true* | nil |
| `gpt54Mini` | `gpt-5.4-mini` | GPT-5.4 Mini | 1_048_576 | **false** (unchanged) | nil |
| `gpt54` | `gpt-5.4` | GPT-5.4 | 1_048_576 | true* | nil |
| `gpt55` | `gpt-5.5` | GPT-5.5 | 1_048_576 | true* | nil |
| `gpt56Terra` | `gpt-5.6-terra` | GPT-5.6 Terra | 922_000 | false | `none` |
| `gpt56Sol` | `gpt-5.6-sol` | GPT-5.6 Sol | 922_000 | false | `none` |
| `gpt6Luna` | `gpt-6-luna` | GPT-6 Luna | 922_000 | false | `none` |
| `gpt6Sol` | `gpt-6-sol` | GPT-6 Sol | 922_000 | false | `none` |
| `gpt61Sol` | `gpt-6.1-sol` | GPT-6.1 Sol | 922_000 | false | `low` |
| `gpt6Astra` | `gpt-6-astra` | GPT-6 Astra | 922_000 | false | `low` |

\* Today's value. Confirmed or flipped to `false` by the live probe in [quickstart.md](./quickstart.md) 5.2 (R21). The kept models' `reasoningEffort` starts as `nil` (today's request shape) and is set to `none` by the probe if a model returns `length`, an empty reply or is slow (R20).

- `static var default: LLMModel { .gpt6Luna }` (FR-036)
- `static let legacyDefaultRawValue = "gpt-5.1"`: used only by the migrator to log the old value of an inherited default.
- **Removed cases**: `gpt4oMini`, `gpt41Mini`, `gpt5Nano`, `gpt5Mini`, `gpt51`, `gpt54Nano` (deprecated), `gpt54Pro`, `gpt55Pro` (Chat Completions not supported, R27).
- `supportsTemperature` and `reasoningEffort` are exhaustive `switch`es with **one row per case** and no family grouping (FR-035). A new case won't compile until both are decided.
- `infoDescription` reads `model.llm.<case>.info`. Format: `<one-line purpose> — $<in>/$<out> per 1M tokens` (FR-034).
- `ReasoningEffort`: `enum String { none, low }`. Only the values in use are declared.

`TokenEstimator.contextLimit(for:)` takes its values from the `contextLimit` column above. The budget stays at 80% of the limit.

### STTModel (`Verborra/Models/STTModel.swift`)

| Case | rawValue | displayName | languageField |
|---|---|---|---|
| `gptTranscribe` | `gpt-transcribe` | GPT Transcribe | `.languagesArray` → `languages[]` |

- `static var default: STTModel { .gptTranscribe }` (FR-036)
- `static let legacyDefaultRawValue = "gpt-4o-mini-transcribe"`
- **Removed cases**: `gpt4oMiniTranscribe`, `gpt4oTranscribe`, `whisper1`.
- `LanguageField`: `enum { singular /* "language" */, languagesArray /* "languages[]" */ }`. Only `languagesArray` is used now; `singular` is kept so any future model's request shape is decided per model (R22).
- `infoDescription` reads `model.stt.<case>.info`. Format: `<purpose> — $<price> / min`.

### Model selection (persisted, `AppSettings`)

| Key | Type | Current values | Missing |
|---|---|---|---|
| `selectedSTTModelRawValue` | String | an `STTModel.rawValue` | fresh install → `STTModel.default` |
| `selectedLLMModelRawValue` | String | an `LLMModel.rawValue` | fresh install → `LLMModel.default` |

Rules:
- The getters stay as they are (`Model(rawValue:) ?? .default`) as a safety net.
- After the migrator runs, a saved value is always a current case or missing (fresh install only).

### ModelSelectionMigrator (new, `Verborra/Models/ModelSelectionMigrator.swift`)

A pure function of `UserDefaults` and a logger, so it can be tested with an in-memory suite. It runs once per launch from `AppDelegate.applicationDidFinishLaunching(_:)` in `Verborra/VerborraApp.swift`, right after the logging setup and before `AppController` is created, so no model setting has been read (`AppSettings` reads `@AppStorage` lazily, so creating it earlier is fine).

State transitions, for each of the two keys:

```text
saved = defaults.string(key)
saved ∈ current cases                     → no-op
saved ∉ current cases (removed/unknown)   → write default; log reason=removed
saved == nil && onboardingCompleted saved → write default; log old=legacyDefaultRawValue, reason=inheritedDefault
saved == nil && fresh install             → no-op
```

Idempotent: on a second run every branch is a no-op. Nothing is shown to the user (FR-038).

### RecordingError (`Verborra/Models/RecordingState.swift`)

New case: `modelUnavailable(modelName: String, kind: ModelKind)`, where `ModelKind` is `.speechToText` or `.text`. It maps to `error.modelUnavailable.text` or `error.modelUnavailable.stt` (R23). It's `Equatable`, like the other cases.

### Localization (`Verborra/Localizable.xcstrings`, en + ru)

- **Add**: `model.llm.{gpt56Terra,gpt56Sol,gpt6Luna,gpt6Sol,gpt61Sol,gpt6Astra}.info`, `model.stt.gptTranscribe.info`, `error.modelUnavailable.text`, `error.modelUnavailable.stt`.
- **Delete**: `model.llm.{gpt4oMini,gpt41Mini,gpt5Nano,gpt5Mini,gpt51,gpt54Nano,gpt54Pro,gpt55Pro}.info`, `model.stt.{gpt4oMiniTranscribe,gpt4oTranscribe,whisper1}.info` (FR-041).
- **Keep and check**: the prices in the descriptions of the four kept models.

## 7. Prompt name (US10)

| Rule | Value |
|---|---|
| `SystemPrompt.maxNameLength` | 30, counted as `String.count` (grapheme clusters) |
| Typing or pasting past 30 (previous value ≤ 30) | cut to the first 30 characters (`PromptNameRule.clamp(new:old:)`) |
| Stored name already > 30 (saved before this release) | kept as is; editor shows `n/30` in red and `settings.prompts.nameTooLong`; Save disabled until ≤ 30 |
| Floating window title | `PromptNameRule.display(_:)`: unchanged up to 30; above 30, first 29 characters + "…" |
| Selector button widths (FR-063, FR-064, R34) | microphone, language and prompt buttons each follow their title, no fixed cap; together they get the room left before the right-hand buttons minus the normal button gap; when the row is too narrow the microphone title truncates first, then the prompt, then the language; never overlaps |
| Built-in names (all languages), "New prompt" (en, ru) | ≤ 30, enforced by a unit test |

No migration: stored prompts are never rewritten automatically (FR-060).

