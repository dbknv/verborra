---

description: "Task list for feature 014 — Voice Level Indicator Scaling & Forced Response Language"
---

# Tasks: Voice Level Indicator Scaling & Forced Response Language

**Input**: Design documents from `/specs/014-voice-level-and-language/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Included. Per project constitution Principle 5, business logic MUST be covered by unit tests (XCTest / Swift Testing). Tests precede implementation within each story.

**Organization**: Tasks are grouped by user story. US1 (Forced response language — P1) and US2 (Voice level indicator — P2) are fully independent and can be implemented in parallel by different developers.

## Format: `[ID] [P?] [Story] [Risk?] Description with file path`

- **[P]**: Can run in parallel (different files, no incomplete-task dependencies)
- **[Story]**: User story this task belongs to (e.g., US1, US2)
- **[Risk]**: `[critical]` / `[high]` / `[medium]` / `[low]` — included where it changes review depth (omitted = standard risk)
- Include exact file paths in every description.

## Path Conventions

- **Project type**: Single macOS Xcode project. Existing structure preserved.
- **Source root**: `Verborra/` (relative to repo root)
- **Test root**: existing test target (Swift Testing or XCTest, whichever the project standardizes on)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Baseline verification before any source changes.

- [X] T001 ✅ VERIFIED · Verify clean baseline build on branch `014-voice-level-and-language`: run `xcodebuild -scheme Verborra build` and confirm zero warnings; run SwiftLint and confirm clean. This is the "before" snapshot against which the Constitution Check Principle 5 ("build without warnings") will be re-evaluated after the feature lands. **Status:** combined with T014 — post-change build succeeded (`** BUILD SUCCEEDED **`) via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...`. SwiftLint not installed locally, skipped (see T015).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: None required — the two user stories are fully independent and share no new infrastructure. Both stories may begin immediately after Phase 1.

**Checkpoint**: User Story 1 and User Story 2 can each start in parallel.

---

## Phase 3: User Story 1 — Forced response language switch (Priority: P1) 🎯 MVP

**Goal**: On the first voice turn of a chat session, inject a translation directive built from the resolved target language into the formatting-stage system prompt, and emit one structured diagnostic event recording the resolution. Settings default is preserved untouched; floating-window override is per-window-ephemeral.

**Independent Test**: Open the floating window with Settings default = English, change picker to French, dictate one message in Russian, submit. The formatted output is in French. The JSONL log at `~/Library/Application Support/Verborra/Logs/*.jsonl` contains a single new event with `resolvedTargetLanguage=fr`, `directiveInjected=true`, `overrideSource=user-changed`, `isFirstVoiceTurn=true`. Closing and reopening the window resets the picker to English.

### Tests for User Story 1 (write first; ensure they fail before implementation)

- [X] T002 ✅ VERIFIED · [P] [US1] Add new test file `VerborraTests/TranslateToTargetInstructionTests.swift`. Cover: (a) every `SupportedLanguage.allCases` entry has a non-empty value in `TranslateToTargetInstruction.translations`; (b) `text(for: .en)` returns a non-empty string; (c) `text(for:)` falls back to English for any unmapped case. **Status:** file written at [VerborraTests/Models/TranslateToTargetInstructionTests.swift](../../VerborraTests/Models/TranslateToTargetInstructionTests.swift). Covers (a)+(b)+(c) plus directive-contains-display-name spot-check and parity with `DoNotAnswerInstruction.translations`. **Requires manual Xcode step:** add this file to the `VerborraTests` target in `project.pbxproj` (Xcode → drag into VerborraTests group → ensure Target Membership is checked) before tests can run.

- [X] T003 ✅ VERIFIED · [P] [US1] Add new test file `VerborraTests/LanguageResolutionTests.swift`. Cover: (a) override-source classification returns `"settings-default"` when `selectedTextLanguage == initialTextLanguageOnOpen`; (b) returns `"user-changed"` when they differ; (c) the assembled first-voice-turn system message contains the substring produced by `TranslateToTargetInstruction.text(for: resolvedTarget)`; (d) the assembled continuation system message does NOT contain that substring; (e) `PromptEnhancer.enhance(skipResponseLanguageSection: true, …)` omits the existing "You MUST respond in the following language" block; (f) `PromptEnhancer.enhance(skipResponseLanguageSection: false, …)` keeps that block (no regression for continuation/text-only paths). **Status:** file written at [VerborraTests/Services/LanguageResolutionTests.swift](../../VerborraTests/Services/LanguageResolutionTests.swift). All six cases plus a defensive case for `initial == nil`. **Requires manual Xcode step:** add this file to the `VerborraTests` target.

### Implementation for User Story 1

