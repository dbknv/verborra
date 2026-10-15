import XCTest
@testable import Verborra

final class TokenEstimatorTests: XCTestCase {

    func testEstimateTokensBasic() {
        // 12 chars / 3 = 4 tokens
        XCTAssertEqual(TokenEstimator.estimateTokens("Hello World!"), 4)
    }

    func testEstimateTokensEmptyString() {
        // min 1 token
        XCTAssertEqual(TokenEstimator.estimateTokens(""), 1)
    }

    func testEstimateTokensSingleChar() {
        XCTAssertEqual(TokenEstimator.estimateTokens("A"), 1)
    }

    func testEstimateTokensCyrillic() {
        // "Привет мир" = 10 chars / 3 ≈ 3 tokens
        XCTAssertEqual(TokenEstimator.estimateTokens("Привет мир"), 3)
    }

    func testContextLimitGPT6Luna() {
        XCTAssertEqual(TokenEstimator.contextLimit(for: .gpt6Luna), 922_000)
    }

    func testContextLimitGPT52() {
        XCTAssertEqual(TokenEstimator.contextLimit(for: .gpt52), 1_048_576)
    }

    func testMessageBudget() {
        let budget = TokenEstimator.messageBudget(for: .gpt6Luna, systemPromptTokens: 100)
        // 80% of 922000 = 737600, minus 100 = 737500
        XCTAssertEqual(budget, 737_500)
    }

    func testMessageBudgetLargeSystemPrompt() {
        let budget = TokenEstimator.messageBudget(for: .gpt6Luna, systemPromptTokens: 1_000_000)
        // Should not go negative
        XCTAssertEqual(budget, 0)
    }
}
