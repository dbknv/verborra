# Phase 0 Research — Voice Level Indicator Scaling & Forced Response Language

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Date**: 2026-05-28

Six decisions, resolving every NEEDS CLARIFICATION raised during planning. None remain open.

---

## R1 — Amplitude mapping curve for the voice level indicator

**Decision**: Apply a `pow(level, 0.5)` (square-root) curve on top of the existing linear `min(rms * 5, 1.0)` audio level in `RecordingViewModel.audioLevel`. The square-root curve is applied inside `AudioWaveformView`, not at the source, so the level signal continues to expose a linear 0…1 amplitude for other consumers.

**Rationale**:

- Today's pipeline: RMS over the audio buffer, multiplied by a hardcoded gain of 5.0, clamped to 1.0 ([AudioCaptureService.swift:436](Verborra/Services/AudioCaptureService.swift#L436)). At conversational input (~−25 to −20 dBFS RMS) the resulting linear level is typically 0.05–0.15 → only 5–15% of available height. That's why the bar barely moves (matches the user's report).
- Increasing the gain (e.g. to 15.0) is a tempting one-line fix but it pushes loud speech and bursts immediately to saturation, eliminating useful headroom and making the indicator look "stuck full" during normal speech.
- A power curve with exponent < 1 expands the low end and compresses the top: at level=0.10, `pow(0.10, 0.5) ≈ 0.32` (≈32% height); at level=0.50, `pow(0.50, 0.5) ≈ 0.71` (≈71%). At level=0.0 it stays 0. This hits the ≥50% target in SC-001 without saturating early.
- Applied at the *view* layer (not in `AudioCaptureService`) so the underlying audio signal stays unchanged for any future consumers (telemetry, VAD, etc.) and so we don't need to touch the audio capture pipeline (Principle 4 — no audio pipeline changes).

**Alternatives considered**:

- *Bump the linear gain from 5.0 to ~10–15.* Rejected: saturates loud speech, loses dynamic range.
- *True dB scaling (`20 * log10`)*. Rejected as overkill for this scope; the `pow(x, 0.5)` curve achieves the visible target with a single line of Swift and no need to handle the log-of-zero edge case.
- *Per-call-site amplification multiplier (so each container could tune its own gain)*. Rejected: violates FR-008 ("MUST continue to work in every location… without requiring changes at each call site").

---

## R2 — Container-relative scaling in SwiftUI

**Decision**: Wrap the bar-rendering body of `AudioWaveformView` in a `GeometryReader`. Derive each bar's `maxHeight` as a fraction (e.g. `0.9`) of `geometry.size.height`. Remove the current fixed `maxHeight = 36` and the implicit fixed 40-pt frame around the component.

**Rationale**:

- `GeometryReader` is the native SwiftUI primitive for "use whatever vertical space my parent gives me." The component remains a single shared SwiftUI view (FR-001) and consumers continue to use `.frame(height:)` (or any other height-determining modifier) on the parent to give the indicator a height budget. No call-site changes required.
- The current 0.1 s `easeInOut` animation is preserved.
- Leaving a small slack at the top (`0.9 * height`) avoids the bars visually touching the container edge during loud speech (smooth saturation per FR-005).

**Alternatives considered**:

- *Explicit `height` parameter on `AudioWaveformView`*. Rejected: pushes container responsibility into every call site, contradicts FR-008 and FR-002.
- *PreferenceKey-based two-pass layout*. Rejected as overengineered for a leaf component.

---

## R3 — Smoothing strategy

**Decision**: Keep the existing 0.1 s SwiftUI `easeInOut` animation on the `audioLevel` binding (already in place at [AudioWaveformView.swift:15](Verborra/Views/Components/AudioWaveformView.swift#L15)). Do **not** add an exponential moving average (EMA) on the raw level signal in addition.

**Rationale**:

- The level signal is already published at a stable 20 Hz cadence (50 ms timer in `RecordingViewModel`), and the existing 0.1 s ease interpolates between consecutive published values. Layered with the square-root curve from R1, this gives a smooth-but-responsive feel without double-smoothing.
- Adding EMA on top of an ease animation is a common cause of "soft mush" perception — the indicator feels delayed and unresponsive.
- The animation easing also gives free interpolation through the 50 ms gaps between RMS updates, eliminating the step artifacts that bare values would produce.

**Alternatives considered**:

- *EMA with α ≈ 0.3 instead of the ease animation*. Rejected: identical visual result with worse onset latency (SC-002 requires <100 ms visible deflection on speech onset; EMA with α 0.3 takes ~3 frames to reach 65%).
- *No smoothing — raw values driving the bar heights*. Rejected: visible step artifacts at 20 Hz update rate would violate FR-006.

If QA observes jitter in real usage, the fallback is to add a one-frame EMA in `RecordingViewModel.updateLevelsFromAtomic()` rather than at the view layer.

---

## R4 — Translation-directive shape and per-language strings

**Decision**: Add a new top-level static enum `TranslateToTargetInstruction` in `Verborra/Models/SystemPromptDefinition.swift`, mirroring the existing `DoNotAnswerInstruction` enum at [SystemPromptDefinition.swift:81](Verborra/Models/SystemPromptDefinition.swift#L81). Same shape: `static let translations: [SupportedLanguage: String]` + `static func text(for: SupportedLanguage) -> String`. The directive text is a fixed two-branch instruction parameterised by the target language's display name:

> *"Return the final text in **<TARGET>**. If the input is in another language, translate it to **<TARGET>**. If the input is already in **<TARGET>**, keep the language unchanged and only perform formatting and cleanup."*

Concrete localized text per `SupportedLanguage` is captured in [contracts/translation-directive.md](./contracts/translation-directive.md).

**Rationale**:

- Mirroring `DoNotAnswerInstruction` is the lowest-friction extension: same dictionary lookup, same call-site shape, same readability/maintenance ergonomics. New string tables sit beside the existing ones.
- The text is intentionally short and prescriptive (two branches: translate-if-different / leave-if-matches) — this is the exact pattern the user described.
- Localizing per supported language avoids the LLM having to infer instruction intent from English text when responding in (say) Russian.

**Alternatives considered**:

- *Single English instruction regardless of target language*. Rejected: LLMs follow non-English instructions more reliably when the instruction is itself in the target language.
- *Generate the directive dynamically from a template string in code*. Rejected: keeping each language's instruction as a hand-tuned literal is consistent with the existing `DoNotAnswerInstruction.translations` style and avoids surprising LLM behavior from machine-built phrasing.

---

## R5 — Override-source classification (`settings-default` vs `user-changed`)

**Decision**: Add `private var initialTextLanguageOnOpen: SupportedLanguage?` to `RecordingViewModel`. Set it inside `showOverlay()` (alongside the existing reset of `didConsumeFirstVoiceTurn = false`) from a read of `AppSettings.globalTextLanguage` at that moment. At submission time, compare `selectedTextLanguage` (the live override) against the snapshot:

- `selectedTextLanguage == initialTextLanguageOnOpen` → override source is `"settings-default"`.
- otherwise → override source is `"user-changed"`.

Reset to `nil` when the overlay closes.

**Rationale**:

- The classification needs to distinguish "the user opened the window and let the picker stay where it was" from "the user actively changed the picker before submitting." Comparing the current value to the value at window-open captures exactly that.
- The snapshot is in-memory only, lives on the same `RecordingViewModel` that owns the override, and is cleared on close. No new persistence (Principle 3).
- This avoids the need for the picker to set a flag every time it's touched — keeps `LanguageSelectorView` unchanged.

**Alternatives considered**:

- *A `Bool` flag (`overrideWasTouched`) set on every picker interaction.* Rejected: requires modifying `LanguageSelectorView` and `changeTextLanguage`. The snapshot approach is purely additive on the ViewModel.
- *Always log `selectedTextLanguage` and `globalTextLanguage` raw values, let downstream tooling diff them.* Rejected: pushes interpretation cost to log readers and clutters the event with two fields where one classified enum suffices.

---

## R6 — Diagnostic log event placement and structure

**Decision**: Emit one structured `DiagnosticLogger` event at INFO level inside `RecordingViewModel.streamChat()` (or wherever the first-voice-turn injection lands — currently lines ~615–628), under category `.api` (the same category `ChatSession` uses). Emit **only** when `isFirstVoiceTurn == true`. Metadata fields:

| Field                     | Type                | Value                                         |
|---------------------------|---------------------|-----------------------------------------------|
| `resolvedTargetLanguage`  | String (raw value)  | e.g. `"en"`, `"ru"`, `"fr"`                   |
| `directiveInjected`       | String              | `"true"` (always true when this event fires)  |
| `overrideSource`          | String (enum value) | `"settings-default"` \| `"user-changed"`      |
| `isFirstVoiceTurn`        | String              | `"true"`                                      |

See [contracts/diagnostic-event.md](./contracts/diagnostic-event.md) for the full JSONL schema.

**Rationale**:

- Category `.api` keeps the event next to existing message-prep logs in `ChatSession.prepareMessagesForLLM` (the same area engineers will look at to debug a "wrong language" report).
- INFO level (not DEBUG) per constitution Principle 6 — first-voice-turn submission is a "key lifecycle event" worth seeing without flipping to DEBUG. Volume is bounded: one event per chat session, not per audio frame.
- The fields are all small primitives. No transcript content, no API payload, no language model output is logged.
- `directiveInjected: "true"` is technically redundant today (the event only fires when injection happens), but writing it explicitly future-proofs the event for the case where injection becomes conditional.

**Alternatives considered**:

- *Log under a new category `.languageResolution`*. Rejected: adds a category for a single event, fragments where engineers look for related context.
- *Log at DEBUG level only*. Rejected: users will report wrong-language issues to support; we want the event visible in the default `INFO` log so reports can be triaged without asking the user to switch logging level.
- *Emit on every voice turn including continuations*. Rejected by FR-022 — only the first turn carries the directive, and only its emission is interesting.
