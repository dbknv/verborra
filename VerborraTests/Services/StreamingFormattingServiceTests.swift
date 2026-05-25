import XCTest
@testable import Verborra

final class StreamingFormattingServiceTests: XCTestCase {

    func testParseSSETokenValid() {
        // Test SSE parsing via a mock approach — validate the JSON format
        let json = """
        {"choices":[{"delta":{"content":"Hello"}}]}
        """
        let data = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = parsed?["choices"] as? [[String: Any]]
        let delta = choices?.first?["delta"] as? [String: Any]
        let content = delta?["content"] as? String

        XCTAssertEqual(content, "Hello")
    }

    func testParseSSETokenWithEmptyContent() {
        let json = """
        {"choices":[{"delta":{"content":""}}]}
        """
        let data = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = parsed?["choices"] as? [[String: Any]]
        let delta = choices?.first?["delta"] as? [String: Any]
        let content = delta?["content"] as? String

        XCTAssertEqual(content, "")
    }

    func testParseSSETokenWithNoDelta() {
        let json = """
        {"choices":[{"delta":{}}]}
        """
        let data = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = parsed?["choices"] as? [[String: Any]]
        let delta = choices?.first?["delta"] as? [String: Any]
        let content = delta?["content"] as? String

        XCTAssertNil(content)
    }

    func testDONESignal() {
        let line = "data: [DONE]"
        let json = String(line.dropFirst(6))
        XCTAssertEqual(json, "[DONE]")
    }

    func testSSELinePrefix() {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"token\"}}]}"
        XCTAssertTrue(line.hasPrefix("data: "))
        let json = String(line.dropFirst(6))
        XCTAssertTrue(json.hasPrefix("{"))
    }

    func testCancelStream() {
        let service = StreamingFormattingService(apiKeyProvider: { "test-key" })
        // Should not crash when cancelling without active stream
        service.cancelStream()
    }

    func testStreamFormatRequiresApiKey() async {
        let service = StreamingFormattingService(apiKeyProvider: { "" })
        var receivedError: Error?

        do {
            for try await _ in service.streamFormat(
                text: "test",
                systemPrompt: "test",
                textLanguage: .en,
                model: .gpt41Nano
            ) {
                XCTFail("Should not receive tokens without API key")
            }
        } catch {
            receivedError = error
        }

        XCTAssertNotNil(receivedError)
        if let recordingError = receivedError as? RecordingError {
            XCTAssertEqual(recordingError, .apiKeyNotConfigured)
        }
    }
}
