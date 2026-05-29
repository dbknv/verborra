# Implementation Plan: Voice Level Indicator Scaling & Forced Response Language

**Branch**: `014-voice-level-and-language` | **Date**: 2026-05-28 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/014-voice-level-and-language/spec.md`

## Summary

Release 0.14 ships two independent improvements:

1. **Voice level indicator** — turn the current fixed-height `AudioWaveformView` (40 pt, linear mapping, gain 5.0) into a container-relative component that reads its available height via `GeometryReader`, applies a non-linear amplitude curve so conversational input fills ≥50% of the container, and smooths the level signal to remove jitter. **Call sites MUST supply an explicit `.frame(height:)`** (revised post-`/speckit.verify` — see clarification 2026-05-29 in spec.md). Confirmed per-call-site heights for 0.14: RecordingView = 110 pt, MicrophoneTestStep = 120 pt (existing 60 pt doubled), InputFieldView = 24 pt (unchanged from pre-feature). Bundled overlay calibration ships in the same release because it shares the QA cycle: overlay panel `initialSize` height = 220 pt (from 250), bottom-of-screen margin = 2% (from 5%), inner VStack spacing = 2 (from 12), outer paddings top = 6 / bottom = 8 (from 8 / 24), recording-state timer font reduced from `.title2` (~22 pt) to `.body` (~17 pt) monospaced. Plus one onboarding font fix: "Speak into the microphone…" hint loses its `.font(.caption)` so it matches its "Microphone is working" counterpart.
2. **Forced response language** — introduce a new `TranslateToTargetInstruction`, inject it into the formatting-stage system prompt and emit one structured `DiagnosticLogger` event recording the resolved target language, whether the directive was injected, and the override source (`settings-default` vs `user-changed`). The floating-window override (`RecordingViewModel.selectedTextLanguage`) is already per-window ephemeral and matches FR-013 through FR-015; this plan preserves that and adds an `initialTextLanguageOnOpen` snapshot so the override source can be detected at submission time.

   *Architecture revision (post-QA 2026-05-29)*: rather than mutating `PromptEnhancer` per-call, the entire system-prompt assembly is unified behind a single `SystemPromptBuilder.build(_: Input) -> String`. This builder lives in [Verborra/Services/PromptEnhancer.swift](Verborra/Services/PromptEnhancer.swift) (file kept under the legacy name) alongside the `DoNotAnswerInstruction` and `TranslateToTargetInstruction` enums it consumes. `PromptEnhancer` (struct) is removed. The builder produces the same prompt shape from every code path (4 in `RecordingViewModel` + 1 in `ChatSession.prepareMessagesForLLM`), in a fixed order: base prompt (always English) → Personal Preferences (if any) → Vocabulary Replacements (if any) → Response Instruction (if `injectDoNotAnswer`) → Response Language Override (always last). `FormattingService.format` and `StreamingFormattingService.streamFormat` are simplified to take an already-assembled prompt; their parameters `vocabularyEntries`, `personalPreferences`, `skipResponseLanguageSection` are removed. The previously-localized 10-locale `translations` tables for both directive enums are dropped — directives are English, with the target-language **name** (e.g. "Spanish") interpolated for `TranslateToTargetInstruction`. The `[MUST]/[MUST NOT]` mix is consolidated to **`[MUST]` only**. `DoNotAnswerInstruction`'s section heading is renamed from `## Critical Instruction` to `## Response Instruction`.

Both directions live entirely inside the existing app structure (SwiftUI views + the existing `RecordingViewModel`/`ChatSession`/`PromptEnhancer` pipeline). No new external dependencies, no new persistence locations, no schema migrations.

## Technical Context

**Language/Version**: Swift 5.9+ (Xcode 15+)
**Primary Dependencies**: SwiftUI, AppKit (NSPanel), AVFoundation (AVAudioEngine), swift-markdown (4.0+), KeyboardShortcuts (sindresorhus), swift-atomics (1.2+) — all already in the project; no additions.
**Storage**: UserDefaults / `@AppStorage` (Settings default for response language — existing `AppSettings.globalTextLanguage`). The floating-window override is in-memory only on `RecordingViewModel`. The new structured language-resolution event is logged via the existing JSONL diagnostic logging system (spec 007, `~/Library/Application Support/Verborra/Logs/`).
**Testing**: Swift Testing (or XCTest, whichever the project already standardizes on) for pure-logic units (target-language resolution, amplitude-mapping curve, override-source classification, translation-directive string assembly). Manual QA for visual smoothness and LLM compliance.
**Target Platform**: macOS 15 (Sequoia) and newer.
**Project Type**: Single macOS app (existing structure).
**Performance Goals**:

- Voice indicator visibly deflects within 100 ms of speech onset (SC-002).
- Voice indicator update is smooth at the existing 20 Hz audio-level cadence (50 ms timer in `RecordingViewModel`) — must not jitter or flicker.
- First-voice-turn directive injection adds ≤1 ms to the existing prompt-assembly path (string concatenation + dictionary lookup).
- Diagnostic logging on first turn is non-blocking (writes go through the existing `JSONLFileWriter` already used by `ChatSession`).

**Constraints**:

- No new external dependencies (Principle 2: justify each new SPM dependency — this feature adds none).
- No new audio pipeline changes (the level signal source remains `RecordingViewModel.audioLevel: Float`, RMS-based, capped at 1.0).
- No persistence change for the floating-window override; it remains in-memory only.
- Translation-directive text must be available in all currently supported response languages (per FR-020 and the existing `SupportedLanguage` set used by `DoNotAnswerInstruction.translations`).

**Scale/Scope**:

- ~3 SwiftUI files touched for Direction 1 (the component + 2-3 call sites only if call sites need any change — likely none).
- ~5 files touched for Direction 2: `SystemPromptDefinition.swift` (new instruction), `RecordingViewModel.swift` (injection + snapshot + logging), `PromptEnhancer.swift` (skip language section on first turn so it isn't duplicated), `AppSettings.swift` (no change — only read), `LanguageSelectorView.swift` (no change — already ephemeral). Plus tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| 1. Native macOS experience | ✅ Pass | All UI changes are pure SwiftUI inside the existing `AudioWaveformView`. No new windows/panels, no Electron, no third-party UI. |
| 2. Swift-first development | ✅ Pass | All changes are Swift. MVVM + `@Observable` pattern preserved (no architectural change). No new SPM dependencies introduced. |
| 3. Minimalism and simplicity | ✅ Pass | No new UI surfaces. Existing language picker is reused. Directive is added inside the existing system-prompt assembly. Hotkey path untouched. |
| 4. Security and privacy | ✅ Pass | No new audio storage. No new API keys. The new diagnostic log event contains the resolved target language (a `SupportedLanguage` raw value, non-sensitive) and an enum-valued override source — no message contents, no API payload. |
| 5. Code quality and testing | ✅ Pass | New logic (amplitude curve, target-language resolution, override-source classification, directive string assembly) is pure and unit-testable. Network interaction (LLM) is already abstracted through existing service protocols. |
| 6. Logging and observability | ✅ Pass | New structured event uses the existing `DiagnosticLogger` with category `.api` (where `ChatSession` already logs). Confidential data (transcript, response text) is not logged. The level signal itself is not logged (DEBUG-level metric noise avoided). |

No constitutional violations. No complexity-tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/014-voice-level-and-language/
├── plan.md                       # This file (/speckit.plan output)
├── spec.md                       # Feature specification (already written)
├── research.md                   # Phase 0 output (/speckit.plan)
├── data-model.md                 # Phase 1 output (/speckit.plan)
├── quickstart.md                 # Phase 1 output (/speckit.plan)
├── contracts/
│   ├── translation-directive.md  # Wording / per-language strings for the new directive
│   ├── diagnostic-event.md       # Structured event emitted on first voice turn
│   └── audio-waveform.md         # Component API + container behavior
├── checklists/
│   └── requirements.md           # Quality checklist (already written)
└── tasks.md                      # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
Verborra/
├── Views/
│   └── Components/
│       ├── AudioWaveformView.swift          # Direction 1: container-relative + curve + smoothing
│       └── LanguageSelectorView.swift       # Direction 2: no change (already ephemeral)
├── ViewModels/
│   └── RecordingViewModel.swift             # Direction 2: snapshot + directive injection + log event
├── Models/
│   ├── AppSettings.swift                    # Direction 2: no change (read-only consumer)
│   ├── SystemPromptDefinition.swift         # Direction 2: new TranslateToTargetInstruction enum
│   ├── ChatSession.swift                    # Direction 2: no functional change (continuation hint preserved)
│   └── LogCategory.swift                    # Direction 2: no change (existing .api category reused)
├── Services/
│   ├── PromptEnhancer.swift                 # Direction 2: skip language section on first voice turn
│   ├── AudioCaptureService.swift            # Direction 1: no change (RMS source preserved)
│   └── DiagnosticLogger.swift               # Direction 2: no change (structured metadata already supported)
└── Tests/
    ├── AudioAmplitudeMappingTests.swift     # Direction 1 — new
    ├── TranslateToTargetInstructionTests.swift  # Direction 2 — new
    └── LanguageResolutionTests.swift        # Direction 2 — new
```

**Structure Decision**: Single macOS Xcode project structure is preserved. No new top-level directories. Source files live alongside their existing peers.

## Complexity Tracking

> *No constitutional violations to track.* This feature reuses existing patterns (the `DoNotAnswerInstruction` injection model, the `DiagnosticLogger` with structured metadata, the per-window `RecordingViewModel.selectedTextLanguage` state) and adds no new abstractions.

---

## Phase 0 — Research

See `research.md` (generated by this command). Six decisions resolved:

1. **Amplitude curve** — non-linear power curve (`pow(level, 0.5)` ≈ square root) over the existing linear `min(rms * 5, 1.0)` signal, to make normal-volume speech reach the ≥50% target while keeping silence near baseline.
2. **Container-height detection** — `GeometryReader` wrapping the bars in `AudioWaveformView`; bar `maxHeight` derived as a fixed fraction (e.g. 90%) of the geometry's `size.height`.
3. **Smoothing strategy** — keep the existing 0.1 s SwiftUI ease animation; do NOT add EMA on top (avoids double-smoothing artifacts). Confirm via QA that this is enough; fall back to EMA only if jitter is observed.
4. **Directive shape and per-language strings** — mirror `DoNotAnswerInstruction.translations`. New enum `TranslateToTargetInstruction` with the two-branch wording per `SupportedLanguage`.
5. **Override-source classification** — capture `initialTextLanguageOnOpen` from `AppSettings.globalTextLanguage` when the overlay opens (in `RecordingViewModel.showOverlay()`). At submission, compare `selectedTextLanguage` to that snapshot; if equal → `settings-default`, else → `user-changed`.
6. **Log event placement and fields** — emit one event per first voice turn at the existing injection site in `RecordingViewModel` (line ~620), under category `.api`. Metadata fields: `resolvedTargetLanguage` (raw value), `directiveInjected: "true"`, `overrideSource: "settings-default" | "user-changed"`, `isFirstVoiceTurn: "true"`.

---

## Phase 1 — Design & Contracts

See `data-model.md`, `contracts/*.md`, and `quickstart.md` (generated by this command).

After Phase 1 is written, re-evaluate Constitution Check: **still passes**. No design surface required to add new persistence, networking, or third-party deps.

---

## Phase 1.5 — Post-hotfix architectural amendments (2026-05-29)

After 014 shipped, two user-facing defects landed against the spec: (a) the `answerQuestionsInFirstMessage` toggle was inert on the built-in prompt, and (b) switching the text language mid-chat-session did not retarget continuation turns. Root-causing produced four design amendments documented inline in spec.md (Session 2026-05-29 post-hotfix). Summary of the technical shape:

1. **`TranslateToTargetInstruction` becomes two-branch.** Signature changes from `text(for:)` to `text(for:allowAnswering:)`. When `allowAnswering: true`, only the language-constraint `[MUST]` is emitted; the echo/translate bullet is dropped. Builder derives `allowAnswering = !input.injectDoNotAnswer`. See FR-011 amendment in spec.md.

2. **New `AnswerQuestionInstruction` enum, symmetric to `DoNotAnswerInstruction`.** Single English `[MUST]` rule. `SystemPromptBuilder.Input` gains `injectAnswerQuestion: Bool = false`. Mutual exclusion with `injectDoNotAnswer` is enforced inside `build(_:)` via `if / else if`. Wired from both call sites (`RecordingViewModel.formatTranscription`, `ChatSession.prepareMessagesForLLM` first-voice-turn branch). See new FR-023.

3. **Toggle editability decoupled from `isReadOnly`.** `PromptsStore.setAnswerInFirstMessage(promptID:value:)` bypasses the read-only guard for this single field. `SettingsViewModel.persistAnswerInFirstMessage()` wraps it. `SettingsView.answerInFirstMessageRow` no longer disables the toggle for read-only prompts and auto-persists on change (Save button is not rendered for read-only prompts). FR-009b's read-only protection is unchanged for `name`/`content`.

4. **Language-change propagation into the active session.** `RecordingViewModel.changeTextLanguage(_:)` and `changeVoiceLanguage(_:)` mirror their new value into `chatSession?.textLanguage` / `voiceLanguage`. Continuation turns use the current value in `ChatSession.prepareMessagesForLLM`. See new FR-024. No change to `selectedTextLanguage` semantics — this fix is pure propagation into the session model.

5. **Built-in prompt rename to "Speech To Text" + v3→v4 migration.** `SystemPromptDefinition.simpleVoiceToText` (`systemId` retained) — `.en` name renamed; locales that distinguish Voice/Speech lexically updated (es, fr, pt, it). `PromptsStore.currentDataVersion` bumped 3→4; new migration step re-syncs `name`/`content` from `SystemPromptRegistry` for every system prompt (safe — system prompts cannot be user-modified). Existing installs pick up the rename on next launch.

All five amendments compile and ship as a single batch; no new tests added (the hotfix surfaces no new branches that aren't covered by the conceptual contracts of `SystemPromptBuilder` and `PromptsStore` migration). Tasks T033–T038 in tasks.md track the implementation.

---

## Phase 1.6 — OpenAI compatibility & model catalog amendments (2026-05-29)

After the toggle/language hotfix shipped, manual model-by-model testing surfaced a second class of defects: HTTP 400 from OpenAI on `gpt-5-nano` / `gpt-5-mini`, and HTTP 404 on `gpt-5.3`. The bodies were invisible in the log (only the status code was captured), making the cause untriagable from log alone. Resolving this produced four design amendments and a catalog cleanup, landed as a single batch.

1. **Response-body capture on non-200.** Both `StreamingFormattingService` (streaming) and `FormattingService` (non-streaming fallback) now log the OpenAI error body verbatim on every 4xx and 5xx, capped at 2000 chars (4000 for streaming non-200). New helper `StreamingFormattingService.collectBody(_:cap:)` drains the byte stream into a UTF-8 string. The `Streaming request details` DEBUG line also reports `"temperature": "omitted"` when the key is dropped per amendment 2, so the log mirrors the actual request shape rather than a hardcoded value. See new FR-025.

2. **`LLMModel.supportsTemperature: Bool` + conditional `temperature` key.** OpenAI's GPT-5 reasoning tier (`*-nano`, `*-mini` across `gpt-5` and `gpt-5.4` families) rejects any `temperature` other than the default `1` with HTTP 400 `unsupported_value`. The `temperature` key is now omitted from the JSON body when `supportsTemperature == false`. Both request builders updated. See new FR-026.

3. **Default LLM model: `gpt-4.1-nano` → `gpt-5.1`.** Single-line change to `LLMModel.default`. Affects only fresh installs and the `LLMServiceProtocol.process(text:systemPrompt:)` convenience entry point — existing installs keep their persisted choice through the `@AppStorage` fallback. See new FR-027.

4. **Catalog rotation: −2 / +6.** Removed `gpt-4.1-nano` (OpenAI deprecated — "Not recommended for new projects") and `gpt-5.3` (returns 404 — identifier doesn't exist at OpenAI). Added the six flagship-table entries: `gpt-5.4-nano`, `gpt-5.4-mini`, `gpt-5.4`, `gpt-5.4-pro`, `gpt-5.5`, `gpt-5.5-pro`. Per-case updates land in six places: enum, `displayName`, `infoDescription`, `supportsTemperature`, `TokenEstimator.contextLimit(for:)`, and `Localizable.xcstrings` (`en` + `ru` translations with inline pricing where OpenAI publishes it). Existing installs with a persisted removed-model identifier fall back silently to `LLMModel.default` via the `?? .default` clause already in `AppSettings`. See new FR-028.

**Known issue (out of scope for this batch)**: `FormattingService.performWithRetry` retries 400 errors up to `maxRetries` times because its `catch let error as RecordingError` clause stores the throw in `lastError` and falls through to the next loop iteration. 4xx should not be retried — only `429` and `5xx` — but the user-visible behaviour is unchanged (still fails after N attempts). Tracked separately. See spec Session 2026-05-29 model-compat clarifications for the rationale to defer.

All five points compile and ship together. Tasks T041–T046 in tasks.md track the implementation.

---

## Phase 2 — Out of /speckit.plan scope

`tasks.md` is produced by `/speckit.tasks` and is intentionally not created by this command.
