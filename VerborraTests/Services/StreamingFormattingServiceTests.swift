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
                model: .gpt52
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

    // MARK: - Request shape per model (spec 015, T022)

    private func requestBody(for model: LLMModel) throws -> [String: Any] {
        let service = StreamingFormattingService(apiKeyProvider: { "sk-test" })
        let request = try service.buildRequest(messages: [("system", "Format"), ("user", "hello")], model: model)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testGPT6LunaStreamingRequest() throws {
        let body = try requestBody(for: .gpt6Luna)
        XCTAssertEqual(body["reasoning_effort"] as? String, "none")
        XCTAssertNil(body["temperature"])
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 4000)
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    func testGPT61SolAndAstraStreamingRequest() throws {
        for model in [LLMModel.gpt61Sol, .gpt6Astra] {
            let body = try requestBody(for: model)
            XCTAssertEqual(body["reasoning_effort"] as? String, "low", "\(model)")
            XCTAssertNil(body["temperature"], "\(model)")
            XCTAssertEqual(body["max_completion_tokens"] as? Int, 4000, "\(model)")
            XCTAssertEqual(body["stream"] as? Bool, true, "\(model)")
        }
    }

    func testGPT52StreamingRequest() throws {
        let body = try requestBody(for: .gpt52)
        XCTAssertEqual(body["temperature"] as? Double, 0.2)
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 4000)
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    // MARK: - Model unavailable (spec 015, T089)

    private func streamError(status: Int, body: String) async -> Error? {
        MockURLProtocol.reset()
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(body.data(using: .utf8)!, response, nil)]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let service = StreamingFormattingService(apiKeyProvider: { "sk-test" }, session: URLSession(configuration: config))
        do {
            for try await _ in service.streamFormat(text: "t", systemPrompt: "p", textLanguage: .en, model: .gpt61Sol) {}
            return nil
        } catch {
            return error
        }
    }

    func testStreamingModelNotFound404() async {
        let error = await streamError(status: 404, body: "{}")
        XCTAssertEqual(error as? RecordingError, .modelUnavailable(modelName: "GPT-6.1 Sol", kind: .text))
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testStreamingModelNotFound400() async {
        let error = await streamError(status: 400, body: #"{"error":{"code":"model_not_found"}}"#)
        XCTAssertEqual(error as? RecordingError, .modelUnavailable(modelName: "GPT-6.1 Sol", kind: .text))
    }

    func testStreamingOther400StaysFormattingFailed() async {
        let error = await streamError(status: 400, body: #"{"error":{"code":"unsupported_value"}}"#)
        guard case .formattingFailed = error as? RecordingError else { return XCTFail("got \(String(describing: error))") }
    }
}