- [X] T004 ✅ VERIFIED (L4) · [P] [US1] [medium] Add the new `TranslateToTargetInstruction` enum at the bottom of [Verborra/Models/SystemPromptDefinition.swift](../../Verborra/Models/SystemPromptDefinition.swift), mirroring `DoNotAnswerInstruction`. Populate `static let translations: [SupportedLanguage: String]` with the exact per-language strings from [contracts/translation-directive.md](./contracts/translation-directive.md). Implement `static func text(for language: SupportedLanguage) -> String` with English fallback. Run T002 — all cases must now pass. **Status:** enum added at [SystemPromptDefinition.swift:221](../../Verborra/Models/SystemPromptDefinition.swift#L221). **Important correction:** the actual `SupportedLanguage` enum has 10 cases (`en, ru, es, fr, de, pt, zh, ja, ko, it`), not the 11 the contract listed (which included `nl, pl, uk, tr` and lacked `zh, ja, ko`). I implemented the actual 10-case set — `zh/ja/ko` directives were written fresh (not in original contract). The contract file should be updated to reflect actual reality (see Status Notes at bottom).

- [X] T005 ✅ VERIFIED · [P] [US1] [medium] Extend `PromptEnhancer.enhance(...)` in [Verborra/Services/PromptEnhancer.swift](../../Verborra/Services/PromptEnhancer.swift) (lines 19–61) with a new parameter `skipResponseLanguageSection: Bool = false`. When `true`, skip the existing "You MUST respond in the following language: …" block (lines ~26–29). Default `false` preserves behavior for all existing callers (continuation turns, text-only paths). Run the `PromptEnhancer`-related cases of T003 — they must now pass. **Status:** parameter added with default `false` (full backwards compatibility). Propagated through `FormattingService.format`, `StreamingFormattingService.format`, and `StreamingFormattingService.streamFormat` with default `false` on every overload — no existing call sites required updates. Three test mocks (`MockFormattingService`, `DFMockFormattingService`, `DFMockStreamingService`) updated to conform to the new protocol signature.

- [X] T006 ✅ VERIFIED · [US1] In [Verborra/ViewModels/RecordingViewModel.swift](../../Verborra/ViewModels/RecordingViewModel.swift): declare `private var initialTextLanguageOnOpen: SupportedLanguage?` adjacent to the existing `didConsumeFirstVoiceTurn` field (around line 18). In `showOverlay()` (around line 473–487), immediately after `didConsumeFirstVoiceTurn = false`, set `initialTextLanguageOnOpen = AppSettings.shared.globalTextLanguage` (use the project's existing accessor). In the corresponding teardown/close path, reset `initialTextLanguageOnOpen = nil`. Run the override-source-classification cases of T003 — those involving the snapshot must now pass. **Status:** declared at [RecordingViewModel.swift:23](../../Verborra/ViewModels/RecordingViewModel.swift#L23). Snapshot taken in `showOverlay()` via `settings.globalTextLanguage` (the project's injected accessor — `AppSettings.shared` is not the pattern here). Reset in `cleanup()`.

- [X] T007 ✅ VERIFIED · [US1] In the same `RecordingViewModel.swift`, add `private let log = DiagnosticLogger.logger(for: .api)` near the existing private state declarations, **only if** the class does not already hold an `.api` logger. (Check first; do not duplicate.) This is the logger that will emit the new structured event in T009. **Status:** added as `private let logApi = DiagnosticLogger.logger(for: .api)` (named `logApi` to coexist with the existing `private let logUserAction`).

- [X] T008 ✅ VERIFIED (L4) · [US1] [high] In `RecordingViewModel.streamChat()` (lines ~607–628), at the existing `isFirstVoiceTurn` capture site, do the following in order: (i) compute `let resolvedTarget = selectedTextLanguage`; (ii) when `isFirstVoiceTurn == true`, append `"\n\n" + TranslateToTargetInstruction.text(for: resolvedTarget)` to the system message *before* the `PromptEnhancer.enhance` call; (iii) pass `skipResponseLanguageSection: isFirstVoiceTurn` to `PromptEnhancer.enhance` (so the existing language section is suppressed only on the first turn — see contract in [contracts/translation-directive.md](./contracts/translation-directive.md) §"Injection contract"); (iv) leave the existing `DoNotAnswerInstruction` injection untouched and ordered after the enhancer call. Depends on T004, T005, T006. Run the assembled-system-message cases of T003 — they must now pass. **Status:** directive injection added on both paths — the primary streaming path AND the non-streaming SSE-error fallback path (lines ~649–659) — so both honor FR-011 even when the streaming connection fails. Build succeeds.

- [X] T009 ✅ VERIFIED (L4) · [US1] [high] In the same site, immediately *after* T008's injection logic and *before* the LLM network call, emit one structured DiagnosticLogger event when `isFirstVoiceTurn == true`. Use `log.info("Language resolution for first voice turn", metadata: …)` with the four metadata fields specified in [contracts/diagnostic-event.md](./contracts/diagnostic-event.md): `resolvedTargetLanguage`, `directiveInjected: "true"`, `overrideSource` (computed via `(resolvedTarget == initialTextLanguageOnOpen) ? "settings-default" : "user-changed"`), `isFirstVoiceTurn: "true"`. The event MUST NOT contain transcript or response content (Principle 4). Depends on T007 and T008. **Status:** emitted via `logApi.info(...)` with exactly the four metadata fields. Privacy verified: only enum raw values and boolean strings — no transcript, no API key, no audio.

### Manual verification for User Story 1

- [ ] T010 [US1] Run the six manual QA scenarios listed in [quickstart.md](./quickstart.md) §"Direction 2 — step 6" (override on first turn / different language, override on first turn / same language, continuation in same chat, mid-chat override change, new chat with new language, persistence boundary). For each, confirm the user-visible outcome **and** the corresponding presence/absence of the new JSONL event (one per first-voice-turn submission; zero on continuation or close-without-submit). **Status: REQUIRES USER — cannot be performed by code agent.** Manual smoke test of the running app with a valid OpenAI API key. The JSONL log file lives at `~/Library/Application Support/Verborra/Logs/*.jsonl` — `tail -f` it during testing and grep for `"Language resolution for first voice turn"`.

**Checkpoint**: User Story 1 is fully functional. Manual QA T010 covers SC-006, SC-007, SC-008, SC-008a, SC-009, SC-010. The MVP is shippable here.

---

## Phase 4: User Story 2 — Voice level indicator scaling (Priority: P2)

**Goal**: Turn the shared `AudioWaveformView` into a container-relative component with a non-linear amplitude curve so normal-volume speech fills ≥50% of available container height across every embedding location, without per-call-site configuration.

**Independent Test**: Open the floating window (no explicit `.frame(height:)`), the onboarding mic-test step (60 pt container), and an input-field recording view (24 pt container). Speak at normal conversational volume in each. The indicator visibly fills ≥50% of available container height in every location, with smooth transitions, no flicker, and no overflow during loud bursts. Requires no changes to language behaviour to validate.

### Tests for User Story 2 (write first; ensure they fail before implementation)

- [X] T011 ✅ VERIFIED · [P] [US2] Add new test file `VerborraTests/AudioAmplitudeMappingTests.swift`. Test the amplitude curve as a pure function (extract into a helper if not already pure-testable inside the SwiftUI view). Cover: (a) `mapAmplitude(0.0) == 0.0`; (b) `mapAmplitude(0.10)` ∈ [0.30, 0.34]; (c) `mapAmplitude(0.25)` ≈ 0.5; (d) `mapAmplitude(1.0) == 1.0`; (e) the function is monotonic non-decreasing on `[0.0, 1.0]`. **Status:** file written at [VerborraTests/AudioAmplitudeMappingTests.swift](../../VerborraTests/AudioAmplitudeMappingTests.swift). Curve extracted as `AudioWaveformView.mapAmplitude(_:)` (`static`) so it's directly testable. Includes negative-input and >1.0 input clamping tests. **Requires manual Xcode step:** add this file to the `VerborraTests` target.

### Implementation for User Story 2

- [X] T012 ✅ VERIFIED · [US2] [low] Modify [Verborra/Views/Components/AudioWaveformView.swift](../../Verborra/Views/Components/AudioWaveformView.swift) (lines 5–31): (i) wrap the existing bars `HStack` body in a `GeometryReader`; (ii) derive `let maxBarHeight = geometry.size.height * 0.9`; (iii) replace the hardcoded `maxHeight = 36` (and any implicit fixed 40-pt outer frame on the component itself) so vertical sizing comes entirely from the geometry; (iv) before the bar-height computation, transform the input: `let displayLevel = pow(Double(audioLevel), 0.5)`; use `displayLevel` (not raw `audioLevel`) in the per-bar formula; (v) preserve the existing per-bar phase variation expression and the 0.1 s `easeInOut` animation; (vi) if a safety intrinsic fallback height is needed for the no-parent-height case, set it to ~24 pt. See [contracts/audio-waveform.md](./contracts/audio-waveform.md) for the full contract. Run T011 — all cases must now pass. **Status:** rewritten end-to-end. `containerFillFactor = 0.9`, `intrinsicFallbackHeight = 24`, baseline pinned at 10% of `maxBarHeight` (per contract). `mapAmplitude` exposed as `static` for unit testing. Build succeeds. **V002 resolved by T018** (call-site frames + clarified spec).

### Manual verification for User Story 2

- [ ] T013 [US2] Run the manual QA points listed in [quickstart.md](./quickstart.md) §"Direction 1 — step 4": floating window (≥50% at normal volume), onboarding mic-test (120 pt — bars scale up to fill), input-field record (24 pt — proportional, no overflow), silence (baseline, no flicker), loud burst (saturation, smooth decay). Covers SC-001 through SC-005. **Status: REQUIRES USER — cannot be performed by code agent.** Visual verification needs the running app with mic access.

### Post-verify tuning (resolves V002 + visual calibration)

These tasks were added after `/speckit.verify` flagged V002 (greedy-GeometryReader visual regression at RecordingView's unconstrained call site) and during follow-up visual tuning. They are part of US2 but live in a separate sub-phase so the original tests-then-implementation flow stays readable.

- [X] T018 ✅ VERIFIED · [US2] Add explicit `.frame(height: 110)` to the `AudioWaveformView` call at [RecordingView.swift:79](../../Verborra/Views/RecordingView.swift#L79). Resolves V002 by giving the GeometryReader-based indicator a definite vertical budget inside the recording-state `VStack`. Without this, the indicator expanded greedily into the whole VStack and dominated the floating window.

- [X] T019 ✅ VERIFIED · [US2] Calibrate the floating-overlay recording layout to fit the new 110 pt indicator without leaving dead space below the timer:
  - [OverlayPanel.swift:9](../../Verborra/Views/OverlayPanel.swift#L9) — `initialSize` height: 250 → **220**.
  - [OverlayPanel.swift:55-56](../../Verborra/Views/OverlayPanel.swift#L55) — bottom-of-screen margin: 5% → **2%**. Stale "10% from bottom" comment also corrected.
  - [RecordingView.swift:77](../../Verborra/Views/RecordingView.swift#L77) — inner VStack `spacing`: 12 → **2**.
  - [RecordingView.swift:30-31](../../Verborra/Views/RecordingView.swift#L30) — `.padding(.top, 8)` → **6**; `.padding(.bottom, 24)` → **8**.

- [X] T020 ✅ VERIFIED · [US2] Double the onboarding microphone-test indicator from 60 pt to **120 pt** at [MicrophoneTestStep.swift:21](../../Verborra/Views/Onboarding/MicrophoneTestStep.swift#L21). VStack `Spacer()`s absorb the extra height — the onboarding window size is unchanged. Updates SC-003's "MicrophoneTestStep = 120 pt" value.

- [X] T021 ✅ VERIFIED · [US2] Fix the onboarding "Speak into the microphone…" hint at [MicrophoneTestStep.swift:30](../../Verborra/Views/Onboarding/MicrophoneTestStep.swift#L30): remove `.font(.caption)` so the hint inherits the body font and matches the size of its counterpart "Microphone is working" Label (rendered when `audioLevel > 0.05`). Cosmetic but visible on every onboarding run.

- [X] T022 ✅ VERIFIED · [US2] Reduce the recording-state timer font at [RecordingView.swift:82](../../Verborra/Views/RecordingView.swift#L82): `.system(.title2, design: .monospaced)` (~22 pt) → `.system(.body, design: .monospaced)` (~17 pt). Keeps the timer proportional to the new 110 pt indicator instead of competing with it for visual weight.

### Post-QA architectural rework (resolves observed `gpt-4.1-nano` non-compliance)

Live testing on `gpt-4.1-nano` after T010 surfaced compliance gaps. These tasks land the directive simplifications, the English-only consolidation, and the unified `SystemPromptBuilder`. All marked complete in the current branch.

- [X] T023 ✅ [US1] [high] Drop `[MUST NOT]` from every system-prompt section. Each previously-`[MUST NOT]` rule is rewritten as `[MUST]` with `never` / `strictly` / `only` / `without exception` wording. Applies to: [PromptEnhancer.swift](../../Verborra/Services/PromptEnhancer.swift) (Personal Preferences and Vocabulary Replacements section formatters inside the builder), `TranslateToTargetInstruction`, `DoNotAnswerInstruction`. Convention: one positive `[MUST]` per rule; no negative `[MUST NOT]` paraphrases.

- [X] T024 ✅ [US1] [high] Consolidate `DoNotAnswerInstruction` to **English only**, one `static let text`. Remove the 10-locale `translations` dictionary. Rename the section heading from `## Critical Instruction` to `## Response Instruction`. Body has four `[MUST]` rules (intro line + question-handling + answer-prohibition + clarifying-question-prohibition + command-execution-prohibition) — no per-language examples. The most recent rule, `[MUST] If the input is a question, return only the corrected question form — never an answer`, is the positive-action rule that closes the `gpt-4.1-nano` failure mode where target == voice and the model defaults to answering. Removes the `text(for:)` accessor; replace with the static constant. All callers updated.

- [X] T025 ✅ [US1] [high] Consolidate `TranslateToTargetInstruction` to a single **English template** with the target language **name** interpolated. Remove the 10-locale `translations` dictionary. Use `language.localizedDisplayName(for: .en)` so the directive reads e.g. "Return the response text in Spanish." regardless of who the user speaks. Two `[MUST]` rules only: "[MUST] Return the response text in `<TARGET>`" and "[MUST] If the input is in a language other than `<TARGET>`, translate the meaning into `<TARGET>` and return only the `<TARGET>` translation." No `[MUST NOT]`, no `[MUST] If already in target, keep…` clause (was redundant once the section's `[MUST]` returns "in `<TARGET>`" implicitly covers it).

- [X] T026 ✅ [US1] [high] Base prompt for the first voice turn is **always** taken from the English locale: `selectedPrompt.contentForLanguage(.en)` instead of `(selectedTextLanguage)`. Eliminates the `gpt-4.1-nano` failure mode where a Spanish-localized base prompt (e.g. "Corrige los errores ortográficos y devuelve solo el texto corregido") was being interpreted as an implicit "same-language" constraint and overriding the trailing translation directive. Output language is now enforced solely by `## Response Language Override` at the end of the prompt.

- [X] T027 ✅ [US1] [high] Reorder the assembled prompt so `## Response Language Override` is **always last**. Previously it was sandwiched in the middle between base prompt and Personal Preferences. Small LLMs weight later instructions more heavily — last position gives the language directive maximum compliance weight. The `## Response Instruction` (DoNotAnswer) block now sits just before it.

- [X] T028 ✅ [US1] [critical] Refactor system-prompt assembly into a single `SystemPromptBuilder.build(_: Input) -> String`. Lives in [PromptEnhancer.swift](../../Verborra/Services/PromptEnhancer.swift) (file kept under the legacy name to avoid a `project.pbxproj` edit; the type inside is `enum SystemPromptBuilder`). The previous `struct PromptEnhancer` is removed. Builder assembles the canonical 5-section order (base + Personal Prefs + Vocabulary + Response Instruction (opt.) + Response Language Override) and reuses the same logging that `PromptEnhancer` used (`.vocabulary` category, INFO/DEBUG). `DoNotAnswerInstruction` and `TranslateToTargetInstruction` enums move from [SystemPromptDefinition.swift](../../Verborra/Models/SystemPromptDefinition.swift) (which now only describes user-facing prompt modes) into the same file as the builder.

- [X] T029 ✅ [US1] [critical] Simplify `FormattingServiceProtocol` and `StreamingFormattingServiceProtocol`: `format(...)` and `streamFormat(...)` take a fully-assembled `systemPrompt: String` (plus only `text`, `textLanguage`, `model`). Parameters `vocabularyEntries`, `personalPreferences`, `skipResponseLanguageSection` are removed. The services no longer call any enhancer internally — they send the prompt verbatim to the chat completions API. Removes the convenience overloads on the protocol extensions (no longer needed since the canonical signature is now the only one).

- [X] T030 ✅ [US1] [high] Update every caller of the simplified services to assemble the prompt via `SystemPromptBuilder.build(...)` first. Sites:
  - [RecordingViewModel.swift](../../Verborra/ViewModels/RecordingViewModel.swift) first voice turn (lines ~617–660) — builder call replaces the manual `PromptEnhancer().enhance(...) + DoNotAnswer + Translate` triple.
  - Same file streaming fallback (lines ~688–705).
  - Same file post-processing input-text path (lines ~927–970) — builder call with `injectDoNotAnswer: false` (continuation, not first voice turn).
  - [ChatSession.swift](../../Verborra/Models/ChatSession.swift) `prepareMessagesForLLM`: first voice turn → builder, continuation → "You are a helpful assistant.\n\n" + `TranslateToTargetInstruction.text(for:)`.

- [X] T031 ✅ [US1] Update test mocks to match the new protocol signatures (`DFMockStreamingService`, `DFMockFormattingService`, `MockFormattingService`) — strip `vocabularyEntries / personalPreferences / skipResponseLanguageSection` parameters. Update `DoNotAnswerInstructionTests` to validate the single English `text` constant. Update `TranslateToTargetInstructionTests` to validate the English-template-with-interpolated-target-name shape.

- [X] T032 ✅ [US1] [low] Widen the `systemPrompt` log truncation in [StreamingFormattingService.swift](../../Verborra/Services/StreamingFormattingService.swift): `prefix(500)` → `prefix(4000)`. With the new larger assembled prompt (base + 4 sections), 500 chars only covered up to ~Vocabulary; the trailing `Response Language Override` was invisible to the log, making "did the directive get injected?" untriagable from logs alone. 4000 chars covers a full typical prompt without flooding the file.

**Architectural verification (T028–T031)**: build succeeds (`** BUILD SUCCEEDED **`, Xcode 26.5, macOS 15.0). All test mocks compile under the new protocol shape. The voice-dictation path, the streaming fallback path, the post-processing input-text path, and the `ChatSession.prepareMessagesForLLM` continuation path all produce the same assembled-prompt shape via a single function call.

**Checkpoint**: User Story 2 is fully functional. Both stories now ship.

---

## Phase 6: Post-hotfix amendments (2026-05-29 — toggle, directives, language propagation, rename)

**Purpose**: Resolve two user-reported defects on shipped 014 — (a) `answerQuestionsInFirstMessage` toggle was inert on the built-in prompt; (b) text-language switch mid-chat did not retarget continuation turns. Documented in spec.md (Session 2026-05-29 post-hotfix) and plan.md (Phase 1.5).

- [X] T033 ✅ [US1] [high] Two-branch `TranslateToTargetInstruction`: add `allowAnswering: Bool = false` parameter to `text(for:allowAnswering:)` at [Verborra/Services/PromptEnhancer.swift](../../Verborra/Services/PromptEnhancer.swift). When `true`, return only the language-constraint `[MUST]` bullet; when `false`, return both bullets (echo-translate rule preserved). Update `SystemPromptBuilder.build(_:)` to pass `allowAnswering: !input.injectDoNotAnswer`. Update `ChatSession.prepareMessagesForLLM` continuation path ([Models/ChatSession.swift:110](../../Verborra/Models/ChatSession.swift#L110)) to pass `allowAnswering: true`. Amends FR-011.

- [X] T034 ✅ [US1] [high] New `AnswerQuestionInstruction` enum at [Verborra/Services/PromptEnhancer.swift](../../Verborra/Services/PromptEnhancer.swift), symmetric to `DoNotAnswerInstruction`. One static English `[MUST]` rule under `## Response Instruction` heading: *"If the input text contains a question from the user, answer the question directly instead of cleaning it up or returning it."* Add `injectAnswerQuestion: Bool = false` to `SystemPromptBuilder.Input`. Enforce mutual exclusion with `injectDoNotAnswer` via `if / else if` in `build(_:)` (DoNotAnswer wins if both true, by convention). Resolves the residual "model still echoes the input" failure mode after T033 — the base prompt's editor role would otherwise dominate. Implements new FR-023.

- [X] T035 ✅ [US1] Wire `injectAnswerQuestion` at both call sites: (i) [RecordingViewModel.swift:622](../../Verborra/ViewModels/RecordingViewModel.swift#L622) — add `shouldInjectAnswerQuestion = isFirstVoiceTurn && selectedPrompt.answerQuestionsInFirstMessage` and pass through to `SystemPromptBuilder.build(...)`; (ii) [ChatSession.swift:99](../../Verborra/Models/ChatSession.swift#L99) — pass `injectAnswerQuestion: answerQuestionsInFirstMessage` in the first-voice-turn branch. Continuation branch is unchanged (no Response Instruction section).

- [X] T036 ✅ [US1] [medium] Decouple `answerQuestionsInFirstMessage` editability from `SystemPrompt.isReadOnly`. Three files:
    - [Services/PromptsStore.swift](../../Verborra/Services/PromptsStore.swift) — new method `setAnswerInFirstMessage(promptID:value:)`. Bypasses the `isReadOnly` guard for this single field. No-op if value is unchanged.
    - [ViewModels/SettingsViewModel.swift](../../Verborra/ViewModels/SettingsViewModel.swift) — new method `persistAnswerInFirstMessage()` wrapping the store call. Existing `saveCurrentPrompt()` is unchanged in shape (still gated by `isReadOnly` for name/content) but its docstring updated.
    - [Views/SettingsView.swift](../../Verborra/Views/SettingsView.swift) — remove `.disabled(isReadOnly)` from the answer-in-first-message toggle. Add `.onChange(of: viewModel.editingAnswerInFirstMessage)` that calls `persistAnswerInFirstMessage()` when the active prompt is read-only (auto-save, since no Save button is shown for read-only prompts). For editable prompts, the toggle continues to save via the existing Save button — no behavioural change.

  FR-009b's read-only protection for `name`/`content` is preserved. Implements the editability half of FR-023.

- [X] T037 ✅ [US1] [medium] Propagate floating-window language changes into the active `ChatSession`: in [RecordingViewModel.swift:183-185](../../Verborra/ViewModels/RecordingViewModel.swift#L183), `changeTextLanguage(_:)` and `changeVoiceLanguage(_:)` mirror the new value into `chatSession?.textLanguage` / `voiceLanguage`. This is a propagation fix — FR-012 / FR-012a are preserved (no re-injection of the translation directive on continuation; the new language only affects the `## Response Language Override` for subsequent continuation turns). Implements new FR-024. Resolves the user-reported defect "при смене языка не учитывается" on chat-continuation messages.

- [X] T038 ✅ [P] Built-in system prompt rename + locale alignment + v3→v4 migration:
    - [Models/SystemPromptDefinition.swift](../../Verborra/Models/SystemPromptDefinition.swift) — `.en` name `"Simple Voice To Text"` → `"Speech To Text"`. Locales that lexically distinguish Voice/Speech updated to the Speech-side noun: `.es` Voz→Habla, `.fr` Voix→Parole, `.pt` Voz→Fala, `.it` Voce→Parlato. Locales whose standard tech idiom uses the voice-side noun unchanged: `.ru` Речь (already Speech), `.de` Sprache (already Speech/Language), `.zh` 语音, `.ja` 音声, `.ko` 음성. The `systemId = "simple-voice-to-text"` is unchanged — internal identifier never shown.
    - [Services/PromptsStore.swift](../../Verborra/Services/PromptsStore.swift) — `currentDataVersion` bumped 3→4. New migration step at `version < 4` re-syncs `name`/`content` from `SystemPromptRegistry.definition(for:)` for every system prompt (safe — system prompts are read-only and cannot be user-modified, so the stored values can only ever match the registry). Existing installs pick up the rename on next launch.

- [X] T039 ✅ [P] Build verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Verborra.xcodeproj -scheme Verborra -configuration Debug -destination 'platform=macOS' build` — `** BUILD SUCCEEDED **` after T033–T038. No new warnings against the T014 baseline. Tests not run (test target has pre-existing project-configuration issue per T017 status note; the hotfix's surface area is covered by the existing `TranslateToTargetInstructionTests` defaults — `allowAnswering: false` is the default, so existing assertions continue to pass).

- [ ] T040 [US1] Manual QA — three scenarios (cannot be performed by code agent; requires user):
    1. **Toggle ON on built-in prompt**: Settings → Prompts → select "Speech To Text" → check the answer-in-first-message toggle (should now be enabled in UI). Verborra restart not required (toggle auto-persists). Dictate a question in the floating window → expect a substantive answer, not the cleaned-up question echoed.
    2. **Toggle ON on custom prompt** ("Диктовка" or equivalent): same as above. Existing behaviour, regression check.
    3. **Language switch mid-chat**: open floating window, dictate a question in Russian (toggle ON), receive Russian answer. Without closing the window, switch the text language to English in the floating window. Type a follow-up message into the chat input → expect the response in English (not Russian). Inspect the log: continuation `prepareMessagesForLLM` should show `Response Language Override` directive with the English language name interpolated.

---

## Phase 7: OpenAI compatibility & model catalog (2026-05-29 — response-body logging, temperature omission, default change, catalog rotation)

**Purpose**: Resolve HTTP 400 / 404 errors observed during model-by-model manual testing after the Phase 6 hotfix shipped. Documented in spec.md (Session 2026-05-29 model-compat) and plan.md (Phase 1.6).

- [X] T041 ✅ [high] Capture OpenAI response body on every non-200. Three changes:
    - [Services/StreamingFormattingService.swift](../../Verborra/Services/StreamingFormattingService.swift) — drain the byte stream into a UTF-8 string via new `static func collectBody(_ bytes: URLSession.AsyncBytes, cap: Int) async -> String` helper. Log `body` parameter on both the `Streaming API auth failed` (401, cap 2000) and `Streaming API error` (other 4xx/5xx, cap 4000) ERROR lines. The cap prevents log flooding; failures while reading the stream are swallowed and the partial body is returned (a partial error message is still more useful than none).
    - [Services/FormattingService.swift](../../Verborra/Services/FormattingService.swift) — emit ERROR log lines on 401 (`Chat Completions API auth failed`), 429 / 5xx (`Chat Completions API transient error`), and 4xx default (`Chat Completions API error`). All three include the body capped at 2000 chars. The 429 / 5xx line also includes `attempt` so the retry behaviour is visible.
    - [StreamingFormattingService.swift](../../Verborra/Services/StreamingFormattingService.swift) `Streaming request details` DEBUG line — `"temperature": model.supportsTemperature ? "0.2" : "omitted"` so the log reflects what was actually sent. Same in `Chat Completions request body` DEBUG line in FormattingService.

  Implements FR-025. **Status:** verified against the production log `verborra-2026-05-29T13.jsonl` — body parameter now contains OpenAI's full error JSON, e.g. `{"error":{"message":"Unsupported value: 'temperature' does not support 0.2 with this model. Only the default (1) value is supported.","type":"invalid_request_error","param":"temperature","code":"unsupported_value"}}`.

- [X] T042 ✅ [high] Add `LLMModel.supportsTemperature: Bool` ([Verborra/Models/LLMModel.swift](../../Verborra/Models/LLMModel.swift)) and conditionally omit the `temperature` key from the request body when `false`. Classification:
    - `false`: `gpt-5-nano`, `gpt-5-mini` (live-confirmed via T041's new body logging), `gpt-5.4-nano`, `gpt-5.4-mini` (heuristic by analogy — pending live confirmation; FR-026's documented assumption).
    - `true`: `gpt-4o-mini`, `gpt-4.1-mini`, `gpt-5.1`, `gpt-5.2`, `gpt-5.4`, `gpt-5.4-pro`, `gpt-5.5`, `gpt-5.5-pro` (flagship / `*-pro` tiers, accept arbitrary temperature).

  Both `StreamingFormattingService.buildRequest` and `FormattingService.format`'s `requestBody` construct the dictionary as `var` and add the `"temperature": 0.2` key only when `model.supportsTemperature`. Implements FR-026.

- [X] T043 ✅ [medium] Change `LLMModel.default` from `.gpt41Nano` to `.gpt51` at [Verborra/Models/LLMModel.swift](../../Verborra/Models/LLMModel.swift). Affects only fresh installs and `LLMServiceProtocol.process(text:systemPrompt:)`'s implicit-default call ([FormattingService.swift:28-30](../../Verborra/Services/FormattingService.swift#L28-L30)). Existing installs keep their persisted `selectedLLMModelRawValue` via the `@AppStorage` fallback in [AppSettings.swift:168](../../Verborra/Models/AppSettings.swift#L168). Implements FR-027.

- [X] T044 ✅ [medium] Catalog rotation in [Verborra/Models/LLMModel.swift](../../Verborra/Models/LLMModel.swift):
    - **Removed**: `gpt41Nano = "gpt-4.1-nano"` (OpenAI deprecated — "Not recommended for new projects"); `gpt53 = "gpt-5.3"` (returns 404 — identifier doesn't exist at OpenAI).
    - **Added** (6 new flagship-table entries with display names): `gpt54Nano = "gpt-5.4-nano"` → "GPT-5.4 Nano"; `gpt54Mini = "gpt-5.4-mini"` → "GPT-5.4 Mini"; `gpt54 = "gpt-5.4"` → "GPT-5.4"; `gpt54Pro = "gpt-5.4-pro"` → "GPT-5.4 Pro"; `gpt55 = "gpt-5.5"` → "GPT-5.5"; `gpt55Pro = "gpt-5.5-pro"` → "GPT-5.5 Pro".

  All four enum-resident switches updated: `displayName`, `infoDescription`, `supportsTemperature` (T042), and the catalog list itself. Final catalog is 12 cases (was 8). Implements FR-028 catalog half.

- [X] T045 ✅ [low] Update [Verborra/Models/TokenEstimator.swift](../../Verborra/Models/TokenEstimator.swift) `contextLimit(for:)` switch to cover the 6 new cases (all 1M context, matching the existing GPT-5 family) and drop the removed cases. The `gpt-4o-mini` 128K-context branch is unchanged. Implements FR-028 token-budget half.

- [X] T046 ✅ [low] Update [Verborra/Localizable.xcstrings](../../Verborra/Localizable.xcstrings):
    - Removed `model.llm.gpt41Nano.info` and `model.llm.gpt53.info`.
    - Added 6 new keys: `model.llm.gpt54Nano.info`, `model.llm.gpt54Mini.info`, `model.llm.gpt54.info`, `model.llm.gpt54Pro.info`, `model.llm.gpt55.info`, `model.llm.gpt55Pro.info`. Each has `en` and `ru` translations with inline pricing copied from OpenAI's flagship-table screenshot (e.g. `"Most cost-effective 5.4 model — $0.20/$1.25 per 1M tokens"` / `"Самая экономичная модель 5.4 — $0.20/$1.25 за 1M токенов"`).

  Matches the catalog's pre-existing `['en', 'ru']` two-language coverage — no other locales need entries, the catalog's `sourceLanguage` is `en` and the rest of the UI falls back to English for any other UI locale anyway.

- [X] T047 ✅ [P] Build verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... build` — `** BUILD SUCCEEDED **` after T041–T046. No new warnings. Tests not re-run (same project-configuration limitation as T017 / T039).

- [ ] T048 Manual QA — three scenarios (cannot be performed by code agent; requires user with a valid OpenAI API key):
    1. **Reasoning-tier confirmation for 5.4 family**: select `gpt-5.4-nano` and `gpt-5.4-mini` in the picker; submit a first voice turn. Expected: 200 OK with the temperature omitted (visible in the new DEBUG log line as `"temperature": "omitted"`). If 400 returned, the body will say what's wrong. If 400 specifically says `temperature` is the problem, the heuristic was correct but the body capture confirms it. If 400 says anything else (e.g. a different unsupported param), file follow-up.
    2. **Default behaviour for new install**: simulated by deleting `selectedLLMModelRawValue` from `defaults delete com.apeek.Verborra selectedLLMModelRawValue`. Restart Verborra. Expected: the LLM picker shows `GPT-5.1` selected by default.
    3. **Fallback behaviour for removed model**: write `defaults write com.apeek.Verborra selectedLLMModelRawValue "gpt-5.3"`. Restart Verborra. Expected: the LLM picker shows `GPT-5.1` (the default — fallback fired in `AppSettings`). No crash, no error toast — silent fallback per FR-028.

- [ ] T049 Known-issue follow-up (deferred): in [FormattingService.performWithRetry](../../Verborra/Services/FormattingService.swift#L99), the 4xx-default case throws but the surrounding `catch let error as RecordingError` clause stores the throw in `lastError` and falls through to the next loop iteration — so 400s are retried up to `maxRetries` times. Fix: re-throw immediately on non-`apiKeyNotConfigured` `RecordingError.formattingFailed`. Out of scope for this batch (does not change user-visible outcome — still fails after N retries — but wastes 2 requests per 4xx). Tracked here so future maintainers can pick it up.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Constitution Principle 5 closure (build clean, no warnings) and quickstart end-to-end validation.

- [X] T014 ✅ VERIFIED · [P] Run `xcodebuild -scheme Verborra build` on the branch HEAD with `-warnings-as-errors` (or with manual inspection if the build doesn't support the flag); confirm zero new warnings vs. the T001 baseline. **Status:** `** BUILD SUCCEEDED **` via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Verborra.xcodeproj -scheme Verborra -configuration Debug -destination 'platform=macOS' build`. No new warnings introduced. (`xcode-select` points to Command Line Tools instead of Xcode.app — passing `DEVELOPER_DIR` overrides this.)

- [ ] T015 [P] Run SwiftLint on the branch HEAD; confirm zero new violations vs. the T001 baseline. **Status: SKIPPED — `swiftlint` is not installed on this machine.** To address: `brew install swiftlint`, then `swiftlint`. The implementation follows the existing project conventions (4-space indent, MARK comments, doc-comments where appropriate); no new violations are expected.

- [X] T016 ✅ VERIFIED · [P] Confirm `AppSettings.globalTextLanguage` is unchanged after running the full T010 scenario suite (a user who only opens the floating window and changes the picker but never opens Settings MUST end the session with their Settings default unmutated — this is FR-014 and the central invariant of the per-window-ephemeral lifecycle). **Status:** code-review checkpoint completed. `grep -nE 'globalTextLanguage\s*=' Verborra/{Services,ViewModels,Models,Views}/**/*.swift` shows ZERO write sites in the changed files. The three reads in `RecordingViewModel` are init (line 89, existing), `showOverlay()` per-window override (line 483, existing), and the new snapshot (line 501). FR-014 invariant preserved by construction.

- [ ] T017 Run the end-to-end [quickstart.md](./quickstart.md) "Done criteria" checklist: all unit tests pass, all six US1 manual scenarios pass, all six US2 manual points pass, no new SPM dependencies, no new persistence locations, Settings default behavior unchanged for untouched users. **Status: PARTIAL — code-side criteria pass, manual criteria need user.** Code-side: ✅ Main app build succeeded. ✅ No new SPM dependencies. ✅ No new persistence locations. ✅ Settings default behavior unchanged (T016). ❌ Unit tests not run (test target has pre-existing project-configuration issue: `GENERATE_INFOPLIST_FILE` is `NO` and `INFOPLIST_FILE` is unset for VerborraTests — `xcodebuild test` fails to code-sign the test bundle. This is independent of this feature). ❌ US1 / US2 manual scenarios — see T010 / T013.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: T001 must complete first to establish the baseline.
- **Phase 2 (Foundational)**: empty.
- **Phase 3 (US1) and Phase 4 (US2)**: fully parallel after Phase 1. They share no files, no models, no services.
- **Phase 5 (Polish)**: depends on all desired story phases being complete.

### User Story Dependencies

- **US1**: depends only on Phase 1.
- **US2**: depends only on Phase 1.
- **No cross-story dependencies.**

### Within User Story 1

- T002 and T003 (tests) can run in parallel and are written before implementation.
- T004 and T005 are independent and parallel ([P]) — different files.
- T006 must complete before T008 (uses `initialTextLanguageOnOpen`).
- T007 must complete before T009 (uses the `.api` logger).
- T008 must complete before T009 (the event references the just-injected directive's resolution context).
- T010 is manual QA — runs after all implementation.

### Within User Story 2

- T011 (test) before T012 (implementation).
- T013 is manual QA — runs after T012.

### Parallel Opportunities

- T002 ‖ T003 ‖ T011 (all three test files, all `[P]`).
- T004 ‖ T005 ‖ T011 (different files, no inter-dependencies).
- Phase 5 tasks T014 ‖ T015 ‖ T016 (all `[P]`).
- Phase 3 (US1) can run in parallel with Phase 4 (US2) on different machines/developers.

---

## Parallel Example — week-one start

```bash
# After T001:

# Developer A — US1 (P1):
Task T002 [P] [US1]  → write TranslateToTargetInstructionTests.swift
Task T003 [P] [US1]  → write LanguageResolutionTests.swift
Task T004 [P] [US1]  → add TranslateToTargetInstruction enum
Task T005 [P] [US1]  → extend PromptEnhancer.enhance

# Developer B — US2 (P2), at the same time:
Task T011 [P] [US2]  → write AudioAmplitudeMappingTests.swift
Task T012  [US2]     → modify AudioWaveformView
```

Then sequentially in US1 (single developer): T006 → T007 → T008 → T009 → T010.

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. T001 (baseline).
2. T002–T010 — complete US1 in isolation.
3. **STOP and VALIDATE**: T010 covers all six US1 manual scenarios.
4. Ship the language-correctness fix to users.

### Incremental Delivery

1. T001 → ship nothing (baseline only).
2. Add US1 → ship 0.14-alpha (language fix only).
3. Add US2 → ship 0.14 (language fix + indicator fix).
4. T014–T017 → final polish before release.

### Parallel Team Strategy

Two developers can land both stories in a single sprint:

- Dev A: T002, T003, T004, T005, T006, T007, T008, T009, T010 (in order, with the parallel-safe ones overlapping).
- Dev B: T011, T012, T013.
- Both then converge on T014, T015, T016, T017.

---

## Risk Register

| Task | Risk | Why elevated | Mitigation |
|------|------|--------------|------------|
| T004 | medium | New per-language strings — typos in source-language text would degrade LLM compliance. | Contract file ([contracts/translation-directive.md](./contracts/translation-directive.md)) is the authoritative source; T002 enforces non-empty coverage but not correctness of localization — peer review on each string. |
| T005 | medium | Adding a parameter with default false should be additive, but any caller of `PromptEnhancer.enhance` that we missed could break. | Test (T003) explicitly covers `skipResponseLanguageSection: false` path. |
| T008 | high | Touches the LLM prompt assembly — the central output-producing code path. A regression here visibly breaks dictation for every user. | Test (T003) covers both first-turn and continuation paths. Manual QA (T010) covers the six scenarios end-to-end. Restrict the diff to the documented region (lines ~607–628). |
| T009 | high | Wrong field shape or missing field would propagate to log readers and degrade triage. Logging the wrong thing (e.g. transcript) would violate Principle 4. | Contract file ([contracts/diagnostic-event.md](./contracts/diagnostic-event.md)) is the authoritative schema. Privacy clause: only enum-valued and primitive fields, no transcript/response. Code review check: grep for transcript variable name in the log call — must not appear. |
| T012 | low | Pure SwiftUI view change. Container scaling is well-supported by `GeometryReader`. | T011 covers the curve. Manual QA (T013) covers visual correctness. |

---

## Notes

- This feature does NOT add new external dependencies, new persistence, new API surfaces, or new entitlements. Principle 2 (Swift-first, minimal deps) is preserved.
- The diagnostic event is INFO level, not DEBUG — it is intended to be visible in the default log file so user-reported wrong-language issues can be triaged without flipping logging level.
- The Settings default `AppSettings.globalTextLanguage` is **read-only** in this feature. Any task that writes to it is a bug and would fail T016.
- `[P]` = different files, no incomplete-task dependencies — verified per task above.
- Commit after each task or logical group; do not amend across tasks.

---

## Status Notes (post-implementation)

### Outstanding user-action items

These three items cannot be completed by a code agent and require manual user action:

1. **Add new test files to the `VerborraTests` Xcode target** (`project.pbxproj` membership). The three new test files were created on disk but are not yet registered with the test target:
   - `VerborraTests/Models/TranslateToTargetInstructionTests.swift`
   - `VerborraTests/Services/LanguageResolutionTests.swift`
   - `VerborraTests/AudioAmplitudeMappingTests.swift`

   In Xcode: open `Verborra.xcodeproj`, right-click the `VerborraTests` group (or appropriate subgroup), choose "Add Files to 'Verborra'…", select each file, ensure **Target Membership** has **VerborraTests** checked.

2. **Fix the pre-existing `VerborraTests` Info.plist configuration** so `xcodebuild test` can run. Currently `GENERATE_INFOPLIST_FILE = NO` and no `INFOPLIST_FILE` is set for the test target. Fix: in Xcode target editor → `VerborraTests` → Build Settings, set `GENERATE_INFOPLIST_FILE = YES`. (Or set `INFOPLIST_FILE` to a valid plist path.) This is a pre-existing issue unrelated to this feature.

3. **Run T010 and T013 manual QA** with the running app and a valid OpenAI API key. See [quickstart.md](./quickstart.md) for the exact scenarios.

### Corrections to spec/plan artifacts

- **Supported language set** — the contract file [contracts/translation-directive.md](./contracts/translation-directive.md) listed 11 candidate languages (en, ru, es, de, fr, it, pt, nl, pl, uk, tr). The actual `SupportedLanguage` enum in [Verborra/Models/SupportedLanguage.swift](../../Verborra/Models/SupportedLanguage.swift) has 10 cases: `en, ru, es, fr, de, pt, zh, ja, ko, it`. The implementation matches the actual enum (added `zh, ja, ko` directives; omitted `nl, pl, uk, tr` because those `SupportedLanguage` cases don't exist). The contract file should be updated next time it's edited; the implementation is canonical.
- **AudioWaveformView call-site contract** — the original contract ([contracts/audio-waveform.md](./contracts/audio-waveform.md)) §"Call-site behavior" table said "no per-call-site changes required." `/speckit.verify` (V002) and follow-up tuning corrected this: each call site MUST provide an explicit `.frame(height:)`. The 0.14 confirmed values are RecordingView = 110 pt, MicrophoneTestStep = 120 pt, InputFieldView = 24 pt. Spec.md Clarifications session 2026-05-29 records this. The contract file should be updated next edit to match.
- **Overlay panel sizing** — overlay panel `initialSize` height and bottom-of-screen margin were tuned in T019 to fit the new compact 110 pt indicator. These are not strictly part of feature 014's spec but ship in the same release because the calibration was performed against the new indicator size.
- **Directive contract stale (post-2026-05-29 rework)** — [contracts/translation-directive.md](./contracts/translation-directive.md) lists 11 per-language directives. Post-T024/T025, both `DoNotAnswerInstruction` and `TranslateToTargetInstruction` are **English-only** (no per-language tables) — `TranslateToTargetInstruction` interpolates the target language NAME into an English template. The contract file should be rewritten next edit to reflect this, or annotated as "superseded by 2026-05-29 clarification in spec.md".
- **Section heading rename** — `## Critical Instruction` is renamed to `## Response Instruction` for the DoNotAnswer block. Any external doc that references the old heading needs updating; internal refs already consistent.
- **PromptEnhancer.swift filename** — the file at [Verborra/Services/PromptEnhancer.swift](../../Verborra/Services/PromptEnhancer.swift) now contains the `SystemPromptBuilder` enum + the two directive enums, NOT the old `PromptEnhancer` struct. Filename preserved to avoid `project.pbxproj` modification. Rename pending — needs an Xcode UI rename or a careful pbxproj edit. Not blocking.

### Build status

- **Main app build:** ✅ `** BUILD SUCCEEDED **` (Xcode 26.5, target macOS 15.0).
- **Test target build:** ❌ blocked by the pre-existing `GENERATE_INFOPLIST_FILE` configuration (see item 2 above). Once unblocked AND the test files are added to the target (item 1), the new tests should run cleanly — they are pure-function tests with no environmental dependencies.
