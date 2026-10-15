---

description: "Task list for 015 Reliability, Shortcuts & Model List Update"
---

# Tasks: Reliability, Shortcuts & Model List Update

<!--
Baseline (T001, 2026-10-14, Xcode 27.0 via DEVELOPER_DIR, branch 015-reliability-shortcuts-models off chore/speckit-1.2.0 @ fb5fa59):
- App target: BUILD SUCCEEDED, 2 warnings (OnboardingViewModel.swift:122, :130 — 'weak' capture differs from implicit strong capture).
- Test target: did not build at all — missing Info.plist (GENERATE_INFOPLIST_FILE absent). Fixed in T001 by adding GENERATE_INFOPLIST_FILE = YES to VerborraTests Debug/Release.
- After that fix: test target does NOT compile — 124 errors in 9 files:
  RecordingViewModelTests 58, SettingsViewModelTests 45, FormattingServiceTests 8, ChatSessionTests 4,
  TranscriptionServiceTests 3, LLMModelTests 3, TokenEstimatorTests 1, FlowTrackerTests 1, DiagnosticLoggerTests 1.
  Causes: main-actor isolation (~97, tests not marked @MainActor), removed model cases (~13), stale initializer arguments (5),
  non-exhaustive catch (4), misc (5). No test results are available at baseline. T017 is widened to fix all of these.
- SwiftLint baseline: see T003.
- T017/T020 outcome: test target compiles; clean `xcodebuild clean test` → 0 errors, 0 warnings, 173 XCTest + 95 Swift Testing tests pass.
  Besides compile fixes, stale tests were updated (async startRecording, PromptsStore data version 4, FormattingService no longer
  appends the language, log cleanup goes by creation date, URLProtocol body read from httpBodyStream). Real bugs found and fixed:
  (1) TranscriptionService and FormattingService retried 4xx/silence errors 3× despite "don't retry on 400" — RecordingErrors
  thrown inside the retry loop are now final; (2) PromptsStore on a fresh install had no default prompt (system prompts were added
  before the empty-list check). Also fixed: PromptsStoreTests deleted the real app's `promptsDataVersion` (now restored), and the
  2 OnboardingViewModel capture warnings.
- SwiftLint (T003/T094/T126, 2026-10-15): SwiftLint 0.65.1 via Homebrew. With Xcode 27 it must be run as
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer TOOLCHAIN_DIR=$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain swiftlint lint`
  (xcode-select points to the Command Line Tools, which lack sourcekitdInProc). Baseline: 144 violations repo-wide.
  The 65 Swift files changed by this feature: 91 → 0 (autofix, Data(…utf8), XCTUnwrap instead of force casts, StartTimeouts,
  split key handler / start closure / streaming error mapping, migrator Selection struct). `.swiftlint.yml` gained
  `cyclomatic_complexity.ignores_case_statements` and `large_tuple.warning: 3`. Two pre-existing functions
  (PromptsStore.migrateIfNeeded, RecordingViewModel.stopRecording) carry a reasoned `swiftlint:disable:next`.
  Repo-wide now 52, all in files this feature doesn't touch. Autofix broke one `let _ =` inside a view builder; restored.
- T099–T125 outcome (2026-10-15): clean `xcodebuild clean test` (Debug, ad-hoc signing from the project) → 0 compiler warnings, 252 XCTest + 117 Swift Testing tests pass (14 new for US9, 9 new for US10); Release build → BUILD SUCCEEDED, 0 warnings. T126 (SwiftLint) and T127 (manual checks) wait for the owner.
-->

**Input**: Design documents from `/specs/015-reliability-shortcuts-models/` (the model-list feature, former spec 016, is merged in as US5–US8)

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md), [investigation.md](./investigation.md)

**Tests**: Included. The constitution requires them (Principle 5: "Business logic MUST be covered by unit tests"), and plan.md lists the test files. Tests cover pure logic only. Audio hardware, login, signing, the global Fn hotkey and real OpenAI calls are verified manually through [quickstart.md](./quickstart.md).

**Organization**: Tasks are grouped by user story so each story can be implemented and tested on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1 = launch at login, US2 = no hangs (plus the stall test in Settings, Phase 15), US3 = shortcut recorder + Fn, US4 = floating-window selectors (amended in Phase 13), US5 = new text models, US6 = GPT Transcribe, US7 = move users off removed models, US8 = model prices, US9 = microphone switching and closing (Phase 12), US10 = prompt name limit (Phase 14)

## Project conventions (read before starting)

- App sources live in `Verborra/`, tests in `VerborraTests/`. The Xcode project uses **explicit file references**, so every new `.swift`/`.h`/`.m` file MUST be added to `Verborra.xcodeproj/project.pbxproj` (PBXFileReference + PBXBuildFile + group + Sources phase of the correct target), and every deleted file removed from it.
- Logging: `DiagnosticLogger.logger(for: <LogCategory>)`, then `.info/.debug/.error(…, parameters:, errorCode:)` (and `.warn` after T006). Never log keystrokes, transcripts or API keys.
- UI strings go in `Verborra/Localizable.xcstrings` with `en` and `ru` values, accessed via `LocalizationManager.shared.string("key")`.
- Build and test: `xcodebuild test -project Verborra.xcodeproj -scheme Verborra -destination 'platform=macOS'`. Zero warnings is required.

---
- Model work (US5–US8): model IDs, prices and per-model request options come from [research.md](./research.md) Area E and [data-model.md](./data-model.md) §6. Never add a hidden fallback model (FR-040).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Bring the project configuration in line with the plan before any code changes.

- [X] T001 Create and switch to branch `015-reliability-shortcuts-models` from `main` (the specs and the constitution 2.0.2 change come along as uncommitted files). Then run `xcodebuild test -project Verborra.xcodeproj -scheme Verborra -destination 'platform=macOS'` on the current tree and record the baseline (passing/failing tests, warning count) in a comment at the top of `specs/015-reliability-shortcuts-models/tasks.md` under "Baseline", so regressions can be told apart from pre-existing failures. Expect the test target **not to compile** at baseline: `LLMModelTests` and other tests refer to model cases that no longer exist (research R26); T011–T020 fix this.
- [X] T002 [P] Sync `project.yml` with the real Xcode project: add package `swift-atomics` (`url: https://github.com/apple/swift-atomics.git`, `from: "1.3.0"`) and the target dependency `package: swift-atomics, product: Atomics`. Add `SWIFT_OBJC_BRIDGING_HEADER: Verborra/Verborra-Bridging-Header.h` to the `Verborra` target settings. Keep `CODE_SIGN_STYLE: Automatic`, `DEVELOPMENT_TEAM: G292C8CN3X`, `CODE_SIGN_IDENTITY: "Apple Development"` as they are, and add `ENABLE_HARDENED_RUNTIME: YES` (constitution v2.0.1, Principle 4).
- [X] T003 [P] Set up SwiftLint as a **development-only** tool (constitution v2.0.1, Principle 5). It MUST NOT be added as an SPM package, build-phase script, build plugin or bundled resource. Prerequisite on the developer machine: `brew install swiftlint`. If Homebrew isn't writable, the owner fixes it with `sudo chown -R $(whoami) /opt/homebrew`. Create a repo-root `.swiftlint.yml` with `included: [Verborra, VerborraTests]`, `excluded: [builds, Verborra.xcodeproj, .build]`, `disabled_rules: [line_length, file_length, type_body_length, function_body_length, identifier_name, todo]` (the existing code has long files and Russian comments), and `opt_in_rules: []`. Then run `swiftlint lint Verborra VerborraTests` once and record the pre-existing violation count in the "Baseline" note from T001 (pre-existing violations in files this feature doesn't touch aren't in scope).

