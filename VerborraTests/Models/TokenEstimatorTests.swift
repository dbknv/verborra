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

    func testContextLimitGPT4oMini() {
        XCTAssertEqual(TokenEstimator.contextLimit(for: .gpt4oMini), 128_000)
    }

    func testContextLimitGPT41Nano() {
        XCTAssertEqual(TokenEstimator.contextLimit(for: .gpt41Nano), 1_048_576)
    }

    func testMessageBudget() {
        let budget = TokenEstimator.messageBudget(for: .gpt4oMini, systemPromptTokens: 100)
        // 80% of 128000 = 102400, minus 100 = 102300
        XCTAssertEqual(budget, 102_300)
    }

    func testMessageBudgetLargeSystemPrompt() {
        let budget = TokenEstimator.messageBudget(for: .gpt4oMini, systemPromptTokens: 200_000)
        // Should not go negative
        XCTAssertEqual(budget, 0)
    }
}
