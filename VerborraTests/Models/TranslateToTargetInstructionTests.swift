import XCTest
@testable import Verborra

// MARK: - TranslateToTargetInstruction tests (014, simplified post-QA 2026-05-29)

final class TranslateToTargetInstructionTests: XCTestCase {

    func testTextIsNonEmptyForEveryLanguage() {
        // The directive is a single English template with the target language
        // name interpolated; every SupportedLanguage case must yield a
        // non-empty directive.
        for language in SupportedLanguage.allCases {
            let text = TranslateToTargetInstruction.text(for: language)
            XCTAssertFalse(
                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Empty directive for \(language)"
            )
        }
    }

    func testDirectiveReferencesTargetLanguageByEnglishName() {
        // The directive interpolates `localizedDisplayName(for: .en)` — i.e.
        // English-language names like "English", "Russian", "Spanish". Each
        // directive must mention its own target language's English name.
        for language in SupportedLanguage.allCases {
            let englishName = language.localizedDisplayName(for: .en)
            let text = TranslateToTargetInstruction.text(for: language)
            XCTAssertTrue(
                text.contains(englishName),
                "Directive for \(language) does not reference its English-language name '\(englishName)'"
            )
        }
    }

    func testDirectiveHasResponseLanguageOverrideHeading() {
        for language in SupportedLanguage.allCases {
            let text = TranslateToTargetInstruction.text(for: language)
            XCTAssertTrue(
                text.contains("## Response Language Override"),
                "Directive for \(language) is missing the English section heading"
            )
        }
    }

    func testDirectiveHasBothMustRules() {
        // [MUST] return + [MUST] translate-if-different are the two rules of
        // the simplified directive.
        for language in SupportedLanguage.allCases {
            let text = TranslateToTargetInstruction.text(for: language)
            XCTAssertTrue(
                text.contains("[MUST] Return the response text in"),
                "Missing 'Return the response text in <target>' rule for \(language)"
            )
            XCTAssertTrue(
                text.contains("[MUST] If the input is in a language other than"),
                "Missing 'If the input is in another language' rule for \(language)"
            )
        }
    }
}