---

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared building blocks used by more than one story: WARN log severity (US2, US3), the `GlobalShortcut` model and formatter (US3 recorder, US4 Start/Stop hint), and the new model catalog (US5–US8; it also makes the test target compile again, which every story's tests need).

**⚠️ CRITICAL**: Finish this phase before starting any user story phase.

### Part A — Logging and shortcut model

- [X] T004 [P] Add three cases to `LogCategory` in `Verborra/Models/LogCategory.swift`, each with a trailing comment naming its owners as the existing cases do: `hotkey` (GlobalHotkeyService, FnEventTap, ShortcutRecorderField), `loginItem` (LoginItemService), `watchdog` (MainThreadWatchdog). Also update the `userAction` comment to `RecordingViewModel, GlobalHotkeyService (hotkey fired)`. This follows constitution Principle 6: one `os.Logger` category per module or service.
- [X] T005 [P] Extend `Verborra/Models/LogEntry.swift` so an entry can carry the severity label `"WARN"`. Add an initializer that takes a `severityLabel: String` (used only for WARN), and keep the existing `init(level: LogLevel, …)` unchanged. Do NOT add a case to `LogLevel` in `Verborra/Models/LogLevel.swift` (the user-selectable modes stay OFF/ERROR/INFO/DEBUG, research R12).
- [X] T006 Make level filtering thread-safe and add `warn` in `Verborra/Services/Logging/DiagnosticLogger.swift` (depends on T005):
  - Today `shouldLog` calls `logLevelProvider()` (reads `AppSettings`) and `isRecordingActiveProvider()` (reads `RecordingViewModel.state`, main-actor state). Both are unsafe from the watchdog, event-tap and audio threads. Add `static let filterSnapshot = OSAllocatedUnfairLock(initialState: LogFilterSnapshot(level: .info, isRecordingActive: false))` and make `shouldLog` read **only** the snapshot.
  - Update the snapshot on the main thread: in `VerborraApp.applicationDidFinishLaunching` right after the provider is set (`DiagnosticLogger.updateFilterSnapshot(level:)`), in the `AppSettings.logLevel` setter, and in the `RecordingViewModel.state` `didSet` (`updateFilterSnapshot(isRecordingActive:)`; T058 adds the same `didSet`). Keep the provider closures for existing callers, but `shouldLog` no longer calls them.
  - `error(...)` reads `appStateProvider` only when `Thread.isMainThread`; off the main thread it omits the app state.
  - Add `func warn(_ message: String, metadata: [String: String]? = nil)`. It is written exactly when `shouldLog(level: .error)` is true, emits `osLogger.error(...)` (os_log has no warn), writes a `LogEntry` with label `"WARN"` and the metadata, and MUST NOT call `Self.appStateProvider`. It must be safe to call from any thread.
- [X] T007 [P] Add tests in `VerborraTests/Logging/DiagnosticLoggerTests.swift`:
  - WARN is written in ERROR/INFO/DEBUG modes, not in OFF mode, and JSONL `level == "WARN"`
  - `appStateProvider` is never invoked by `warn` (use a spy provider that records calls)
  - `warn` and `error` called from a background `DispatchQueue` invoke neither `logLevelProvider`, `isRecordingActiveProvider` nor `appStateProvider` (spies), and filter by the snapshot
  - deferred OFF still applies: snapshot `level: .off, isRecordingActive: true` writes ERROR only (existing T079 behaviour of spec 007)
- [X] T008 [P] Create `Verborra/Models/GlobalShortcut.swift` with:
  - `struct ShortcutModifiers: OptionSet, Codable, Hashable` (`UInt8`): `fn = 1<<0`, `control = 1<<1`, `option = 1<<2`, `shift = 1<<3`, `command = 1<<4`. Include conversions to and from Carbon modifier flags (`cmdKey`/`shiftKey`/`optionKey`/`controlKey`; `fn` has no Carbon bit and is dropped), to `NSEvent.ModifierFlags`, and from `CGEventFlags` *excluding* `.maskSecondaryFn`.
  - `struct GlobalShortcut: Codable, Equatable` with `keyCode: UInt16` and `modifiers: ShortcutModifiers`. `static let default = GlobalShortcut(keyCode: 49, modifiers: [.option])` (⌥Space). `var requiresEventTap: Bool { modifiers.contains(.fn) }`. Rule: "keyCode must not be a modifier key code (54–63, 179)" and "modifiers must not be empty".
  - `enum ShortcutFormatter` with `static func symbols(_ m: ShortcutModifiers) -> [String]` in order `🌐︎` (U+1F310 U+FE0E), `⌃`, `⌥`, `⇧`, `⌘`, `static func keyName(_ keyCode: UInt16) -> String` (letters/digits upper case; `Space`, `Return`, `Tab`, `Delete`, `⌦`, `←`, `→`, `↑`, `↓`, `F1…F20`, `Home`, `End`, `PgUp`, `PgDn`; otherwise the current layout character via `UCKeyTranslate`, reusing the approach in `AppSettings.recordingKeyDisplayName`), and `static func string(_ s: GlobalShortcut) -> String` joining everything with single spaces, e.g. `"🌐︎ ⌥ Space"`, `"⌘ ⇧ R"`.
- [X] T009 Add `@MainActor @Observable final class GlobalShortcutStore` to `Verborra/Models/GlobalShortcut.swift`, with `static let shared`, `private(set) var current: GlobalShortcut`, and `func save(_:)`. Persist it as JSON in UserDefaults key `globalShortcut.v1`. On first load, if the key is absent, migrate from UserDefaults key `KeyboardShortcuts_toggleOverlay` (JSON `{"carbonKeyCode":Int,"carbonModifiers":Int}`) through the Carbon→`ShortcutModifiers` conversion. Fall back to `GlobalShortcut.default` if it's missing or unreadable, save it, and log INFO `Global shortcut migrated` (category `.hotkey`, from T004, metadata `from`, `to`) (depends on T008).
- [X] T010 [P] Add `VerborraTests/Models/GlobalShortcutTests.swift` covering JSON round-trip; migration from `{"carbonKeyCode":49,"carbonModifiers":2048}` → `⌥ Space`; migration fallback to the default on garbage data; formatter output `"🌐︎ ⌃ ⌥ ⇧ ⌘ K"` order; `"⌥ Space"`; `"🌐︎ F5"`; and that the Carbon conversion drops `fn` (depends on T008, T009; use an isolated `UserDefaults(suiteName:)` by injecting defaults into the store's initializer).

### Part B — Model catalog (US5–US8)

**⚠️ CRITICAL**: The app won't build between T011 and T017; do them as one unit and one commit.

- [X] T011 [P] Rewrite `Verborra/Models/LLMModel.swift`: exactly these 10 cases in this order (case order = display order, FR-030): `gpt52="gpt-5.2"`, `gpt54Mini="gpt-5.4-mini"`, `gpt54="gpt-5.4"`, `gpt55="gpt-5.5"`, `gpt56Terra="gpt-5.6-terra"`, `gpt56Sol="gpt-5.6-sol"`, `gpt6Luna="gpt-6-luna"`, `gpt6Sol="gpt-6-sol"`, `gpt61Sol="gpt-6.1-sol"`, `gpt6Astra="gpt-6-astra"`. Display names: "GPT-5.2", "GPT-5.4 Mini", "GPT-5.4", "GPT-5.5", "GPT-5.6 Terra", "GPT-5.6 Sol", "GPT-6 Luna", "GPT-6 Sol", "GPT-6.1 Sol", "GPT-6 Astra". Remove `gpt4oMini`, `gpt41Mini`, `gpt5Nano`, `gpt5Mini`, `gpt51`, `gpt54Nano` (deprecated) and `gpt54Pro`, `gpt55Pro` (no Chat Completions support, research R27). Set `static var default: LLMModel { .gpt6Luna }`; add `static let legacyDefaultRawValue = "gpt-5.1"`. Make `infoDescription` read `model.llm.<caseName>.info`. Covers FR-030, FR-032, FR-036, FR-042.
- [X] T012 In `Verborra/Models/LLMModel.swift`, replace the family-based `supportsTemperature` with an exhaustive one-row-per-case `switch`: `true` for `gpt52`, `gpt54`, `gpt55`; `false` for `gpt54Mini` and all six new cases (FR-035, R21). Add `enum ReasoningEffort: String { case none, low }` and `var reasoningEffort: ReasoningEffort?` as an exhaustive one-row-per-case `switch`: `nil` for the four kept models (the T096 probe may change this, R20), `.none` for `gpt56Terra`, `gpt56Sol`, `gpt6Luna`, `gpt6Sol`, `.low` for `gpt61Sol`, `gpt6Astra` (R20). Update the doc comment to say values are per exact model and confirmed by quickstart 5.2.
- [X] T013 [P] Rewrite `Verborra/Models/STTModel.swift`: single case `gptTranscribe = "gpt-transcribe"`, display name "GPT Transcribe", `infoDescription` from `model.stt.gptTranscribe.info`, `static var default: STTModel { .gptTranscribe }`, `static let legacyDefaultRawValue = "gpt-4o-mini-transcribe"`. Add `enum LanguageField { case singular, languagesArray }` and `var languageField: LanguageField` (`.languagesArray` for `gptTranscribe`). Remove `gpt4oMiniTranscribe`, `gpt4oTranscribe`, `whisper1`. Covers FR-031, FR-032, FR-036.
- [X] T014 Update `TokenEstimator.contextLimit(for:)` in `Verborra/Models/TokenEstimator.swift`: `1_048_576` for the four kept models (unchanged), `922_000` for the six new models (max input, R18); exhaustive switch, no `default:`
- [X] T015 [P] Update `Verborra/Localizable.xcstrings` (en + ru, state `translated`): delete `model.llm.{gpt4oMini,gpt41Mini,gpt5Nano,gpt5Mini,gpt51,gpt54Nano,gpt54Pro,gpt55Pro}.info` and `model.stt.{gpt4oMiniTranscribe,gpt4oTranscribe,whisper1}.info`; add the keys below using the format `<purpose> — $<in>/$<out> per 1M tokens` / `… за 1M токенов`:. Covers FR-034, FR-041.
  - `model.llm.gpt56Terra.info` → "Balanced 5.6 model — $2.00/$12.00 per 1M tokens"
  - `model.llm.gpt56Sol.info` → "High-quality 5.6 model — $4.00/$20.00 per 1M tokens"
  - `model.llm.gpt6Luna.info` → "Fastest and most affordable, great for everyday cleanup — $0.10/$0.50 per 1M tokens"
  - `model.llm.gpt6Sol.info` → "Balanced GPT-6 model — $2.00/$10.00 per 1M tokens"
  - `model.llm.gpt61Sol.info` → "Recommended for advanced formatting — $2.00/$10.00 per 1M tokens"
  - `model.llm.gpt6Astra.info` → "Premium: complex reasoning and restructuring — $10.00/$50.00 per 1M tokens"
  - `model.stt.gptTranscribe.info` → "Accurate transcription of recorded audio — $0.0045 / min"
  
  Write Russian translations in the same style as the existing ru entries.
- [X] T016 Replace removed-case references so the app builds: `FormattingService.process(...)` and `TranscriptionService.transcribe(audioData:language:)` already use `.default` (no change). Grep `Verborra/` for `gpt4oMini|gpt41Mini|gpt41Nano|gpt5Nano|gpt5Mini|gpt51|gpt54Nano|gpt54Pro|gpt55Pro|gpt4oMiniTranscribe|gpt4oTranscribe|whisper1` and fix every hit
- [X] T017 Fix test references to removed/nonexistent cases so the test target compiles: `VerborraTests/Services/FormattingServiceTests.swift` (`.gpt41Nano`/`.gpt4oMini` → `.gpt52`, which keeps temperature 0.2; line 99 expectation `"gpt-4.1-nano"` → `"gpt-5.2"`), `VerborraTests/Services/StreamingFormattingServiceTests.swift:74` and `VerborraTests/ViewModels/DictationFlowTests.swift:254` (`.gpt41Nano` → `.gpt52`), `VerborraTests/Services/TranscriptionServiceTests.swift:63,104` (→ `.gptTranscribe`), `VerborraTests/ViewModels/SettingsViewModelTests.swift:98-99` (defaults → `.gptTranscribe` / `.gpt6Luna`), `VerborraTests/Models/TokenEstimatorTests.swift` (`.gpt4oMini` 128_000 → `.gpt6Luna` 922_000; `.gpt41Nano` → `.gpt52` 1_048_576; recompute the two budget assertions). **Widened after baseline (T001)**: also fix every other pre-existing compile error in the test target — mark test types that touch `@MainActor` types as `@MainActor`, update stale initializer calls (`vocabularyStore:`, `audioDeviceManager:`, `isFirstVoiceTurn:`, `answerQuestionsInFirstMessage:`), make non-exhaustive `catch` blocks exhaustive. Change test code only; don't change app behaviour to suit old tests
- [X] T018 [P] Rewrite `VerborraTests/LLMModelTests.swift` (Swift Testing): `allCases` equals the 10 cases in the T011 order; raw values and display names per T011; `default == .gpt6Luna`; every case round-trips via `init(rawValue:)`; removed IDs (`gpt-4o-mini`, `gpt-4.1-mini`, `gpt-5-nano`, `gpt-5-mini`, `gpt-5.1`, `gpt-5.4-nano`, `gpt-5.4-pro`, `gpt-5.5-pro`) decode to `nil`; `supportsTemperature` and `reasoningEffort` match the T012 table row by row. The round-trip check also covers FR-039 (saved selections decode back to the same model).
- [X] T019 [P] Create `VerborraTests/STTModelTests.swift` and register it in `Verborra.xcodeproj/project.pbxproj` (test target; explicit file references). Swift Testing: `allCases == [.gptTranscribe]`, raw value `gpt-transcribe`, `default == .gptTranscribe`, `languageField == .languagesArray`, removed IDs (`gpt-4o-mini-transcribe`, `gpt-4o-transcribe`, `whisper-1`) decode to `nil`
- [X] T020 Build and run all tests: `xcodebuild test -project Verborra.xcodeproj -scheme Verborra -destination 'platform=macOS'`. Expected: no warnings and every test passes (the request-shape tests are added later, in US5, US6 and Phase 11)

**Checkpoint**: The foundation is ready: WARN logging, the shortcut model, and the new model catalog; the project and test target compile. The user story phases can proceed in any order or in parallel.

---

## Phase 3: User Story 5 — Choose a new text model (Priority: P1)

**Goal**: The six new text models format, stream and handle follow-ups without request errors.

**Independent Test**: Select each new text model, dictate with a formatting prompt and send a follow-up → no error; the DEBUG log shows `reasoningEffort` and `temperature` per [openai-requests.md](./contracts/openai-requests.md).

### Tests for User Story 5

- [X] T021 [P] [US5] In `VerborraTests/Services/FormattingServiceTests.swift`, add request-shape tests with `MockURLProtocol`: `.gpt6Luna` → body has `"reasoning_effort": "none"` and no `temperature`; `.gpt61Sol` and `.gpt6Astra` → `"reasoning_effort": "low"`, no `temperature`; `.gpt52` → `temperature == 0.2` and no `reasoning_effort` key; `max_completion_tokens == 4000` for all
- [X] T022 [P] [US5] In `VerborraTests/Services/StreamingFormattingServiceTests.swift`, add the same four assertions for the streaming request body, plus `stream == true`

### Implementation for User Story 5

- [X] T023 [P] [US5] In `Verborra/Services/FormattingService.swift` `format(...)`: after the temperature block, add `if let effort = model.reasoningEffort { requestBody["reasoning_effort"] = effort.rawValue }`; add `"reasoningEffort": model.reasoningEffort?.rawValue ?? "omitted"` to the DEBUG `Chat Completions request body` metadata; replace the "GPT-5 reasoning models reject custom temperature" comment with one pointing to the per-model table in `LLMModel` Covers FR-033, FR-035.
- [X] T024 [P] [US5] In `Verborra/Services/StreamingFormattingService.swift` `buildRequest(messages:model:)`: same `reasoning_effort` addition; add `reasoningEffort` to the DEBUG request log next to `temperature` (around line 98); update the comment above `requestBody` the same way. The request shape must match T023 exactly, apart from `stream` Covers FR-033, FR-035.
- [X] T025 [US5] Run the T021/T022 tests and the full suite; they must pass

**Checkpoint**: US5 is done. The new text models are selectable (from Phase 2 Part B) and send valid requests.

---

## Phase 4: User Story 6 — Transcribe with GPT Transcribe (Priority: P1)

**Goal**: Transcription uses `gpt-transcribe` with the chosen recognition language sent as `languages[]`.

**Independent Test**: Dictate in English and Russian → correct text; the DEBUG log shows the transcription request with `languages[]` and without `language`.

### Tests for User Story 6

- [X] T026 [P] [US6] In `VerborraTests/Services/TranscriptionServiceTests.swift`, add: with `language: .ru` the multipart body contains `name="languages[]"` followed by `ru`, and does **not** contain `name="language"`; with `language: nil` the body has neither field; the body has `model` = `gpt-transcribe` and `response_format` = `json`; a response `{"text":"привет","languages":[{"code":"ru"}]}` parses to `"привет"`

### Implementation for User Story 6

- [X] T027 [US6] In `Verborra/Services/TranscriptionService.swift` `transcribe(audioData:language:model:)`: replace the unconditional `language` field with a `switch model.languageField` — `.singular` → `name: "language"`, `.languagesArray` → `name: "languages[]"`, value `language.apiCode`, only when `language != nil`. Add `"languageField": "language"|"languages[]"` to the DEBUG `Whisper API request details` metadata. Rename the log messages `Whisper API request` / `Whisper API response` / `Whisper API request details` / `Whisper API response body` to `Transcription API …` (whisper-1 is gone) Covers FR-033.
- [X] T028 [US6] Run the T026 tests and the full suite; they must pass

**Checkpoint**: US5 and US6 are done; dictation works end to end on a fresh install.

---

## Phase 5: User Story 7 — Move users off removed models (Priority: P1)

**Goal**: Existing users on removed models (saved or inherited old default) silently move to the new defaults, with a log entry; users on kept models aren't touched.

**Independent Test**: quickstart 5.3 and 5.4.

### Tests for User Story 7

- [X] T029 [P] [US7] Create `VerborraTests/Models/ModelSelectionMigratorTests.swift` (XCTest, `UserDefaults(suiteName:)` removed in `tearDown`) covering every row of the data-model transition table for both keys `selectedSTTModelRawValue` and `selectedLLMModelRawValue`:
  - saved current value (`gpt-5.4`, `gpt-transcribe`) → unchanged, returns no migrations
  - saved removed value (`gpt-5.1`, `gpt-5-mini`, `gpt-5.5-pro`, `whisper-1`) → rewritten to `gpt-6-luna` / `gpt-transcribe`, one migration each with `reason == .removed` and the old value
  - unknown value (`foo`) → same as removed
  - no value + `onboardingCompleted` saved → both written to the new defaults, `reason == .inheritedDefault`, `old` = `gpt-4o-mini-transcribe` / `gpt-5.1`
  - no keys at all (fresh install) → nothing written, no migrations
  - running twice → second run returns no migrations and doesn't change state (G3)

### Implementation for User Story 7

- [X] T030 [US7] Create `Verborra/Models/ModelSelectionMigrator.swift`: `enum ModelSelectionMigrator` with `struct Migration: Equatable { kind: Kind (.stt/.llm), old: String, new: String, reason: Reason (.removed/.inheritedDefault) }` and `@discardableResult static func run(defaults: UserDefaults = .standard, log: DiagnosticLogger? = DiagnosticLogger.logger(for: .lifecycle)) -> [Migration]`. Implement the transition table from [data-model.md](./data-model.md#modelselectionmigrator-new-verborramodelsmodelselectionmigratorswift) using the keys `selectedSTTModelRawValue`, `selectedLLMModelRawValue`, `onboardingCompleted` (`defaults.object(forKey:) != nil` means "saved"). For each migration, log `log.info("Model selection migrated", metadata: ["kind": "stt"|"llm", "old": old, "new": new, "reason": "removed"|"inheritedDefault"])`. No UI (FR-038). Register `ModelSelectionMigrator.swift` (app sources) and `ModelSelectionMigratorTests.swift` (test target) in `Verborra.xcodeproj/project.pbxproj` (explicit file references) Covers FR-037, FR-038.
- [X] T031 [US7] Wire it in `Verborra/VerborraApp.swift`: in `AppDelegate.applicationDidFinishLaunching(_:)`, call `ModelSelectionMigrator.run()` right after the logging setup (after the `Application launched` log line, so the migration events reach the log file) and before `AppController(...)` is created, so nothing has read `appSettings.selectedSTTModel`/`selectedLLMModel` yet. Grep that no model setting is read in `AppDelegate.init`, `VerborraApp.init` or a property initializer. T006, T037, T059 and T074 also edit this method; keep the call in that position
- [X] T032 [US7] Run the T029 tests and the full suite; they must pass

**Checkpoint**: Upgrading users are migrated (quickstart 5.4).

---

## Phase 6: User Story 1 — App starts automatically at login (Priority: P1)

**Goal**: The "Launch at login" control always shows the real system state, existing users get registered automatically, fresh users are asked once in onboarding, and registration survives app updates (FR-001…FR-006).

**Independent Test**: [quickstart.md §0 and §1](./quickstart.md#1-launch-at-login-us1). Build signed, install to /Applications, log out and in → Verborra runs. Disable it in System Settings › Login Items → the Settings toggle shows off plus "needs approval" plus **Open Login Items**.

### Tests for User Story 1

- [X] T033 [P] [US1] Create `VerborraTests/Services/LoginItemServiceTests.swift` covering every row of the reconcile table in [contracts/login-item.md](./contracts/login-item.md#startup-reconcile). Use a fake `SMAppService` wrapper (status settable, register/unregister can throw):
  - onboarding not completed → no call
  - intent nil + `.notRegistered` → `register()` called
  - intent on + `.enabled` → no call
  - intent on + `.requiresApproval` → no call
  - intent off + `.enabled` → intent becomes true, no call
  - `setEnabled(true)` failure → `lastError` set, displayed state == real status
  - `isRunningFromApplications` is true for `/Applications/Verborra.app` and `~/Applications/Verborra.app`, false for `~/Downloads/Verborra.app` and a DerivedData path

### Implementation for User Story 1

- [X] T034 [US1] **(Amended 2026-10-15: owner has no Apple certificate → signing stays ad-hoc (`CODE_SIGN_IDENTITY = "-"`, `Manual`, no team) with `ENABLE_HARDENED_RUNTIME = YES`, also in `project.yml`. Verified without overrides: Release BUILD SUCCEEDED, `codesign -dv` → `flags=0x10002(adhoc,runtime)`, `codesign --verify --deep --strict` OK; Debug tests pass. Original text below kept for history.)** Fix code signing in `Verborra.xcodeproj/project.pbxproj` for **both** Debug and Release build configurations of the `Verborra` app target (the blocks that currently contain `CODE_SIGN_IDENTITY = "-"`, `CODE_SIGN_STYLE = Manual`, `DEVELOPMENT_TEAM = ""`). Set `CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY = "Apple Development"`, `DEVELOPMENT_TEAM = G292C8CN3X`, `ENABLE_HARDENED_RUNTIME = YES`. Leave `Verborra/Verborra.entitlements` unchanged: `com.apple.security.device.audio-input` is already the Hardened Runtime microphone entitlement, and no other runtime exception is needed. Verify with `xcodebuild build -configuration Release` plus `codesign -dv <built app>` → `TeamIdentifier=G292C8CN3X`, `flags=0x10000(runtime)`, no `Signature=adhoc` (FR-006, constitution P4).
- [X] T035 [US1] In `Verborra/Models/AppSettings.swift`, change `launchAtLogin` into the user's **intent**. Expose `var launchAtLoginIntent: Bool?` backed by UserDefaults key `launchAtLogin` (`nil` when the key is absent = "never chosen", treated as `true` by callers) with a setter that writes a Bool. Remove the `@AppStorage("launchAtLogin") var launchAtLogin: Bool = true` default-true property and update all call sites.
- [X] T036 [US1] Create `Verborra/Services/LoginItemService.swift`. It has:
  - `enum LoginItemStatus { case enabled, notRegistered, requiresApproval, notFound }` (mapped from `SMAppService.Status`)
  - a small `protocol LoginItemBackend { var status: SMAppService.Status { get }; func register() throws; func unregister() throws; static func openSystemSettingsLoginItems() }` with a production conformer wrapping `SMAppService.mainApp`
  - `@MainActor protocol LoginItemServiceProtocol` exactly as in [contracts/login-item.md](./contracts/login-item.md#service-interface)
  - `@MainActor @Observable final class LoginItemService` that implements it: `refresh()`, `setEnabled(_:)` (write intent → register/unregister → refresh; on failure set `lastError` and log ERROR `Launch at login change failed` with `enabled`, `status`, `error`; on success log INFO `Launch at login changed` with `old`, `new`, `statusBefore`, `statusAfter`), `reconcileAtLaunch(onboardingCompleted:)` per the contract table with the listed log lines, and `openSystemSettings()`. All logging uses category `.loginItem`.
  - `var isRunningFromApplications: Bool`, computed once from `Bundle.main.bundleURL`: true when the path starts with `/Applications/` or `<home>/Applications/` (injectable `bundleURL` for tests). `reconcileAtLaunch` always writes INFO `Login item reconcile` with `appPath`, `status`, `intent`, `action` (spec edge case "multiple copies").
- [X] T037 [US1] Wire it into `Verborra/VerborraApp.swift`: create `let loginItemService = LoginItemService(settings: appSettings)` in `AppDelegate`, call `loginItemService.reconcileAtLaunch(onboardingCompleted: appSettings.isOnboardingCompleted)` in `applicationDidFinishLaunching` after logging starts, call `loginItemService.refresh()` in `applicationDidBecomeActive`, and inject it into the `Settings` scene environment and into `OnboardingViewModel` (depends on T036).
- [X] T038 [US1] Update `Verborra/ViewModels/SettingsViewModel.swift`: replace `updateLaunchAtLogin(_:)` and `launchAtLoginError` with pass-throughs to the injected `LoginItemServiceProtocol` (`loginItemStatus`, `loginItemError`, `setLaunchAtLogin(_:)`, `openLoginItemsSettings()`). Remove the direct `SMAppService` usage (depends on T036).
- [X] T039 [US1] Update the System section in `Verborra/Views/SettingsView.swift` (currently lines ~146-157). Bind the toggle `get` to `status == .enabled` and `set` to `setLaunchAtLogin`. For `.requiresApproval` show the caption key `settings.general.launchAtLogin.needsApproval` plus a button `settings.general.launchAtLogin.openLoginItems` that calls `openLoginItemsSettings()`. For `.notFound` show the caption `settings.general.launchAtLogin.notFound` plus the same button. Show `loginItemError` in red. When `isRunningFromApplications == false`, show the caption `settings.general.launchAtLogin.notInApplications` with the app's parent folder path. Call `refresh()` in `.onAppear` (FR-001, FR-003, FR-004) (depends on T038; pass `isRunningFromApplications` through `SettingsViewModel`).
- [X] T040 [US1] Onboarding ask-once: in `Verborra/ViewModels/OnboardingViewModel.swift` add `var launchAtLoginChoice: Bool = true` and `var launchAtLoginError: String?`. In `completeOnboarding()`, call `loginItemService.setEnabled(launchAtLoginChoice)` **before** setting `appSettings.isOnboardingCompleted = true`. Copy any `lastError` into `launchAtLoginError`, and still complete onboarding. Add the service to the initializer (default parameter for tests) (FR-005) (depends on T036).
- [X] T041 [US1] In `Verborra/Views/Onboarding/CompletionStep.swift`, add a `Toggle` labelled `onboarding.completion.launchAtLogin` ("Start Verborra at login") bound to `viewModel.launchAtLoginChoice` (on by default), plus a red caption for `launchAtLoginError` (depends on T040).
- [X] T042 [P] [US1] Add `Verborra/Localizable.xcstrings` entries (en + ru) for: `settings.general.launchAtLogin.needsApproval` ("Verborra needs your approval in System Settings › Login Items."), `settings.general.launchAtLogin.notFound` ("macOS can't find this copy of Verborra as a login item. Move it to Applications and try again."), `settings.general.launchAtLogin.openLoginItems` ("Open Login Items"), `settings.general.launchAtLogin.notInApplications` ("Verborra is running from %@. Move it to Applications so the right copy starts at login."), `onboarding.completion.launchAtLogin` ("Start Verborra at login").
- [X] T043 [US1] Add the new and removed files to `Verborra.xcodeproj/project.pbxproj` (`LoginItemService.swift` in app sources, `LoginItemServiceTests.swift` in test sources) and run the full test suite (depends on T033–T042).

**Checkpoint**: US1 is complete. Run quickstart §0 and §1.1–1.5.

---

## Phase 7: User Story 2 — App never freezes during recording (Priority: P1)

**Goal**: Recording start succeeds or shows a retryable error within 5 s without ever blocking the main thread. One automatic same-device retry, cancel by hotkey or Esc, and full diagnostics: step timings, ERROR on failures, WARN on stalls over 2 s, uncaught-exception logging in all builds and crash-on-exception in DEBUG builds (FR-007…FR-013a).

**Independent Test**: [quickstart.md §2](./quickstart.md#2-no-hangs-at-recording-start-us2). Switch the mic between 44.1 and 48 kHz and start a recording; unplug a USB mic during start; press the hotkey twice quickly. Each time: no freeze, an error or recording within 5 s, the menu bar responds, and an ERROR/WARN entry is in the logs.

### Interface changes for User Story 2 (first: the tests compile against these)

- [X] T044 [US2] Extend `Verborra/Models/RecordingState.swift`:
  - add `case starting(attempt: Int)` to `RecordingState`
  - add `enum StartFailureReason: Equatable { case timeout(step: String), formatMismatch(node: Double, hardware: Double), audioException(name: String, reason: String), engineStartFailed(String), deviceUnavailable }` with `var shortDescription: String`
  - add `case recordingStartFailed(StartFailureReason)` to `RecordingError` with localized `errorDescription` key `error.recordingStartFailed` ("Couldn't start the microphone (%@). Press Retry or close the window.")
  - update the exhaustive switches that break (`RecordingViewModel.currentAppState()`, `ControlBarView`, `RecordingView`)
- [X] T045 [US2] Change `AudioCaptureServiceProtocol` in `Verborra/Services/AudioCaptureService.swift`:
  - replace `startRecording(deviceID:maxDuration:awaitBluetoothSwitch:)` with `startRecording(deviceID: String?, maxDuration: MaxRecordingDuration, awaitBluetoothSwitch: Bool, attempt: Int, setupTimeout: Duration, firstBufferTimeout: Duration) async throws` (one attempt only; the view model owns retries)
  - add `func cancelStart()` (non-blocking)
  - remove `onDeviceFallback`
  - keep the protocol `@MainActor`
  - update the extension convenience overload (defaults: `attempt: 1`, `setupTimeout: .milliseconds(1800)`, `firstBufferTimeout: .milliseconds(600)`)

### Tests for User Story 2

- [X] T046 [P] [US2] Extend `VerborraTests/Mocks/MockAudioCaptureService.swift` to the new protocol shape (depends on T044, T045). It needs a scripted result queue per call (`.success`, `.failure(AudioSetupError)`, `.hang` that only returns on cancellation), a configurable delay, a record of every `deviceID` it was called with, and a counter for `cancelStart()` calls. Remove `onDeviceFallback`.
- [X] T047 [US2] Create `VerborraTests/ViewModels/RecordingStartTests.swift` for `RecordingViewModel`, using the mock from T046 and injected short budgets (depends on T046, T044):
  - (a) first attempt fails, second succeeds → states `.starting(1)` → `.starting(2)` → `.recording`
  - (b) both fail → `.error(.recordingStartFailed)`, and `retryFromError()` → `.starting(1)`
  - (c) both attempts use the **same** `deviceID` and `selectedAudioDeviceID` never changes (FR-013)
  - (d) `.hang` → error within the overall deadline
  - (e) hotkey (`toggleOverlay()` while visible) during `.starting` → `.idle` synchronously and `cancelStart()` called (FR-013a)
  - (f) Esc via `dismissOverlay()` during `.starting` → cancelled
  - (g) a late success after cancellation doesn't change state
  - (h) both attempts use their full setup and first-buffer timeouts → `.error` is reached within the overall 5 s budget (with injected short budgets: within `overallStartBudget` plus a small tolerance), never budget + 0.4 s
- [X] T048 [P] [US2] Create `VerborraTests/Logging/MainThreadWatchdogTests.swift`. Test the pure stall detector (T057) with an injected clock: no WARN when pongs arrive every 0.5 s; exactly one WARN after 2.0 s without a pong, with metadata `stage`, `stageAgeMs`, `deviceName`, `deviceID`, `stallMs`; one INFO `Main thread recovered` when the pong resumes; a new stall afterwards produces a new WARN.

### Implementation for User Story 2

- [X] T049 [P] [US2] Create the Objective-C exception shim. Create `Verborra/Support/ObjCExceptionCatcher.h` declaring `NSError * _Nullable VBRTryCatch(NS_NOESCAPE void (^ _Nonnull block)(void));`. Create `Verborra/Support/ObjCExceptionCatcher.m`, which runs the block in `@try`, and on `@catch (NSException *e)` returns an `NSError` with domain `"VBRObjCException"`, `userInfo[@"name"] = e.name`, `userInfo[@"reason"] = e.reason ?: @""`; otherwise it returns nil. Create `Verborra/Verborra-Bridging-Header.h` with `#import "Support/ObjCExceptionCatcher.h"`. Add all three to `project.pbxproj` (the `.m` file in app Sources) and set `SWIFT_OBJC_BRIDGING_HEADER = Verborra/Verborra-Bridging-Header.h` for both configurations of the app target.
- [X] T050 [US2] Create `Verborra/Services/AudioEngineHost.swift` per [contracts/recording-start.md](./contracts/recording-start.md#host-interface): a `final class AudioEngineHost: AudioEngineHosting, @unchecked Sendable` owning `AVAudioEngine?` and a private serial `DispatchQueue(label: "dev.apeek.verborra.audio-engine", qos: .userInitiated)`. Requirements:
  - **All** engine and CoreAudio work runs inside `queue.async`, bridged with `withCheckedThrowingContinuation`.
  - `start(deviceID:generation:onBuffer:)` runs steps 1–6 of the "Host start sequence" table. Each step is timed with `ContinuousClock` into `AudioSetupTimings` (fields: `engineCreateMs`, `setDeviceMs`, `readFormatsMs`, `installTapMs`, `prepareMs`, `startMs`, `firstBufferMs: Double?` (filled by the facade, T051), `nodeSampleRate`, `hwSampleRate`, `channels`, `recreatedForStaleNode`).
  - Set the device via `AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)` and check the `OSStatus`; non-zero → `AudioSetupError.deviceUnavailable(step: "setDevice")`.
  - Read the node rate from `inputNode.outputFormat(forBus: 0)` and the hardware rate from `kAudioDevicePropertyNominalSampleRate`. If they differ, re-create the engine **once** and re-check; if they still differ → `.formatMismatch(node:hardware:)`.
  - Use `installTap(onBus: 0, bufferSize: 4096, format: nil)`.
  - Wrap `installTap`, `prepare` and `start` in `VBRTryCatch`. A caught exception → `.objcException(step:name:reason:)`.
  - Publish the step currently running in a `ManagedAtomic<Int>` (`currentStep`) for timeout logging.
  - `teardown(generation:)` runs `removeTap`/`stop` asynchronously on the queue, only if the generation matches or is nil, also guarded with `VBRTryCatch`.
  - `stop()` is awaited.
  - The host never touches `@MainActor` state (depends on T049).
- [X] T051 [US2] Refactor `AudioCaptureService` in `Verborra/Services/AudioCaptureService.swift` into a facade over `AudioEngineHost`:
  - Replace `private var engine: AVAudioEngine?` with `private var host: AudioEngineHost` and `private var generation: UInt64`.
  - `startRecording(...)` keeps the permission check and the Bluetooth stabilization (the BT trigger engine also goes through the host), then increments `generation` and runs `host.start` raced against `setupTimeout` (task group with a sleeping child; on timeout throw `AudioSetupError.timeout(step: <host.currentStep name>)` and call `host.teardown(generation:)`).
  - If the previous host is still busy (its last call didn't return), create a **new** `AudioEngineHost` for this attempt.
  - Wait for the first buffer up to `firstBufferTimeout`, replacing the 5 s loop at lines 212-226. If the engine is running without buffers, that counts as success. Measure the wait with `ContinuousClock` and store it in the attempt's `AudioSetupTimings.firstBufferMs` (`nil` if the attempt failed before this step).
  - `cancelStart()` increments `generation`, calls `host.teardown(generation: nil)`, cleans up BT stabilization (`cleanupBTStabilization()`), and returns immediately.
  - **Delete** the default-device fallback branch in `prepareAndStartEngine` (current lines 687-748) and all `onDeviceFallback` code.
  - Route `stopRecording`, `resetRecording` and `handleDeviceFormatChange` engine calls through the host (`await host.stop()` / `teardown`). `stopRecording` stays `async`. `resetRecording` and the format-change restart use fire-and-forget teardown plus `Task` for the restart.
  - Remove the forced `tapFormat` creation (lines 661-669).
  - `startFileWritingIfNeeded` takes the node format returned by the host. (Depends on T045, T050.)
- [X] T052 [US2] Add the per-attempt diagnostics in `Verborra/Services/AudioCaptureService.swift`, exactly as E1 and E2 in [contracts/diagnostic-events.md](./contracts/diagnostic-events.md#event-catalog):
  - after each attempt: INFO `Audio setup timings` (category `.engine`) with `attempt`, `generation`, `outcome` (`ok`/`failed`/`timeout`/`cancelled`), `deviceName`, `deviceID`, all `*Ms` fields including `firstBufferMs` (empty string when `nil`), `nodeSampleRate`, `hwSampleRate`, `channels`, `recreatedForStaleNode`
  - on each failure: ERROR `Audio setup failed` with `parameters` `step`, `attempt`, `deviceName`, `deviceID`, `nodeSampleRate`, `hwSampleRate`, `reason`, and `errorCode` ∈ `timeout`, `formatMismatch`, `objcException:<name>`, `engineStartFailed`, `deviceUnavailable` (FR-010, FR-012) (depends on T051)
- [X] T053 [US2] Implement start orchestration in `Verborra/ViewModels/RecordingViewModel.swift`:
  - add `private var startTask: Task<Void, Never>?`, `private var startBeganAt: ContinuousClock.Instant?`, and injectable budgets (`overallStartBudget = .seconds(5)`, `attemptSetupTimeout = .milliseconds(1800)`, `firstBufferTimeout = .milliseconds(600)`) via `init` default parameters for tests
  - rewrite `startRecording()`:
    - set `state = .starting(attempt: 1)`
    - inside `startTask`, run the existing BT preparation, then attempt 1
    - on failure, log it and set `state = .starting(attempt: 2)`
    - attempt 2 runs on the **same** `captureDeviceID`. **Both** of its timeouts are capped by what is left of the 5 s budget (measured after BT stabilization): `setupTimeout = min(2.4 s, remaining)`, then `firstBufferTimeout = min(0.6 s, remaining after setup)`; if nothing remains, fail with `.timeout(step: "budget")` (contract recording-start.md, FR-007)
    - on second failure: `state = .error(.recordingStartFailed(reason))` and ERROR `Recording start failed after retry` (category `.audio`; `deviceName`, `deviceID`, `totalMs`, `reason`)
    - on success: the existing `.recording` transition plus `startTimers()`, then INFO `Recording ready` (category `.audio`; `hotkeyToReadyMs` from the `startRecording()` call to `.recording` minus the Bluetooth mode switch, `btSwitchMs`, `attempts`, `deviceName`, `deviceID`; event E13 in contracts/diagnostic-events.md)
    - check `Task.isCancelled` after every await and return without touching state if cancelled
  - map `AudioSetupError` to `StartFailureReason` in `mapError`
  - **delete** the `onDeviceFallback` handler (current line ~145) (depends on T044, T045)
- [X] T054 [US2] Implement cancellation in `Verborra/ViewModels/RecordingViewModel.swift`:
  - add `func cancelStart(trigger: String)`. It cancels `startTask`, calls `audioCaptureService.cancelStart()` and `audioDeviceManager.bluetoothProfileManager.cancelPreparation()`, sets `state = .idle` synchronously, and logs INFO `Recording start cancelled` (`.userAction`; `attempt`, `elapsedMs`, `trigger`)
  - in `handleRecordingKey()`, add `case .starting: cancelStart(trigger: "hotkey")`
  - in `dismissOverlay()` and `cleanup()`, call `cancelStart(trigger: "esc"/"close")` when `state` is `.starting`
  - make `.error(.recordingStartFailed)` go to `startRecording()` through the existing `retryFromError()` path (FR-013a) (depends on T053)
- [X] T055 [P] [US2] Update `Verborra/Views/RecordingView.swift`: for `.starting`, show `ProgressView().controlSize(.small)` plus the text key `recording.starting` ("Starting microphone…"), and add `.recordingStartFailed` to `isRetryableError(_:)` so the existing Retry button appears (FR-013) (depends on T044).
- [X] T056 [P] [US2] Update `Verborra/Views/ControlBarView.swift`: in `.starting`, the Start/Stop button shows title key `controlbar.cancel` ("Cancel") with SF Symbol `xmark`, is enabled, and calls `viewModel.cancelStart(trigger: "button")`. The microphone and language menus are disabled while `.starting` (depends on T044, T054).
- [X] T057 [US2] Create `Verborra/Services/Logging/MainThreadWatchdog.swift`:
  - `struct HangContext: Sendable { var stage: String; var deviceName: String?; var deviceID: String?; var stageEnteredAt: Date }`, stored in `static let hangContext = OSAllocatedUnfairLock(initialState: HangContext(stage: "idle", …))` with `static func setStage(_:)` and `static func setDevice(name:id:)`
  - a pure `struct StallDetector` (input: `now`, `lastPong`; output: `.none`, `.warn(stallMs)`, `.recovered(stallMs)`), with threshold 2.0 s and one WARN per stall
  - `final class MainThreadWatchdog` with its own `DispatchQueue(label: "dev.apeek.verborra.watchdog", qos: .utility)` and a `DispatchSourceTimer` every 0.5 s. Each tick posts `DispatchQueue.main.async { lastPong.store(now) }` (`ManagedAtomic<UInt64>` of `DispatchTime.now().uptimeNanoseconds`) and feeds `StallDetector`
  - on `.warn`, write `logger.warn("Main thread unresponsive", metadata: stage, stageAgeMs, deviceName, deviceID, stallMs)` (category `.watchdog`); on `.recovered`, INFO `Main thread recovered` (`stage`, `stallMs`)
  - all watchdog logging uses category `.watchdog` (from T004)
  - skip ticks when `DiagnosticLogger.filterSnapshot` (from T006) has level `.off`; never call `logLevelProvider()` from the watchdog queue
  - it MUST NOT call any `@MainActor` API, `logLevelProvider`, `isRecordingActiveProvider` or `appStateProvider` (FR-011) (depends on T006)
- [X] T058 [US2] Publish `HangContext` updates:
  - in `Verborra/ViewModels/RecordingViewModel.swift`, extend the `state` `didSet` from T006 (and add one on `windowPhase`) that calls `MainThreadWatchdog.setStage(...)` with values `idle`, `starting.1`, `starting.2`, `recording`, `transcribing`, `formatting`, `postProcessing`, `error`, and `overlayShown` in `showOverlay()`
  - in `Verborra/Services/AudioCaptureService.swift`, call `MainThreadWatchdog.setDevice(name:id:)` at the start of each attempt (depends on T057)
- [X] T059 [US2] In `Verborra/VerborraApp.swift`:
  - as the **first** statements of `applicationDidFinishLaunching`, install `NSSetUncaughtExceptionHandler` (all builds), and inside `#if DEBUG` run `UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])`. Release builds keep AppKit's default exception handling (research R11). The handler logs ERROR `Uncaught exception` (category `.lifecycle`; `parameters` `name`, `reason`, `thread` = `main`/`background`, `callStack` = first 20 `callStackSymbols` joined by `\n`) and then calls `JSONLFileWriter.shared.flushSync()`. It may run on any thread (e.g. the audio queue), so it relies on T006's thread-safe filtering and touches no main-actor state.
  - after logging starts, create and start `MainThreadWatchdog` (keep a strong reference in `AppDelegate`)
  - add a `#if DEBUG` button "Simulate main-thread stall (3 s)" to `MenuBarView` that calls `Thread.sleep(forTimeInterval: 3)` on main (quickstart 2.6)
  - (R11) (depends on T057)
- [X] T060 [P] [US2] Add `Verborra/Localizable.xcstrings` entries (en + ru): `error.recordingStartFailed`, `recording.starting`, `controlbar.cancel`.
- [X] T061 [US2] Add the new files to `Verborra.xcodeproj/project.pbxproj` (`AudioEngineHost.swift`, `MainThreadWatchdog.swift` in app sources; `RecordingStartTests.swift`, `MainThreadWatchdogTests.swift` in test sources) and make the full test suite pass, including the updated existing tests in `VerborraTests/ViewModels/RecordingViewModelTests.swift` and `VerborraTests/ViewModels/DictationFlowTests.swift`, which use the old `startRecording` signature (depends on T044–T060).

**Checkpoint**: US2 is complete. Run quickstart §2.1–2.7.

---

## Phase 8: User Story 4 — Floating window: prompt selection at the bottom with number shortcuts 1-2-3 (Priority: P2)

**Goal**: The prompt menu moves from the top header to the bottom bar between microphone and language. Keys: 1 microphone, 2 prompt (cycle), 3 language, active only in pre-recording idle/error. The Start/Stop hint shows 🌐︎ (FR-023…FR-029).

**Independent Test**: [quickstart.md §4](./quickstart.md#4-floating-window-us4). Open the overlay: no top header; the bottom bar shows `[mic 1] [prompt 2] [language 3]`. Pressing 2 cycles prompts with wrap-around. Reopening resets to the default prompt.

### Tests for User Story 4

- [X] T062 [P] [US4] Add tests to `VerborraTests/ViewModels/RecordingViewModelTests.swift`:
  - `cyclePrompt()` with 3 prompts wraps 1→2→3→1
  - with 1 prompt it is a no-op
  - when the selected prompt was removed from the store it falls back to `promptsStore.defaultPrompt`
  - `handleKeyDown` keyCode 18/19/20 calls microphone/prompt/language cycling only when `windowPhase == .preProcessing` and `state` is `.idle` or `.error`, and returns `false`/does nothing in `.starting`, `.recording`, `.transcribing`, `.formatting` (AS 4.7)
  - `showOverlay()` resets `selectedPrompt` to the default after a key-2 change (FR-027)
  - `changePrompt` mirrors into `chatSession?.systemPrompt`
  - Build `NSEvent.keyEvent(with:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:)` for key events.

### Implementation for User Story 4

- [X] T063 [US4] In `Verborra/ViewModels/RecordingViewModel.swift`:
  - change `changePrompt(_ prompt: SystemPrompt)` to `changePrompt(_ prompt: SystemPrompt, source: PromptChangeSource = .menu)` (`enum PromptChangeSource: String { case menu, key }`). It sets `selectedPrompt`, sets `chatSession?.systemPrompt = prompt`, and logs INFO `Prompt changed` (`.userAction`; `from`, `to` = prompt names, `source`) (FR-029).
  - add `func cyclePrompt()` per [contracts/floating-window-keys.md](./contracts/floating-window-keys.md#cycleprompt-semantics): `prompts = promptsStore.prompts`; empty → return; index of `selectedPrompt.id`; nil → `changePrompt(promptsStore.defaultPrompt, source: .key)`; else `prompts[(i + 1) % prompts.count]` (FR-024, FR-026, FR-027).
  - if microphone (`switchAudioDevice`) and language (`changeTextLanguage`) changes have no `.userAction` INFO line yet, add `Microphone changed` / `Text language changed` with `from`, `to`, `source`.
- [X] T064 [US4] Update the `handleKeyDown(_:)` number keys in `Verborra/ViewModels/RecordingViewModel.swift` (currently lines ~889-902):
  - add `private var canCycleSelections: Bool { windowPhase == .preProcessing && (state == .idle || { if case .error = state { true } else { false } }()) }`
  - `case 18` → `cycleMicrophone()`, `case 19` → `cyclePrompt()`, `case 20` → `cycleTextLanguage()`, each requiring `eventModifiers.isEmpty && canCycleSelections`, returning `true` when handled
  - update the comments (key 2 is now prompt, key 3 is language) (depends on T063)
- [X] T065 [US4] Update `Verborra/Views/ControlBarView.swift`:
  - in `preProcessingButtons`, insert a new `controlBarMenu` **between** the microphone and language menus: `title: viewModel.selectedPrompt.name`, `sfSymbol: "text.quote"`, `hotkeyLabel: "2"`, `isEnabled: !isProcessing && !isStarting`. Its content is `ForEach(viewModel.promptsStore.prompts)` buttons calling `viewModel.changePrompt(prompt, source: .menu)` with a checkmark on the selected id. Limit the title width (`.frame(maxWidth: 180)` with tail truncation inside `ControlBarButtonLabel`, via a new optional `maxTitleWidth` parameter).
  - change the language menu `hotkeyLabel` from `"2"` to `"3"` and update its comment
  - replace the body of `formattedShortcutLabel` with `ShortcutFormatter.string(GlobalShortcutStore.shared.current)` and drop `import KeyboardShortcuts` (FR-028)
  - fix the `ControlBarButtonLabel` doc comment ("used by ControlBarView") (FR-023, FR-025) (depends on T009, T063)
- [X] T066 [US4] In `Verborra/Views/OverlayContentView.swift`, remove the top `PromptSelectorView` block (lines 13-18, "Prompt selector (preProcessing only)"). **Delete** the now-unused `Verborra/Views/Components/PromptSelectorView.swift`, `Verborra/Views/Components/MicrophoneSelectorButton.swift` and `Verborra/Views/Components/LanguageSelectorView.swift`, and remove them from `Verborra.xcodeproj/project.pbxproj` (FR-023) (depends on T065).
- [ ] T067 [US4] **(Automated suite passes; manual quickstart §4 pending — owner.)** Run the full test suite and quickstart §4.1–4.9 (depends on T062–T066).

**Checkpoint**: All four user stories work on their own.

---

## Phase 9: User Story 3 — Reliable shortcut recording with live modifier feedback and Fn support (Priority: P2)

**Goal**: A custom recorder shows held modifiers live, saves on the first regular key, validates against overlay, app and system shortcuts, and supports Fn. Global registration is hybrid: Carbon without Fn, a background CGEventTap with Fn. Overlay keys no longer intercept Settings (FR-014…FR-022, FR-028 for Settings).

**Independent Test**: [quickstart.md §3](./quickstart.md#3-shortcut-recorder-and-fn-us3). Hold ⌥ then ⇧ in the field and see `⌥ ⇧`. Press K and get `⌥ ⇧ K` saved. Set `🌐︎ Space`: it opens the overlay from any app and no space is typed. Arrow and F-keys alone are unaffected. Record 20 shortcuts with the overlay open and all are captured.

### Tests for User Story 3

- [X] T068 [P] [US3] Create `VerborraTests/Services/FnTrackingTests.swift` for `FnTracker` (T070):
  - `flagsChanged(63, fn: true)` then `keyDown(49, flags: [])` → modifiers `[.fn]`
  - `keyDown(126 /* ↑ */, flags: [.maskSecondaryFn])` without a prior Fn press → modifiers `[]` (no false positive)
  - same for F5 (96) and Home (115)
  - Fn released (`flagsChanged(63, fn: false)`) → the next keyDown has no `.fn`
  - ⌃⌥ held with Fn → `[.fn, .control, .option]`
  - keyCode 179 behaves like 63
- [X] T069 [P] [US3] Create `VerborraTests/Models/ShortcutValidatorTests.swift` for `ShortcutValidator` (T071), with an injected symbolic-hotkey list and an injected trial-register function. Cover each rule in order from [contracts/global-shortcut.md](./contracts/global-shortcut.md#validation-order-first-match-wins):
  - `K` alone → `.modifierRequired`
  - `⇧1`, `🌐︎ 2`, `Esc`, `3` → `.conflictsWithOverlay`
  - `⌥C`, `⌥⇧V`, `⌘W` → `.conflictsWithOverlay`
  - `⌘Q`, `⌘,` → `.reservedByApp`
  - `⌃↑` in the symbolic list → `.reservedBySystem`
  - a trial register that fails → `.inUseByAnotherApp`
  - `🌐︎ Space` → `.ok` (the trial register is skipped for Fn)
  - `⌥Space` → `.ok`

### Implementation for User Story 3

- [X] T070 [P] [US3] Create `Verborra/Services/FnEventTap.swift`, part 1: `struct FnTracker` (pure value type). It has `mutating func handleFlagsChanged(keyCode: UInt16, flags: CGEventFlags)`, which sets `fnHeld` only when `keyCode` is 63 or 179 and reads `flags.contains(.maskSecondaryFn)`, and `func effectiveModifiers(for flags: CGEventFlags) -> ShortcutModifiers`, which returns `ShortcutModifiers(cgFlags: flags)` without secondaryFn, plus `.fn` iff `fnHeld`. See [data-model.md FnTracker](./data-model.md#fntracker-pure-state-machine-unit-tested).
- [X] T071 [P] [US3] Create `Verborra/Models/ShortcutValidator.swift`:
  - `enum ShortcutRejection { case modifierRequired, conflictsWithOverlay, reservedByApp, reservedBySystem, inUseByAnotherApp }` with a localized `message`
  - `enum ShortcutValidationResult { case ok, rejected(ShortcutRejection) }`
  - `struct ShortcutValidator` with injectable `symbolicHotKeys: () -> [(keyCode: UInt16, modifiers: ShortcutModifiers)]` (production: `CopySymbolicHotKeys`, enabled entries only, Carbon modifiers converted) and `trialRegister: (GlobalShortcut) -> Bool` (production: `RegisterEventHotKey` with signature `"VBRt"` and id 9999, then immediately `UnregisterEventHotKey`; `false` on `eventHotKeyExistsErr`)
  - `validate(_:)` applies the 5 rules **in order** exactly as in the contract table. Rule 2: keyCode ∈ {53, 18, 19, 20} with modifiers ⊆ {fn, shift}, or keyCode ∈ {8, 9} with modifiers ∈ {[.option], [.option, .shift]}, or ⌘W (13). Rule 3: ⌘Q (12) and ⌘, (43). Rule 4 compares ignoring `.fn`. Rule 5 runs only when `!requiresEventTap`.
- [X] T072 [US3] Create `Verborra/Services/FnEventTap.swift`, part 2: `final class FnEventTap`. It starts a dedicated `Thread` (name `dev.apeek.verborra.fn-tap`) that creates `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: keyDown | flagsChanged, callback:, userInfo:)`, adds its run-loop source to **that thread's** `CFRunLoop`, and runs it. Callback behaviour:
  - on `.tapDisabledByTimeout` / `.tapDisabledByUserInput` → `CGEvent.tapEnable(tap:, enable: true)` plus INFO `Event tap re-enabled` (`reason`, category `.hotkey`)
  - flagsChanged → `FnTracker.handleFlagsChanged`, then pass the event through
  - keyDown: if `isPaused` (atomic) or autorepeat (`.keyboardEventAutorepeat` field != 0), pass through; if keyCode and effective modifiers equal the target `GlobalShortcut` (stored in an `OSAllocatedUnfairLock`), return `nil` and `DispatchQueue.main.async(onMatch)`; otherwise pass the event through unchanged
  - it never logs key codes of non-matching events
  - logging from the tap thread relies on T006's thread-safe filtering; the tap never reads main-actor state
  - `start()` returns `false` if `tapCreate` returns nil
  - `stop()` invalidates the mach port, removes the source and stops the run loop (depends on T070)
- [X] T073 [US3] Create `Verborra/Services/GlobalHotkeyService.swift` implementing `GlobalHotkeyServiceProtocol` from [contracts/global-shortcut.md](./contracts/global-shortcut.md#service-interface) (`@MainActor @Observable`):
  - holds `GlobalShortcutStore.shared`, a `ShortcutValidator` and an optional `FnEventTap`
  - `enum HotkeyRegistrationStatus { case active(Mechanism), needsAccessibility, failed(String), paused }` with `enum Mechanism: String { case carbon, eventTap }`
  - `register()`: tear down both mechanisms first. If `!requiresEventTap`, call `KeyboardShortcuts.setShortcut(.init(carbonKeyCode: Int(keyCode), carbonModifiers: carbonFlags), for: .toggleOverlay)` plus one-time `KeyboardShortcuts.onKeyDown(for: .toggleOverlay)`. Otherwise call `KeyboardShortcuts.setShortcut(nil, for: .toggleOverlay)` and start `FnEventTap`; on failure set `.needsAccessibility` if `!AXIsProcessTrusted()`, else `.failed`.
  - `isPaused`: for Carbon use `KeyboardShortcuts.disable/enable(.toggleOverlay)`; for the tap set its atomic flag; status `.paused`
  - `apply(_:)`: validate → if ok, save to the store → `register()` → INFO `Global shortcut changed` (`old`, `new` via `ShortcutFormatter.string`, `mechanism`); if rejected, INFO `Global shortcut rejected` (`candidate`, `reason`); registration error → ERROR `Global shortcut registration failed` (all of these in category `.hotkey`)
  - `resetToDefault()` = `apply(.default)`
  - observe `PermissionManager.shared.accessibilityStatus` changes and call `register()` again when it becomes `.granted` while status is `.needsAccessibility`
  - firing logs INFO `Hotkey triggered` (`.userAction`; `mechanism`) and calls `onToggle` on main
  - move the `KeyboardShortcuts.Name.toggleOverlay` extension here (depends on T009, T071, T072)
- [X] T074 [US3] Replace `HotkeyService` with `GlobalHotkeyService` in `Verborra/VerborraApp.swift` (`AppController`: property type, init, `start(onToggle:)`), expose it so the Settings scene environment can reach it, and **delete** `Verborra/Services/HotkeyService.swift`. Check that no remaining reference to `HotkeyService` exists (`grep -rn "HotkeyService\b" Verborra VerborraTests` returns only `GlobalHotkeyService`) (depends on T073).
- [X] T075 [US3] Create `Verborra/Views/Components/ShortcutRecorderField.swift`:
  - an AppKit `final class ShortcutRecorderNSView: NSView` with `acceptsFirstResponder = true`, a rounded-field appearance, `mouseDown` → `window?.makeFirstResponder(self)`, `becomeFirstResponder` → `onRecordingChanged(true)`, and `resignFirstResponder` → `onRecordingChanged(false)` plus a reset to idle
  - `flagsChanged(with:)`: update `FnTracker` from `event.keyCode`/`event.modifierFlags.contains(.function)`, then redraw the held modifiers via `ShortcutFormatter.symbols` (FR-014); if every modifier is released, show the placeholder `shortcut.recorder.placeholder` ("Press shortcut…")
  - `keyDown(with:)`: Esc (53) → cancel and resign (FR-018). With modifiers empty → show the hint `shortcut.rejection.modifierRequired` (FR-017). Otherwise build `GlobalShortcut(keyCode:modifiers:)` from the tracker's effective modifiers and call `onCapture(shortcut)`, which returns `ShortcutValidationResult`. On `.ok` resign first responder (FR-016); on `.rejected` show the message and resign.
  - override `performKeyEquivalent(with:)` to return `true` while first responder, so ⌘-combos reach `keyDown` and don't trigger menu items
  - a SwiftUI wrapper `struct ShortcutRecorderField: NSViewRepresentable` with inputs `shortcut: GlobalShortcut`, `onCapture`, `onRecordingChanged`
  - (depends on T008, T070, T071)
- [X] T076 [US3] Rewrite `Verborra/Views/HotkeysSettingsTab.swift`:
  - a `LabeledContent(l10n.string("settings.hotkeys.globalHotkey"))` containing `ShortcutRecorderField` (`onCapture` → `hotkeyService.apply`; `onRecordingChanged` → `hotkeyService.isPaused = $0`) and a button `settings.hotkeys.reset` ("Reset to default") → `resetToDefault()`
  - below it: the last rejection message (orange) and the status line (`.needsAccessibility` → `settings.hotkeys.needsAccessibility` "🌐︎ shortcuts need Accessibility access" plus a button reusing `PermissionStatusView(permissionType: .accessibility)`; `.failed(msg)` → red)
  - **delete** `Verborra/Views/Components/HotkeyRecorder.swift` (depends on T073, T075)
- [X] T077 [US3] Remove the legacy recording key:
  - in `Verborra/Models/AppSettings.swift`, delete `recordingKeyCode`, `recordingModifiers` and `recordingKeyDisplayName` (lines ~181-215) after T008 has taken over the `UCKeyTranslate` logic
  - in `Verborra/ViewModels/SettingsViewModel.swift`, delete `hasRecordingHotkeyConflict` (lines ~189-199) and the `KeyboardShortcuts` import if unused
  - also remove the UserDefaults keys `recordingKeyCode`/`recordingModifiers` once at launch (`UserDefaults.standard.removeObject`)
- [X] T078 [US3] Scope the overlay key monitor to the overlay panel (FR-020):
  - in `Verborra/Views/OverlayPanel.swift`, give `OverlayManager` `func installKeyMonitor(_ handler: @escaping (NSEvent) -> Bool)`, called from `show(with:)`. It uses `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` and returns the event untouched unless `event.window === panel`. Remove the monitor in `dismiss()`.
  - in `Verborra/Views/OverlayContentView.swift`, delete the `keyMonitor` `@State` and its `onAppear`/`onDisappear` add/remove code (keep `cleanup()`/permission monitoring)
  - in `Verborra/ViewModels/RecordingViewModel.showOverlay()`, pass `handleKeyDown` to `overlayManager.installKeyMonitor` after `overlayManager.show`
- [X] T079 [US3] Use `ShortcutFormatter.string(GlobalShortcutStore.shared.current)` instead of `KeyboardShortcuts.getShortcut(for: .toggleOverlay)` in `Verborra/Views/Onboarding/CompletionStep.swift` (line ~25), so 🌐︎ appears there too (FR-028) (depends on T009).
- [X] T080 [P] [US3] Add `Verborra/Localizable.xcstrings` entries (en + ru):
  - `shortcut.recorder.placeholder`
  - `shortcut.rejection.modifierRequired` ("Add at least one modifier (🌐︎ ⌃ ⌥ ⇧ ⌘).")
  - `shortcut.rejection.conflictsWithOverlay` ("This shortcut is used inside the Verborra window.")
  - `shortcut.rejection.reservedByApp` ("This shortcut is used by Verborra's menu.")
  - `shortcut.rejection.reservedBySystem` ("This shortcut is reserved by macOS.")
  - `shortcut.rejection.inUseByAnotherApp` ("This shortcut is already used by another app.")
  - `settings.hotkeys.reset`
  - `settings.hotkeys.needsAccessibility`
- [X] T081 [US3] Update `Verborra.xcodeproj/project.pbxproj`:
  - add `GlobalHotkeyService.swift`, `FnEventTap.swift`, `ShortcutValidator.swift`, `ShortcutRecorderField.swift`, `FnTrackingTests.swift`, `ShortcutValidatorTests.swift`
  - remove `HotkeyService.swift` and `HotkeyRecorder.swift`
  - run the full test suite (depends on T068–T080)

**Checkpoint**: US3 is complete. Run quickstart §3.1–3.8.

---

## Phase 10: User Story 8 — See the price of every model (Priority: P3)

**Goal**: Both info popovers show all entries with prices; the 10-entry text popover scrolls.

**Independent Test**: quickstart 5.6.

- [X] T082 [US8] In `Verborra/Views/LLMSettingsTab.swift` `modelInfoPopover(models:)`: wrap the `VStack` in `ScrollView(.vertical)` with `.frame(width: 280)` and `.frame(maxHeight: 420)`; keep the row styling (`.headline` name, `.caption` secondary description) and `padding(12)`. Pickers are unchanged (FR-031)
- [X] T083 [P] [US8] Check the four kept model descriptions in `Verborra/Localizable.xcstrings` (en + ru) against [research.md](./research.md) R18: gpt52 $1.75/$14.00, gpt54Mini $0.75/$4.50, gpt54 $2.50/$15.00, gpt55 $5.00/$30.00; make sure every description includes its price (FR-034). Change "Latest flagship model" for gpt55, since it's no longer the latest (e.g. "Flagship 5.5 model" / "Флагманская модель 5.5")
- [X] T084 [P] [US8] Add a test to `VerborraTests/LLMModelTests.swift` and `VerborraTests/STTModelTests.swift`: every case's `infoDescription` contains `"$"` and isn't the raw key (`!hasPrefix("model.")`), for both languages: set `LocalizationManager.shared.currentLanguage = .ru`, check, then `.en`, and restore the original language at the end (same pattern as `VerborraTests/LocalizationManagerTests.swift:31-39`)

**Checkpoint**: US8 is done; all eight user stories work on their own.

---

## Phase 11: Polish & Cross-Cutting Concerns

**Purpose**: The model-unavailable error (FR-040), documentation, lint and release validation for all stories.

### Model-unavailable error (US5–US8 edge case, FR-040)

- [X] T085 Add `case modelUnavailable(modelName: String, kind: ModelKind)` to `RecordingError` in `Verborra/Models/RecordingState.swift`, with `enum ModelKind: Equatable { case speechToText, text }` in the same file; `errorDescription` → `l10n.string("error.modelUnavailable.text", args: modelName)` / `"error.modelUnavailable.stt"`. Check every `switch` over `RecordingError` (grep `case .deviceUnavailable` in `Verborra/`) and handle the new case the same way as `.formattingFailed` / `.transcriptionFailed` (an error state, not retryable)
- [X] T086 [P] Add to `Verborra/Localizable.xcstrings`: `error.modelUnavailable.text` en "%@ isn't available for your OpenAI account. Choose another text model in Settings." / ru "Модель %@ недоступна для вашего аккаунта OpenAI. Выберите другую текстовую модель в настройках."; `error.modelUnavailable.stt` en "%@ isn't available for your OpenAI account." / ru "Модель %@ недоступна для вашего аккаунта OpenAI."
- [X] T087 Add a shared helper `static func isModelUnavailable(status: Int, body: String) -> Bool` (true for 404 with any body, or 400/403 whose JSON `error.code` is `model_not_found` or `model_not_available`) in a new `extension RecordingError` in `Verborra/Models/RecordingState.swift`
- [X] T088 Map it in the three services, never retrying and never falling back to another model: `Verborra/Services/FormattingService.swift` `performWithRetry` (in the `default:` branch, before `formattingFailed`, which has no `model` in scope, so pass `model` into `performWithRetry`); `Verborra/Services/StreamingFormattingService.swift` `default:` status branch; `Verborra/Services/TranscriptionService.swift` `case 400` and `default:` branches (also pass `model` into `performWithRetry`). Throw `.modelUnavailable(modelName: model.displayName, kind: .text|.speechToText)`, and log ERROR with `parameters: ["method": "<func>", "model": model.rawValue, "status": …, "message": <OpenAI error.message, first 500 chars>]` (constitution P6: method, parameters and error description) and `errorCode` = OpenAI `error.code` or the HTTP status
- [X] T089 [P] Tests: in `VerborraTests/Services/FormattingServiceTests.swift`, `StreamingFormattingServiceTests.swift` and `TranscriptionServiceTests.swift`, a 404 response throws `.modelUnavailable(modelName: <displayName>, kind:)` after **exactly one** request (`MockURLProtocol` request count == 1); a 400 with `{"error":{"code":"model_not_found"}}` maps the same way; a 400 with another code still throws `formattingFailed` / `transcriptionFailed`

### Documentation

- [X] T090 [P] Audit `Verborra/Localizable.xcstrings` so every key added in T015, T042, T060, T080 and T086 has both `en` and `ru` translations and no orphaned keys remain from deleted views (`PromptSelectorView`, `HotkeyRecorder`).
- [X] T091 [P] Update `README.md`: the hotkey section mentions Fn/🌐︎ support and that 🌐︎ shortcuts need Accessibility; the floating-window keys are now 1/2/3; the Settings section lists the new model list and defaults (GPT Transcribe, GPT-6 Luna); the build section mentions the ad-hoc + Hardened Runtime build and the `codesign -dv` check. Also add a note recommending System Settings › Keyboard › "Press 🌐︎ key to: Do Nothing" for Fn-shortcut users (research R14).
- [X] T092 [P] Add an `Unreleased` entry to `CHANGELOG.md` summarizing US1–US8 (including the removed models and the silent switch to the new defaults) (user-facing wording).
- [X] T093 [P] Add a `015-reliability-shortcuts-models` line to the "Active Technologies" section of `CLAUDE.md`: Swift 5.9+ + ServiceManagement (SMAppService status), CoreGraphics CGEventTap (Fn hotkey, background thread), Carbon (RegisterEventHotKey/CopySymbolicHotKeys), one Objective-C NSException shim; storage UserDefaults (`globalShortcut.v1`, `launchAtLogin` intent, `selectedSTTModelRawValue`/`selectedLLMModelRawValue`); OpenAI model catalog with per-model request options (no new dependencies).

### Release validation

- [X] T094 Run `swiftlint lint` (development-only tool from T003; required by constitution Principle 5, not optional) on **every file created or modified by this feature** (`git diff --name-only main -- "*.swift"` plus new files) and fix all violations in them. Violations in untouched files are out of scope. Never add SwiftLint to the app target, packages or build phases. Then build Release with **zero warnings** (`xcodebuild build -project Verborra.xcodeproj -scheme Verborra -configuration Release 2>&1 | grep -c "warning:"` → 0).
- [ ] T095 Run the quickstart 5.2 live probe for all 10 text models and `gpt-transcribe`, recording the error code, `finish_reason`, visible-text length and time for each under R21 in `specs/015-reliability-shortcuts-models/research.md`
- [ ] T096 Apply the probe results in `Verborra/Models/LLMModel.swift` and the matching T018/T021 test rows: a kept model with `temperature` that gets a 400 → `supportsTemperature = false`; `gpt-5.6-sol` rejecting `"none"` → `.low`; a kept model returning `length`, empty text or taking more than 2× the slowest new model's time → set `reasoningEffort` to its lowest supported value (`.none` where the model page lists it, otherwise `.low`) and probe again (R20). If a model still fails for any other reason, remove it per research R28: delete the case, its `model.llm.<case>.info` key, its rows in `TokenEstimator` and the tests, and add its ID to the T018 "decodes to nil" list and a T029 "removed" case; then tell the user. If the failing model is `gpt-6-luna` or `gpt-transcribe`, stop and ask the user instead
- [ ] T097 Run `specs/015-reliability-shortcuts-models/quickstart.md` §0–§4 on the Release build installed in `/Applications`, including the one-time removal of stale `com.apeek.Verborra` copies (`mdfind "kMDItemCFBundleIdentifier == 'com.apeek.Verborra'"`), and record the results in `specs/015-reliability-shortcuts-models/verification/quickstart-results.md`. Also check constitution Principle 3 (hotkey to ready for recording ≤ 300 ms): from the `Audio setup timings` lines of quickstart 2.1, compute the median `hotkeyToReadyMs` from the `Recording ready` lines (E13) for non-Bluetooth, single-attempt starts and record it (it must be ≤ 300 ms). Note that it starts at the `startRecording()` call, so the few milliseconds of hotkey dispatch before it are not included. Also confirm Hardened Runtime compatibility (constitution P4): `codesign -dv` shows `flags=0x10002(adhoc,runtime)`, and recording (quickstart 2.1), paste into another app (⌥V) and the 🌐︎ shortcut (3.3) all work on that build. Row 2.8 (the 2-week soak) is recorded as "in progress".
- [ ] T098 Run quickstart 5.3–5.8 manually on the same build (fresh install, upgrade migration, 10× end-to-end per new model plus one dictation per kept model, popovers in en/ru, model-unavailable error, transcription quality vs GPT-4o Mini Transcribe) and record pass/fail in `specs/015-reliability-shortcuts-models/verification/quickstart-results.md`

## Phase 12: User Story 9 — Switch microphone while recording, and close the window at any moment (Priority: P1)

**Added 2026-10-15** (merged from former spec 018). Root causes: [investigation.md §3](./investigation.md). Design: [research.md R31](./research.md), [contracts/recording-start.md](./contracts/recording-start.md) "Microphone switch", [data-model.md §3](./data-model.md) `StartKind`.

**Goal**: A mid-recording switch goes through the same start path as the hotkey (`.starting`, retry, one 5 s budget including the Bluetooth step, cancel on close/Esc/hotkey/stop), the audio host is reused so stop and start never overlap, and the error names the microphone.

**Independent Test**: Quickstart 2.9–2.11: switch to each kind of microphone 10 times while recording; close during a switch; unplug a USB mic during a switch.

### Tests for User Story 9

- [X] T099 [P] [US9] Extend `VerborraTests/Mocks/MockAudioCaptureService.swift`: add the new `bluetoothTimeout: Duration` parameter to `startRecording(...)` and record it in a new `bluetoothTimeouts: [Duration]`; add `calls: [String]` that appends `"reset"` in `resetRecording()`, `"start"` in `startRecording(...)` and `"cancel"` in `cancelStart()`, so tests can assert the order (reset before start). Keep the existing scripted failures and delays.
- [X] T100 [US9] Create `VerborraTests/ViewModels/MicrophoneSwitchTests.swift` (`@MainActor final class … : XCTestCase`, same setup style as `RecordingStartTests.swift`, a device list with at least System Default, "USB Mic" and "Built-in Mic"). Cases, all written before T104–T106 and failing first:
  1. While `.recording`, `switchAudioDevice(to: <USB uid>)` → `state == .starting(attempt: 1)`, `startKind == .switching(to: "USB Mic")`, mock `calls` == `[…, "reset", "start"]` (reset before start), and the recording timer is stopped.
  2. Mock succeeds → `state == .recording(duration: 0, remaining: max)` (restart from zero).
  3. Attempt 1 fails, attempt 2 succeeds on the **same** device id; both fail → `state == .error(.recordingStartFailed(<reason>, deviceName: "USB Mic"))` and `lastStartKind == .switching(to: "USB Mic")`.
  4. In that error state, `switchAudioDevice(to: <Built-in uid>)` starts a new switch (`.starting(attempt: 1)`, one more `"start"` call). After a failed **initial** start (`lastStartKind == .initial`), `switchAudioDevice` only changes the selection (no `"start"` call).
  5. During a switch, `handleKeyDown` with keyCodes 18, 19, 20 returns `false` and the microphone, language and prompt stay unchanged.
  6. During a switch, `dismissOverlay()` → `state == .idle`, mock `calls` contains `"cancel"`; when the mock's delayed start then completes, `state` stays `.idle` (no late `.recording`).
  7. During a switch, `handleRecordingKey()` (the hotkey) → `state == .idle`, and the transcription mock was never called.
  8. Budget: for a Bluetooth target, the `bluetoothTimeout` passed to attempt 1 is ≤ 5 s and measured from the switch request; for an `.initial` start it is 5 s.
  A2DP restore on cancel isn't observable through `BluetoothProfileManager` in tests; it is checked manually in quickstart 2.10.
- [X] T101 [P] [US9] **(Done 2026-10-15 via the new `AudioEngineHosting` protocol and `prepareHostForStart()`/`noteHostTimedOut()`/`displayName(forDeviceID:resolver:)` seams — no real audio or permission prompts; analysis U1.)** Create `VerborraTests/Services/AudioCaptureHostReuseTests.swift` using the host factory added in T104 with a fake `AudioEngineHost` subclass or protocol double: (a) `resetRecording()` followed immediately by `startRecording(...)` reuses the **same** host (factory called once) even though a teardown is still queued; (b) after a start that timed out on a host, the next `startRecording` creates a new host (factory called twice); (c) the failure log/`currentDeviceName` uses the device's display name, not its numeric id (inject a name resolver if needed).

### Implementation for User Story 9

- [X] T102 [US9] In `Verborra/Models/RecordingState.swift` change `case recordingStartFailed(StartFailureReason)` to `case recordingStartFailed(StartFailureReason, deviceName: String)` and its message to `l10n.string("error.recordingStartFailed", args: deviceName, reason.shortDescription)`. Update every use: `Verborra/Views/RecordingView.swift` (`isRetryableError`, ~line 176), `Verborra/ViewModels/RecordingViewModel.swift` (`state = .error(...)` ~line 714 and `mapError` ~line 1248, which gets the device name from the current start), and `VerborraTests/ViewModels/RecordingStartTests.swift` (~lines 104, 130).
- [X] T103 [P] [US9] In `Verborra/Localizable.xcstrings`: change `error.recordingStartFailed` to en "Couldn't start %1$@ (%2$@). Press Retry or close the window." / ru "Не удалось запустить %1$@ (%2$@). Нажмите «Повторить» или закройте окно."; add `recording.switching` en "Switching to %@…" / ru "Переключение на %@…".
- [X] T104 [US9] **(Done 2026-10-15. Also: `protocol AudioEngineHosting` added (U1); the Bluetooth settle wait now uses what is left of `bluetoothTimeout` instead of a fixed 5 s (U2); `AudioEngineHost.isBusy`/`busyCount` removed.)** In `Verborra/Services/AudioCaptureService.swift` (R31 items 1, 3, 7):
  - Add `bluetoothTimeout: Duration` to `AudioCaptureServiceProtocol.startRecording(...)`, to the convenience extension (default `.seconds(5)`), to the implementation and to `MockAudioCaptureService` (T099). `runBluetoothSwitch` races against `bluetoothTimeout` instead of `setupTimeout`.
  - Replace the `if host.isBusy { … host = AudioEngineHost() } else { host.teardown(generation: nil) }` block with: `if hostIsStuck { log "Audio host abandoned after timeout" (INFO, .engine, step: host.currentStep.name); host = makeHost(); hostIsStuck = false } else { host.teardown(generation: nil) }`. Set `hostIsStuck = true` inside the `onTimeout` closures of `startHost` and `runBluetoothSwitch` (they run off the main actor, so store it in a `ManagedAtomic<Bool>`). Remove `AudioEngineHost.isBusy`/`busyCount` if nothing else uses them.
  - Add `init(hostFactory: @escaping () -> AudioEngineHost = { AudioEngineHost() })` (keep the existing call sites compiling) and use `makeHost()` everywhere a host is created; T101 uses it.
  - At the start of `startRecording`, set `currentDeviceName` to the display name: `deviceID.flatMap { AudioDeviceID($0) }.flatMap(CoreAudioQuery.name) ?? (deviceID == nil ? "System Default" : deviceID)`.
- [X] T105 [US9] In `Verborra/ViewModels/RecordingViewModel.swift` (R31 items 2, 4, 5):
  - Add `enum StartKind: Equatable { case initial; case switching(to: String) }`, `private(set) var startKind: StartKind = .initial` and `private(set) var lastStartKind: StartKind = .initial`.
  - Move the body of `startRecording()` after the API-key check and breadcrumb into `private func beginStart(kind: StartKind)`; `startRecording()` calls `beginStart(kind: .initial)`. Budgets: `.initial` keeps the current logic (Bluetooth preparation outside the 5 s; pass `bluetoothTimeout: .seconds(5)`); `.switching` sets `budgetStart` at the request, before Bluetooth preparation, and passes `bluetoothTimeout: max(remaining, 1 ms)`, so preparation + trigger + attempts fit in 5 s (FR-049). On final failure set `state = .error(.recordingStartFailed(reason, deviceName: deviceName))` and `lastStartKind = kind`; on success `lastStartKind = kind`.
  - Rewrite `switchAudioDevice(to:source:)`: keep the logging, `cancelPreparation`, A2DP restore of the previous Bluetooth device and `selectDeviceForSession`. Then: if `state` is `.recording` → `stopTimers()`, `audioCaptureService.resetRecording()`, `beginStart(kind: .switching(to: <new device name>))`; else if `state` is `.error(.recordingStartFailed)` and `lastStartKind` is `.switching` → `beginStart(kind: .switching(to:))`; otherwise only the selection changes. Delete `switchTask` and every reference to it.
  - In `cancelStart(trigger:)`: if the start's target device is Bluetooth and its preparation ran, call `audioDeviceManager.bluetoothProfileManager.restoreA2DP(device:)`. On a failed switch to a Bluetooth device, restore A2DP too.
- [X] T106 [US9] **(Done; `failed` also carries `reason` and `deviceID` per constitution P6, analysis C1.)** Log E16 in `Verborra/ViewModels/RecordingViewModel.swift` ([contracts/diagnostic-events.md](./contracts/diagnostic-events.md)): once per `.switching` start, when it ends, `Microphone switch` on `.audio` with `from`, `to` (display names), `outcome` (`ok` → INFO, `cancelled` → INFO with `trigger`, `failed` → ERROR with `errorCode: "microphoneSwitchFailed"`), `durationMs`, `attempts`.
- [X] T107 [P] [US9] In `Verborra/Views/RecordingView.swift`, the `.starting` caption shows `l10n.string("recording.switching", args: name)` when `viewModel.startKind` is `.switching(to: name)`, otherwise `recording.starting`. Confirm `Verborra/Views/ControlBarView.swift` shows Cancel and disables the three menus in `.starting` (it already uses `!isStarting`); no timer is shown counting during the switch.
- [X] T108 [US9] Add `MicrophoneSwitchTests.swift` and `AudioCaptureHostReuseTests.swift` to the `VerborraTests` target in `Verborra.xcodeproj/project.pbxproj`; update other call sites of `startRecording(...)` and `.recordingStartFailed(...)` in `VerborraTests/` (`RecordingStartTests.swift`, `DictationFlowTests.swift`, `RecordingViewModelTests.swift`); run the full test suite: 0 failures, 0 warnings.

**Checkpoint**: US9 works on its own. Quickstart 2.9–2.11 are manual (T127).

---

## Phase 13: User Story 4 amendment — bar order 1 microphone, 2 language, 3 prompt, and menu titles (Priority: P2)

**Added 2026-10-15** (merged from former spec 016). Design: [research.md R29](./research.md), [contracts/floating-window-keys.md](./contracts/floating-window-keys.md).

**Goal**: The bar reads microphone `1`, output language `2`, prompt `3`; the keys follow; each menu starts with a non-selectable title.

**Independent Test**: Quickstart 4.1–4.10.

- [X] T109 [US4] Update `VerborraTests/ViewModels/RecordingViewModelTests.swift` first: keyCode 19 cycles the **output language** and 20 cycles the **prompt** (rename `testNumberKeysWorkWhenIdle` assertions and the cyclePrompt key tests accordingly); keys still work in `.idle`, `.recording` and `.error`; `.starting`, `.transcribing`, `.formatting` and post-processing ignore them.
- [X] T110 [US4] In `Verborra/ViewModels/RecordingViewModel.swift` `handleKeyDown`: `case 19` → `cycleTextLanguage()`, `case 20` → `cyclePrompt()`; update the comment to "1 microphone, 2 output language, 3 prompt". Update the `Prompt changed` log `source` comment if it mentions key 2.
- [X] T111 [US4] In `Verborra/Views/ControlBarView.swift` `preProcessingButtons`: order microphone, output language (hint `"2"`), prompt (hint `"3"`). Wrap each menu's content in `Section(LocalizationManager.shared.string("controlbar.menu.inputDevice" | "controlbar.menu.outputLanguage" | "controlbar.menu.prompt")) { … }`; keep the microphone menu's existing `Divider()` between System Default and the devices inside the section, and make sure no two separators touch when only System Default exists. Give the microphone menu `maxTitleWidth: 180`.
- [X] T112 [P] [US4] In `Verborra/Localizable.xcstrings` add `controlbar.menu.inputDevice` en "Input device" / ru "Устройство ввода", `controlbar.menu.outputLanguage` en "Output language" / ru "Язык вывода", `controlbar.menu.prompt` en "Using prompt" / ru "Используемый промпт".

**Checkpoint**: US4 matches the amended spec.

---

## Phase 14: User Story 10 — Prompt names fit in the floating window (Priority: P3)

**Added 2026-10-15** (merged from former spec 016). Design: [research.md R32](./research.md), [data-model.md §7](./data-model.md).

**Goal**: Names are limited to "30 user-visible characters" (`String.count`); a counter shows `n/30`; older longer names are kept, shortened with "…" in the bar, and must be shortened before saving.

**Independent Test**: Quickstart 4.11–4.12.

- [X] T113 [P] [US10] Create `VerborraTests/Models/PromptNameRuleTests.swift` (failing first): `PromptNameRule.clamp(new:old:)` — typing from 30 to 31 characters returns the first 30; pasting 45 into a 10-character name returns 30; `old` of 42 and `new` of 41 returns 41 unchanged; emoji, accented letters and CJK each count as 1. `PromptNameRule.display(_:)` — 30 characters unchanged; 31 characters → first 29 + "…". Every `SystemPromptDefinition` name in every `SupportedLanguage` and `settings.prompts.newPrompt` in en and ru have `count <= 30`. `SettingsViewModel`: setting `editingPromptName` to 45 characters when it was 10 leaves 30; `saveCurrentPrompt()` with a 42-character legacy name doesn't change the stored prompt.
- [X] T114 [US10] In `Verborra/Models/SystemPrompt.swift` add `static let maxNameLength = 30` to `SystemPrompt` and `enum PromptNameRule { static func clamp(new: String, old: String) -> String; static func display(_ name: String) -> String }` per data-model §7: clamp returns `String(new.prefix(30))` only when `new.count > 30 && old.count <= 30`; display returns the name when `count <= 30`, else `String(name.prefix(29)) + "…"`.
- [X] T115 [US10] In `Verborra/ViewModels/SettingsViewModel.swift`: `editingPromptName` gets a `didSet` that applies `PromptNameRule.clamp(new:old:)` (guard against re-entry); add `var isPromptNameTooLong: Bool { editingPromptName.count > SystemPrompt.maxNameLength }`; `saveCurrentPrompt()` returns early when it is true.
- [X] T116 [US10] In `Verborra/Views/SettingsView.swift` `promptEditor`: under the name `TextField`, a caption `"\(viewModel.editingPromptName.count)/30"` (`.caption`, `.secondary`, `.red` when too long) and, when too long, `l10n.string("settings.prompts.nameTooLong")`; the Save button gets `.disabled(viewModel.isPromptNameTooLong)`.
- [X] T117 [P] [US10] In `Verborra/Localizable.xcstrings` add `settings.prompts.nameTooLong` en "Shorten the name to 30 characters or fewer." / ru "Сократите название до 30 символов."
- [X] T118 [US10] **(Done 2026-10-15 in code: min-gap spacer, fixed right group at priority 3, language 2, prompt 1, microphone 0 with tail truncation. The by-eye check in a running app could not be done from the agent shell; it is part of quickstart 4.13 in T127.)** In `Verborra/Views/ControlBarView.swift` (after T111), per research R34 and FR-063: the prompt menu title is `PromptNameRule.display(viewModel.selectedPrompt.name)` and the prompt menu has **no** fixed `maxTitleWidth`. Lay the bar out as left group (microphone, language, prompt) + `Spacer(minLength: <the bar's normal button spacing>)` + right group (Start/Stop/Cancel, Exit). Menu labels size to their title (`lineLimit(1)`, `truncationMode(.tail)`, horizontal `fixedSize` on the title only up to the available width); layout priorities: right group 3 (never shrinks), language 2, prompt 1, microphone 0, so the microphone title truncates first, then the prompt. Verify by eye in the Xcode preview with: prompt names "Ask", "Rewrite with info-style", 30 Latin and 30 CJK characters; a long microphone name; Start/Cancel/Stop; shortcut `🌐︎ ⌃ ⌥ ⌘ Space`. In no case may the prompt button touch or overlap the right group.
- [X] T119 [US10] Add `PromptNameRuleTests.swift` to the `VerborraTests` target in `Verborra.xcodeproj/project.pbxproj` and run the full test suite.

**Checkpoint**: US10 works on its own.

---

## Phase 15: User Story 2 amendment — stall test in Settings › Advanced (Priority: P1)

**Added 2026-10-15** (merged from former spec 017). Design: [research.md R30](./research.md).

**Independent Test**: Quickstart 2.6.

- [X] T120 [US2] In `Verborra/VerborraApp.swift` `MenuBarView`, delete the `#if DEBUG` "Simulate main-thread stall (3 s)" button and its comment (FR-046).
- [X] T121 [US2] In `Verborra/Views/AdvancedSettingsTab.swift`, inside `#if DEBUG`, add a last `Section(l10n.string("settings.advanced.developer"))` with a `Button(l10n.string("settings.advanced.simulateStall")) { Thread.sleep(forTimeInterval: 3) }` and a `.caption` `.secondary` `Text(l10n.string("settings.advanced.simulateStallHint"))` (FR-045).
- [X] T122 [P] [US2] In `Verborra/Localizable.xcstrings` add `settings.advanced.developer` en "Developer" / ru "Для разработчика"; `settings.advanced.simulateStall` en "Simulate main-thread stall (3 s)" / ru "Имитировать зависание главного потока (3 с)"; `settings.advanced.simulateStallHint` en "The app stops responding for 3 seconds and a stall warning is written to the log." / ru "Приложение не будет отвечать 3 секунды, а в журнал будет записано предупреждение о зависании." (FR-047).

---

## Phase 15b: User Story 4 amendment — dynamic button widths and a 200 pt window (Priority: P2)

**Added 2026-10-15.** Spec FR-064, US4 scenario 10; [research.md R34](./research.md) (amended).

**Goal** (T128): The microphone and output-language buttons size to their titles exactly like the prompt button: no fixed cap, shared room before the right-hand buttons, shortened with "…" only when the row runs out (microphone, then prompt, then language).

**Independent Test**: Quickstart 4.14 (T128), 4.15 (T130).

- [X] T128 [US4] **(Done 2026-10-15: `maxTitleWidth` removed from `ControlBarButtonLabel` and `controlBarMenu` (no other callers); all three menus use `truncatesTitle: true` with priorities mic 0, prompt 1, language 2. Lint clean, 0 warnings, 252 + 117 tests pass. Visual check: quickstart 4.14 in T127.)** In `Verborra/Views/ControlBarView.swift`, apply the prompt button's width rule to the microphone and output-language buttons (FR-064, research R34 amended): remove `maxTitleWidth: 180` from the microphone menu (keep `truncatesTitle: true`, `layoutPriority(0)`); give the language menu `truncatesTitle: true` (keep `layoutPriority(2)`, so it is the last to shrink). If `maxTitleWidth` then has no callers in `ControlBarButtonLabel`, remove it. Rebuild with 0 warnings, run the test suite, and lint the file. The visual check is quickstart 4.14 (owner, T127).

- [X] T129 [US4] **(Done, then reverted 2026-10-15 at the owner's request; replaced by T130.)** Window fits its content in the pre-recording stage (former FR-065 wording, research R35 "tried and reverted"): compact 189 pt window with `fitHeight`, growing upward for taller content.
- [X] T130 [US4] Fixed pre-recording window height of 200 pt (FR-065 final, research R35): revert T129 (`fitHeight`, `postProcessingMinHeight`, the content `minHeight`/`fixedSize` and `RecordingView.compactContentHeight` removed); `OverlayPanel.initialSize` = 800 × 200 in `Verborra/Views/OverlayPanel.swift` (the chat stage's minimum follows it as before). Content area 155 pt ≥ the tallest pre-recording view (154 pt measured). 0 warnings, lint clean, tests pass. Visual check: quickstart 4.15 (owner, T127).

---

## Phase 16: Polish for the 2026-10-15 follow-ups

- [X] T123 [P] Audit `Verborra/Localizable.xcstrings`: every key from T103, T112, T117 and T122 has `en` and `ru`, and `error.recordingStartFailed` uses positional `%1$@`/`%2$@` in both.
- [X] T124 [P] Update `README.md` (floating-window keys: 1 microphone, 2 output language, 3 prompt; menu titles; switching microphones while recording; prompt names up to 30 characters; the stall test is in Settings › Advanced in Debug builds) and the `Unreleased` entry of `CHANGELOG.md` (microphone switching during recording fixed, closing the window during a switch turns the microphone off, new bar order and menu titles, prompt name limit).
- [X] T125 Clean build and test: `xcodebuild clean test` (Debug) → 0 failures, 0 warnings; `xcodebuild build -configuration Release` → 0 warnings. Record the test counts in the baseline comment at the top of this file.
- [X] T126 Run SwiftLint on the files changed in Phases 12–15 together with T094 (blocked on SwiftLint being installed; see T003).
- [ ] T127 Manual (owner, together with T097): quickstart 2.6, 2.9–2.11 and 4.1–4.15 on the Release build; record pass/fail in `specs/015-reliability-shortcuts-models/verification/quickstart-results.md`.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup. **Blocks every story.** Part B (T011–T020) makes the test target compile, and US5–US8 build on the new catalog. T004 (new log categories) is needed by US1, US2 and US3; T006 is needed by US2 (watchdog WARN); T008 and T009 are needed by US3 (recorder, service) and US4 (Start/Stop hint).
- **User story phases (3–10)**, in priority and execution order: US5, US6, US7 (P1, model list), US1, US2 (P1, reliability), US4, US3 (P2), US8 (P3). All depend only on Foundational and are otherwise independent.
- **Phase 11**: T085–T089 edit the same service files as US5 and US6, so run them after Phases 3 and 4. T095–T096 (live probe and applying it) need US5–US8; T097–T098 need everything, including Phases 12–16.
- **Phases 12–16 (added 2026-10-15)**: build on the finished Phases 1–10. Order: Phase 12 (US9, P1) first, then Phase 13 (US4 amendment), Phase 14 (US10; T118 after T111), Phase 15 (stall test), Phase 16. Phases 12–15 are otherwise independent of each other.

### Cross-story file overlaps (sequence these if done in parallel)

| File | Touched by | Note |
|---|---|---|
| `Verborra/ViewModels/RecordingViewModel.swift` | Foundational (T006: `state` didSet), US2 (T053, T054, T058), US3 (T078), US4 (T063, T064, T110), US9 (T102, T105, T106) | Different functions. Merge carefully or do them one after another (US2 → US4 → US3). |
| `Verborra/Views/ControlBarView.swift` | US2 (T056), US4 (T065, T111, T128), US9 (T107), US10 (T118) | T111 → T118 → T128 (all edit the menus). |
| `Verborra/Views/OverlayContentView.swift`, `OverlayPanel.swift`, `RecordingView.swift` | US2 (T055), US4 (T065), US9 (T107), T129, T130 | T130 last. |
| `Verborra/VerborraApp.swift` | Foundational (T006), US1 (T037), US2 (T059), US3 (T074), US7 (T031) | Different sections of `AppDelegate`/`AppController`/`MenuBarView`; T031's migrator call goes right after the logging setup. |
| `Verborra/Models/RecordingState.swift` | US2 (T044), Phase 11 (T085, T087), US9 (T102) | Different cases; do T044 first. |
| `VerborraTests/Mocks/MockAudioCaptureService.swift` and `Verborra/Services/AudioCaptureService.swift` | US2 (T046, T050–T052), US9 (T099, T104) | T099 and T104 change the same `startRecording` signature; do them together. |
| `Verborra/Services/{Formatting,StreamingFormatting,Transcription}Service.swift` and their tests | Foundational (T017), US5 (T021–T024), US6 (T026–T027), Phase 11 (T088–T089) | Same files; in that order. |
| `VerborraTests/LLMModelTests.swift` | Foundational (T018), US8 (T084), Phase 11 (T096) | Same file. |
| `VerborraTests/ViewModels/DictationFlowTests.swift` | Foundational (T017), US2 (T061) | T017 changes a model case; T061 the `startRecording` signature. |
| `Verborra/Models/AppSettings.swift` | Foundational (T006: `logLevel` setter), US1 (T035), US3 (T077) | Different properties. |
| `VerborraTests/ViewModels/RecordingViewModelTests.swift` | US2 (T061), US4 (T062) | T061 updates call sites to the new `startRecording` signature; T062 adds cyclePrompt and key tests. Do T061 first. |
| `Verborra/Models/LogCategory.swift` | Foundational (T004) | Must be done before T036, T057, T072, T073, which log with the new categories. |
| `Verborra.xcodeproj/project.pbxproj` | T019, T030, T034, T043, T049, T061, T066, T081, T108, T119 | **Never edit it from two tasks at the same time.** |
| `Verborra/Localizable.xcstrings` | T015, T042, T060, T080, T083, T086, T103, T112, T117, T122 | Same file; [P] only relative to code tasks. |

### Within each story

Tests are written first and must fail before implementation. Then models, then services, then view models, then views, then project-file registration and the test run.

---

## Parallel Examples

### Foundational

```text
T004 LogCategory cases ║ T005 LogEntry WARN label ║ T008 GlobalShortcut model + formatter
then T006 DiagnosticLogger.warn → T007 WARN tests ; T009 store → T010 GlobalShortcut tests

Part B: T011 LLMModel ║ T013 STTModel ║ T015 strings → T012 → T014 → T016 → T017 → (T018 ║ T019) → T020
```

### User Stories 5–8

```text
US5: T021 ║ T022 → T023 ║ T024 → T025
US6: T026 → T027 → T028
US7: T029 → T030 → T031 → T032
US8: T082 ║ T083 ║ T084
```

### User Story 1

```text
T033 LoginItemServiceTests ║ T034 pbxproj signing ║ T042 strings
then T035 → T036 → (T037 ║ T038 ║ T040) → (T039 ║ T041) → T043
```

### User Story 2

```text
T044 RecordingState ║ T045 protocol change ║ T048 watchdog tests ║ T049 ObjC shim ║ T060 strings
then T046 mock → T047 start tests
then T050 (after T049) → T051 → T052 → T053 → T054 → (T055 ║ T056)
in parallel: T057 → T058 → T059
then T061
```

### User Story 4

```text
T062 tests
then T063 → T064 ║ T065 → T066 → T067
```

### Phases 12–15 (2026-10-15 follow-ups)

```text
US9:  T099 ║ T101 ║ T103 → T100 → T102 → T104 → T105 → T106 ║ T107 → T108
US4:  T109 ║ T112 → T110 → T111
US10: T113 ║ T117 → T114 → T115 → T116 ; T118 (after T111) → T119
US2:  T120 ║ T121 ║ T122
then Phase 16: T123 ║ T124 → T125 → (T126, T127 owner)
```

### User Story 3

```text
T068 FnTracking tests ║ T069 validator tests ║ T070 FnTracker ║ T071 ShortcutValidator ║ T080 strings
then T072 → T073 → T074 ; T075 → T076 ; T077 ║ T078 ║ T079 ; then T081
```

---

## Implementation Strategy

### Recommended order

Task IDs follow this order, so working through them from T001 to T130 is the recommended path (T128–T130 sit in Phase 15b, before Phase 16). T001–T093 are done; the 2026-10-15 follow-ups are T099–T127.

1. Phase 1 Setup, then Phase 2 Foundational (Part A and Part B). Part B fixes the test target, so every later test run is meaningful.
2. **US5–US7** (Phases 3–5, T021–T032): GPT-5 Nano and GPT-5 Mini stop working on 2026-12-11, and most users are on models that are removed.
3. US1 (login, Phase 6): small and low risk; fixes the most visible bug.
4. US2 (hangs, Phase 7): largest blast radius (audio pipeline); give it the most manual testing time before the release.
5. US4 (floating-window selectors, Phase 8), then US3 (recorder and Fn tap, the most new surface, Phase 9), then US8 (Phase 10).
6. Phase 11: model-unavailable error (T085–T089), documentation, then release validation (T094–T098).
7. **Follow-ups (2026-10-15)**: Phase 12 US9 microphone switching first (it fixes a P1 bug and a privacy problem: the microphone could turn on after the window closed), then Phase 13 (bar order and menu titles), Phase 14 (prompt names), Phase 15 (stall test), Phase 16. Release validation (T097, T098, T127) runs last, on the build with everything. The model-unavailable error can also be done right after US6 if you want it tested earlier; it doesn't depend on US1–US4.

**One release** (spec clarification): all ten stories ship together; nothing ships on its own. Aim to release before 2026-12-11, when GPT-5 Nano and GPT-5 Mini stop working. The 2-week soak (quickstart 2.8) runs after the release.

**US5 and US6 depend on US7 being in the same build**: without the migrator, users who inherited the old defaults are switched with no log entry, and saved removed values are never cleaned up.

### Notes

- Before US3 is merged, `GlobalShortcutStore` is only read (by the US4 hint and onboarding), and the old KeyboardShortcuts recorder still writes the shortcut. While US4 is merged and US3 isn't yet, the hint reflects the migrated value until the next launch after a shortcut change. That's only an in-branch state, since everything ships together, and US3 resolves it by making the store the single source of truth.
- Removing model enum cases is a hard compile break: keep T011–T020 in one commit.
- Never add a hidden fallback model (FR-040).
- Commit after each task or logical group, and keep `project.pbxproj` edits in their own commits where possible to make conflicts easier to resolve.
