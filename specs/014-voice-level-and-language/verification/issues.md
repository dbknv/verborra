# Verification Issues: Feature 014 — Voice Level Indicator Scaling & Forced Response Language

**Feature**: 014-voice-level-and-language
**Run**: 2026-05-28T16:55:00+02:00
**Total issues**: 2 (1 HIGH, 0 MEDIUM, 1 LOW, 0 CRITICAL)

---

## V002 — Indicator visual regression: GeometryReader is greedy, RecordingView call site has no height constraint

**Task**: T012
**Severity**: HIGH
**Type**: `regression_visual_layout`
**Verification level**: L2 Standard (escalated finding from L4 review of related call-site)
**Confidence**: 90% (deduced from layout rules; visual confirmation requires T013 manual QA)
**Status**: detected

### Files

- [Verborra/Views/Components/AudioWaveformView.swift](../../../Verborra/Views/Components/AudioWaveformView.swift) — the rewritten component
- [Verborra/Views/RecordingView.swift](../../../Verborra/Views/RecordingView.swift#L78) — the primary call site

### Description

`AudioWaveformView` now wraps its body in `GeometryReader` to read container height. `GeometryReader` in SwiftUI is **greedy** — it expands to fill all available space along the axis. The new implementation has only `.frame(minHeight: 24)` as a floor; there is no maximum.

In the primary call site, `RecordingView.recordingView(duration:remaining:)` at line 78, `AudioWaveformView` sits in a `VStack(spacing: 12)` next to a `Text(formatRemaining(remaining))`. The Text takes its intrinsic small height; the GeometryReader-based AudioWaveformView takes everything else. Previously the component had an internal `.frame(height: 40)`, so the indicator was a fixed 40 pt regardless of available space. After this change it expands to whatever vertical space the recording overlay window provides — typically much taller than 40 pt.

The other two call sites are protected because they already specify an explicit height:

- `InputFieldView.swift:29` — `.frame(height: 24)` constrains the indicator to 24 pt ✓
- `MicrophoneTestStep.swift:20` — `.frame(height: 60)` constrains the indicator to 60 pt ✓

Only `RecordingView.swift:78` is unconstrained.

### Source of truth

- **Type**: spec + contract
- **References**:
  - spec.md FR-008: "The indicator MUST continue to work in every location where it is currently used, without requiring changes at each call site beyond passing the same data it receives today."
  - contracts/audio-waveform.md §"Call-site behavior" table: "RecordingView.swift:78 — no explicit frame — **None** required."
- **Conflict**: The contract said no call-site changes required, but in practice the unconstrained call site allows GeometryReader to grow without bound. FR-008's "must continue to work" is violated by the visual regression.

### Fix context

- **Can fix automatically**: Yes
- **Two viable approaches** (pick one):

  **Approach A — add an explicit height at the call site** (smallest blast radius):

  ```swift
  // RecordingView.swift:78
  AudioWaveformView(audioLevel: viewModel.audioLevel)
      .frame(height: 60)   // or 40 to match the previous default
  ```

  Pros: zero impact on the component or other call sites; explicit per-location intent.
  Cons: contradicts the "no call-site changes" line in the contract.

  **Approach B — cap the component's vertical greed**:

  Add `.frame(maxHeight: 60)` (or 80) at the end of `AudioWaveformView.body`:

  ```swift
  var body: some View {
      GeometryReader { geometry in
          ...
      }
      .frame(minHeight: Self.intrinsicFallbackHeight, maxHeight: 80)
  }
  ```

  Pros: no call-site changes; component behaves sensibly in any layout.
  Cons: imposes a default ceiling. Larger containers (e.g. MicrophoneTestStep's 60 pt is fine, but a future 100 pt container would be capped at 80 pt unless the call site explicitly opts in).

- **Recommended**: Approach A — restore an explicit `.frame(height: 60)` on RecordingView.swift:78. This is a 1-line change, matches the spec's intent of "≥50% of container height in every place the indicator is embedded" (a 60-pt container is a sensible default for the primary recording view), and keeps the component truly container-relative.

- **Affected files**: `Verborra/Views/RecordingView.swift` (Approach A) OR `Verborra/Views/Components/AudioWaveformView.swift` (Approach B).
- **Requires spec update**: minor — the contract's "no call-site changes required" line should be qualified ("explicit `.frame(height:)` is needed at unconstrained call sites").

### Uncertainty

- **Flags**: visual-confirmation-required
- **Confidence reason**: GeometryReader greediness in a VStack is a well-known SwiftUI behavior, but the actual rendered height in the floating overlay window depends on the overlay's own sizing — not directly inspectable from the source. T013 manual QA would confirm or refute.

---

## V001 — Dead-code path in non-streaming voice fallback duplicates response-language section

**Task**: — (no specific task; surfaced during L4 review of T008)
**Severity**: LOW
**Type**: `code_cleanup_pre_existing`
**Verification level**: L4 Deep (escalated)
**Confidence**: 95%
**Status**: detected

### Files

- [Verborra/ViewModels/RecordingViewModel.swift:721-726](../../../Verborra/ViewModels/RecordingViewModel.swift#L721)

### Description

In `RecordingViewModel.stopRecording()`, when `streamingService == nil` (no streaming service injected — the `else` branch at line 713), the code falls through to:

```swift
formattedText = try await formattingService.format(
    text: rawText,
    systemPrompt: enhancedSystemPrompt,
    textLanguage: selectedTextLanguage,
    model: settings.selectedLLMModel
)
```

This uses the **4-argument overload**, which goes through the extension default and ends up calling the protocol's 7-argument method with `vocabularyEntries: [], personalPreferences: "", skipResponseLanguageSection: false`.

`FormattingService.format` then runs `PromptEnhancer().enhance(basePrompt: enhancedSystemPrompt, ...)` — re-enhancing an already-enhanced prompt. The default-true Response Language section gets appended to a prompt that **already** contains the new `TranslateToTargetInstruction` directive (on first voice turn), producing two conflicting/duplicative language instructions.

### Production impact

- **Production reach**: ZERO. `VerborraApp.swift:144` always injects `StreamingFormattingService` (line 162), so this `else` branch is unreachable in the running app.
- **Test reach**: not exercised by existing tests (`DictationFlowTests` and `RecordingViewModelTests` both inject mock streaming services).
- **Pre-existing**: this duplication-by-re-enhancement was already present before feature 014 — the only delta is that the duplicated content now differs (new directive vs. old default) instead of being identical.

### Source of truth

- **Type**: code analysis (no spec violation, since the path is unreachable)
- **Reference**: none — code-cleanup finding, not a spec or contract violation.

### Fix context

- **Can fix automatically**: Yes
- **Suggested approach**: pass the explicit 7-arg call with `vocabularyEntries: vocabularyStore.entries, personalPreferences: settings.personalPreferencesText, skipResponseLanguageSection: isFirstVoiceTurn` — mirrors the streaming-fallback path at line 699:

  ```swift
  formattedText = try await formattingService.format(
      text: rawText,
      systemPrompt: enhancedSystemPrompt,
      textLanguage: selectedTextLanguage,
      model: settings.selectedLLMModel,
      vocabularyEntries: [],                       // empty — already included above
      personalPreferences: "",                     // empty — already included above
      skipResponseLanguageSection: true            // already-enhanced, suppress double-add
  )
  ```

  (Vocab and prefs are already inside `enhancedSystemPrompt`, so passing empty avoids them being added a second time. `skipResponseLanguageSection: true` avoids the doubled Response Language section.)

  Alternatively, since this path is unreachable in production, deleting the `else` branch entirely is also valid — but that's a riskier change because it removes a fallback that tests might depend on later.

- **Affected files**: `Verborra/ViewModels/RecordingViewModel.swift`
- **Requires spec update**: no

### Uncertainty

- **Flags**: pre-existing
- **Confidence reason**: code path is verifiable from source; production unreachability is verified from VerborraApp.swift wiring.
