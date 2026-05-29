# Quickstart — Feature 014 implementation

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Branch**: `014-voice-level-and-language`

A linear path to a working implementation. Two independent directions; implement and verify each separately.

---

## Direction 1 — Voice level indicator (60–90 min)

### 1. Edit `AudioWaveformView`

[Verborra/Views/Components/AudioWaveformView.swift](../../Verborra/Views/Components/AudioWaveformView.swift)

- Wrap the bars `HStack` in a `GeometryReader`.
- Inside, derive `let maxBarHeight = geometry.size.height * 0.9`.
- Replace any current fixed `maxHeight = 36` (or similar) with `maxBarHeight`.
- Before computing each bar's height, transform the input level: `let displayLevel = pow(Double(audioLevel), 0.5)`. Use `displayLevel` (not raw `audioLevel`) in the bar-height formula.
- Keep the existing per-bar phase variation and 0.1 s `easeInOut` animation.
- Verify the component no longer carries an outer `.frame(height: 40)` — its size is determined by the container.

### 2. Sanity-check call sites

[RecordingView.swift:78](../../Verborra/Views/RecordingView.swift#L78), [InputFieldView.swift:29](../../Verborra/Views/InputFieldView.swift#L29), [MicrophoneTestStep.swift:20](../../Verborra/Views/Onboarding/MicrophoneTestStep.swift#L20) — no edits expected. Each parent already constrains the vertical space via `.frame(height:)` (or via the surrounding layout in `RecordingView`).

### 3. Unit tests

Create `Tests/AudioAmplitudeMappingTests.swift`:

- `pow(0.0, 0.5) == 0.0`
- `pow(0.10, 0.5) ≈ 0.32` (assert ≥ 0.30, ≤ 0.34)
- `pow(0.25, 0.5) == 0.5` (boundary — at quarter input the bar is half-height)
- `pow(1.0, 0.5) == 1.0` (saturation preserved)

### 4. Manual QA

Run the app:

- Floating window: speak at normal volume — bars clearly fill ≥50% of the container.
- Onboarding mic-test step (60 pt container): the indicator now visually fills the larger container.
- Input-field record (24 pt container): the indicator still looks proportional, no overflow.
- Silence: bars sit at baseline, no flicker.
- Loud burst (clap, cough): bars saturate at top, smooth decay back to normal.

---

## Direction 2 — Forced response language (3–5 hours)

### 1. Add `TranslateToTargetInstruction`

Edit [Verborra/Models/SystemPromptDefinition.swift](../../Verborra/Models/SystemPromptDefinition.swift). Append the new enum at the bottom of the file, mirroring `DoNotAnswerInstruction`. Use the per-language strings from [contracts/translation-directive.md](./contracts/translation-directive.md). Add a unit test (`Tests/TranslateToTargetInstructionTests.swift`) that iterates `SupportedLanguage.allCases` and asserts:

- Every case has a non-empty `translations` entry.
- `text(for: .en)` is non-empty (used as fallback).

### 2. Add `initialTextLanguageOnOpen` to `RecordingViewModel`

Edit [Verborra/ViewModels/RecordingViewModel.swift](../../Verborra/ViewModels/RecordingViewModel.swift):

- Near the existing `didConsumeFirstVoiceTurn` declaration (line ~18), add `private var initialTextLanguageOnOpen: SupportedLanguage?`.
- Inside `showOverlay()` (around line 473–487), where `didConsumeFirstVoiceTurn = false` is set, also set `initialTextLanguageOnOpen = appSettings.globalTextLanguage`.
- In the corresponding close/teardown method, set both back: `didConsumeFirstVoiceTurn = false`, `initialTextLanguageOnOpen = nil`.

### 3. Inject the directive on first voice turn

In the same file, locate the existing first-turn-only injection of `DoNotAnswerInstruction` (around lines 615–628). Mirror it for the translation directive:

```swift
let isFirstVoiceTurn = !didConsumeFirstVoiceTurn
let resolvedTarget = selectedTextLanguage

var systemMessage = systemPrompt.contentForLanguage(voiceLanguage)

if isFirstVoiceTurn {
    systemMessage += "\n\n" + TranslateToTargetInstruction.text(for: resolvedTarget)
}

systemMessage = PromptEnhancer().enhance(
    base: systemMessage,
    textLanguage: resolvedTarget,
    skipResponseLanguageSection: isFirstVoiceTurn   // see step 4
)

if isFirstVoiceTurn && !systemPrompt.answerQuestionsInFirstMessage {
    systemMessage += "\n\n" + DoNotAnswerInstruction.text(for: voiceLanguage)
}
```

Then emit the diagnostic event **before** the LLM call:

```swift
if isFirstVoiceTurn {
    let overrideSource = (resolvedTarget == initialTextLanguageOnOpen)
        ? "settings-default" : "user-changed"
    log.info(
        "Language resolution for first voice turn",
        metadata: [
            "resolvedTargetLanguage": resolvedTarget.rawValue,
            "directiveInjected": "true",
            "overrideSource": overrideSource,
            "isFirstVoiceTurn": "true"
        ]
    )
}
```

If `RecordingViewModel` doesn't already hold an `.api` logger, add one near the top of the class:

```swift
private let log = DiagnosticLogger.logger(for: .api)
```

Mark `didConsumeFirstVoiceTurn = true` at the existing site (line ~628).

### 4. Update `PromptEnhancer.enhance`

Edit [Verborra/Services/PromptEnhancer.swift](../../Verborra/Services/PromptEnhancer.swift) (lines 19–61):

- Add a parameter `skipResponseLanguageSection: Bool = false`.
- When `true`, skip the existing "You MUST respond in the following language: …" block (lines ~26–29). All other behavior (personal preferences, vocabulary replacements) is unchanged.

This avoids duplicating the response-language instruction on first voice turn (where `TranslateToTargetInstruction` now owns it).

### 5. Unit tests

`Tests/LanguageResolutionTests.swift`:

- Override source classification: given `initialTextLanguageOnOpen = .en` and `selectedTextLanguage = .en` → `"settings-default"`. Given `selectedTextLanguage = .fr` → `"user-changed"`.
- Directive text presence: with `isFirstVoiceTurn = true`, the assembled system message contains the substring from `TranslateToTargetInstruction.text(for: resolvedTarget)`.
- Directive omission on continuation: with `isFirstVoiceTurn = false`, the assembled system message does NOT contain the substring.
- `PromptEnhancer.enhance(skipResponseLanguageSection: true)` does NOT include the "You MUST respond in the following language" line.

### 6. Manual QA (the critical scenarios from spec)

1. **Override on first turn — different language**: open the floating window with Settings default = English, change picker to French, dictate one message in Russian, submit. Expect the response in French. Verify the JSONL log shows `overrideSource: "user-changed"`.
2. **Override on first turn — same language**: open the floating window with Settings default = English, leave picker at English, dictate one message in English, submit. Expect the response in English (no translation/rephrasing). Verify the log shows `overrideSource: "settings-default"`.
3. **Continuation in same chat**: after scenario 1, dictate a second voice turn (without closing the window). Expect the response in French still (chat continuation). Verify NO new language-resolution log event.
4. **Mid-chat override change**: after scenario 1, change the picker to German *without closing the window*, dictate a third voice turn. Expect the response still in French (chat continuation; FR-012a). Verify still NO new language-resolution log event.
5. **New chat with new language**: close the window, reopen, picker now back to English (Settings default — verifying FR-013 and FR-015). Change to German, dictate, submit. Expect the response in German. Verify a new log event with `overrideSource: "user-changed"`.
6. **Persistence boundary**: change picker to French inside the floating window, close the window without submitting, reopen. Picker now shows English again (the Settings default). Verifies FR-014 and FR-015.

### 7. Verify the log file

```bash
tail -f ~/Library/Application\ Support/Verborra/Logs/*.jsonl | jq 'select(.message=="Language resolution for first voice turn")'
```

Confirm the event fires exactly once per scenario 1, 2, and 5; zero times for 3, 4, and 6 (until a submission happens).

---

## Done criteria

- All unit tests pass (build with no warnings, SwiftLint clean — Principle 5).
- All six manual QA scenarios for Direction 2 produce the expected outcome.
- All six manual QA points for Direction 1 produce the expected visual.
- No new SPM dependencies were added.
- No new persistence locations were added.
- The Settings default response language is unchanged in behavior for users who never touch the floating-window picker.
