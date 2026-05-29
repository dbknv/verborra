import XCTest
@testable import Verborra

// MARK: - Language Resolution Tests (014, T003)
//
// Covers the pure-logic pieces of the forced response language path:
//   - Override-source classification (settings-default vs user-changed).
//   - PromptEnhancer's new skipResponseLanguageSection flag.
//   - System-message assembly: first-voice-turn includes the
//     TranslateToTargetInstruction substring; continuation does NOT.
//
// Behavioral / end-to-end assertions about RecordingViewModel.streamChat
// live in DictationFlowTests; here we keep the helpers pure so they can
// run without spinning up the recording stack.

final class LanguageResolutionTests: XCTestCase {

    // MARK: - Override-source classification (FR-014, R5)

    func testOverrideSourceClassifiedAsSettingsDefaultWhenUnchanged() {
        let initial: SupportedLanguage = .en
        let current: SupportedLanguage = .en
        XCTAssertEqual(classifyOverrideSource(current: current, initial: initial), "settings-default")
    }

    func testOverrideSourceClassifiedAsUserChangedWhenDifferent() {
        let initial: SupportedLanguage = .en
        let current: SupportedLanguage = .fr
        XCTAssertEqual(classifyOverrideSource(current: current, initial: initial), "user-changed")
    }

    func testOverrideSourceClassifiedAsSettingsDefaultWhenInitialMissing() {
        // Defensive: if no snapshot was captured (e.g. window opened mid-test),
        // we treat it as settings-default to avoid false "user-changed" reports.
        XCTAssertEqual(classifyOverrideSource(current: .en, initial: nil), "settings-default")
    }

    // MARK: - PromptEnhancer skipResponseLanguageSection (FR-011, contract)

    func testPromptEnhancerDefaultIncludesResponseLanguageSection() {
        let result = PromptEnhancer().enhance(
            basePrompt: "Base instructions.",
            textLanguage: .en,
            vocabularyEntries: [],
            personalPreferences: ""
        )
        XCTAssertTrue(result.contains("## Response Language"),
                      "Default behavior must include Response Language section")
        XCTAssertTrue(result.contains("You MUST respond in the following language"),
                      "Default must contain the canonical response-language wording")
    }

    func testPromptEnhancerSkippedOmitsResponseLanguageSection() {
        let result = PromptEnhancer().enhance(
            basePrompt: "Base instructions.",
            textLanguage: .en,
            vocabularyEntries: [],
            personalPreferences: "",
            skipResponseLanguageSection: true
        )
        XCTAssertFalse(result.contains("## Response Language"),
                       "skipResponseLanguageSection=true must omit Response Language heading")
        XCTAssertFalse(result.contains("You MUST respond in the following language"),
                       "skipResponseLanguageSection=true must omit the canonical wording")
    }

    func testPromptEnhancerSkippedKeepsPersonalPreferencesAndVocabulary() {
        let entry = VocabularyEntry(targetWord: "OpenAI", alternatives: ["open ai"])
        let result = PromptEnhancer().enhance(
            basePrompt: "Base instructions.",
            textLanguage: .en,
            vocabularyEntries: [entry],
            personalPreferences: "Be concise.",
            skipResponseLanguageSection: true
        )
        XCTAssertTrue(result.contains("## Personal Preferences"),
                      "Personal Preferences section must still appear when skipped Response Language only")
        XCTAssertTrue(result.contains("## Vocabulary Replacements"),
                      "Vocabulary Replacements section must still appear")
        XCTAssertTrue(result.contains("Be concise."),
                      "Personal preferences body must be preserved")
    }

    // MARK: - First-voice-turn system-message assembly (FR-011/FR-012, contract)

    func testFirstVoiceTurnAssemblyContainsDirectiveSubstring() {
        let base = "Base prompt."
        let target: SupportedLanguage = .fr
        let directive = TranslateToTargetInstruction.text(for: target)

        // First voice turn assembly: base + "\n\n" + directive,
        // then PromptEnhancer with skipResponseLanguageSection: true.
        let withDirective = base + "\n\n" + directive
        let enhanced = PromptEnhancer().enhance(
            basePrompt: withDirective,
            textLanguage: target,
            vocabularyEntries: [],
            personalPreferences: "",
            skipResponseLanguageSection: true
        )

        XCTAssertTrue(enhanced.contains(directive),
                      "First-voice-turn message must contain the localized directive substring")
        XCTAssertFalse(enhanced.contains("You MUST respond in the following language"),
                       "First-voice-turn must NOT contain the default English wording (suppressed by skip flag)")
    }

    func testContinuationAssemblyDoesNotContainDirective() {
        let base = "Base prompt."
        let target: SupportedLanguage = .fr
        let directive = TranslateToTargetInstruction.text(for: target)

        // Continuation assembly: base passed straight to PromptEnhancer with
        // skipResponseLanguageSection: false (default).
        let enhanced = PromptEnhancer().enhance(
            basePrompt: base,
            textLanguage: target,
            vocabularyEntries: [],
            personalPreferences: ""
        )

        XCTAssertFalse(enhanced.contains(directive),
                       "Continuation turns must NOT carry the TranslateToTargetInstruction directive")
        XCTAssertTrue(enhanced.contains("## Response Language"),
                      "Continuation turns continue to receive the default Response Language section")
    }

    // MARK: - Helpers

    /// Pure-function mirror of the override-source classification logic that
    /// RecordingViewModel performs at submission time. Extracted here so the
    /// rule is unit-testable without bringing up the full ViewModel stack.
    private func classifyOverrideSource(
        current: SupportedLanguage,
        initial: SupportedLanguage?
    ) -> String {
        guard let initial else { return "settings-default" }
        return current == initial ? "settings-default" : "user-changed"
    }
}
