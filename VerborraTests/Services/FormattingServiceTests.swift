import XCTest
@testable import Verborra

// MARK: - FormattingServiceTests

final class FormattingServiceTests: XCTestCase {
    var service: FormattingService!
    var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        service = FormattingService(apiKeyProvider: { "sk-test-key-12345678901234567890" }, session: session)
    }

    func testSuccessfulFormatting() async throws {
        let responseJSON = """
        {
            "id": "chatcmpl-123",
            "choices": [{"message": {"role": "assistant", "content": "# Отформатированный текст"}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
        }
        """
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseJSON.data(using: .utf8)!, response, nil)]

        let result = try await service.format(text: "привет мир", systemPrompt: "Отформатируй", textLanguage: .ru, model: .gpt52)
        XCTAssertEqual(result, "# Отформатированный текст")
    }

    func testEmptyApiKeyThrows() async {
        let service = FormattingService(apiKeyProvider: { "" }, session: session)
        do {
            _ = try await service.format(text: "test", systemPrompt: "prompt", textLanguage: .en, model: .gpt52)
            XCTFail("Should throw")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .apiKeyNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDifferentModelAndLanguage() async throws {
        let responseJSON = """
        {
            "id": "chatcmpl-456",
            "choices": [{"message": {"role": "assistant", "content": "Formatted English text"}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
        }
        """
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseJSON.data(using: .utf8)!, response, nil)]

        let result = try await service.format(text: "hello", systemPrompt: "Format nicely", textLanguage: .en, model: .gpt52)
        XCTAssertEqual(result, "Formatted English text")
    }

    func testEmptyResponseThrows() async {
        let responseJSON = """
        {"id": "chatcmpl-123", "choices": [{"message": {"role": "assistant", "content": ""}, "finish_reason": "stop"}], "usage": {}}
        """
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseJSON.data(using: .utf8)!, response, nil)]

        do {
            _ = try await service.format(text: "test", systemPrompt: "prompt", textLanguage: .ru, model: .gpt52)
            XCTFail("Should throw")
        } catch let error as RecordingError {
            if case .formattingFailed = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - V018: Extended Tests

    func testRequestBodyContainsCorrectFields() async throws {
        let responseJSON = """
        {
            "id": "chatcmpl-789",
            "choices": [{"message": {"role": "assistant", "content": "Formatted"}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
        }
        """
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseJSON.data(using: .utf8)!, response, nil)]

        _ = try await service.format(text: "hello", systemPrompt: "Format", textLanguage: .en, model: .gpt52)

        let bodyData = MockURLProtocol.lastRequestBody!
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        XCTAssertEqual(body["model"] as? String, "gpt-5.2")
        XCTAssertEqual(body["temperature"] as? Double, 0.2)
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 4000)

        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "hello")
    }

    /// 014: callers assemble the prompt (SystemPromptBuilder adds the language); the service sends it unchanged.
    func testSystemPromptIsSentUnchanged() async throws {
        let responseJSON = """
        {
            "id": "chatcmpl-lang",
            "choices": [{"message": {"role": "assistant", "content": "Текст"}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
        }
        """
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseJSON.data(using: .utf8)!, response, nil)]

        _ = try await service.format(text: "тест", systemPrompt: "Отформатируй", textLanguage: .ru, model: .gpt52)

        let bodyData = MockURLProtocol.lastRequestBody!
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        let systemContent = messages[0]["content"]!

        XCTAssertEqual(systemContent, "Отформатируй")
    }

    func testTimeoutIs30Seconds() async throws {
        let responseJSON = """
        {
            "id": "chatcmpl-timeout",
            "choices": [{"message": {"role": "assistant", "content": "OK"}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
        }
        """
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseJSON.data(using: .utf8)!, response, nil)]

        _ = try await service.format(text: "test", systemPrompt: "prompt", textLanguage: .en, model: .gpt52)

        let request = MockURLProtocol.lastRequest!
        XCTAssertEqual(request.timeoutInterval, 30, "Request timeout should be 30 seconds")
    }

    func testRetryOn429() async throws {
        let error429Response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 429, httpVersion: nil, headerFields: nil)!
        let successJSON = """
        {
            "id": "chatcmpl-retry",
            "choices": [{"message": {"role": "assistant", "content": "After retry"}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
        }
        """
        let successResponse = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockResponses = [
            (Data(), error429Response, nil),
            (successJSON.data(using: .utf8)!, successResponse, nil)
        ]

        let result = try await service.format(text: "test", systemPrompt: "prompt", textLanguage: .en, model: .gpt52)
        XCTAssertEqual(result, "After retry")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testNoRetryOn401() async {
        let error401Response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [
            (Data(), error401Response, nil)
        ]

        do {
            _ = try await service.format(text: "test", systemPrompt: "prompt", textLanguage: .en, model: .gpt52)
            XCTFail("Should throw on 401")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .apiKeyNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(MockURLProtocol.requestCount, 1, "Should not retry on 401")
    }

    // MARK: - Request shape per model (spec 015, T021)

    private func requestBody(for model: LLMModel) async throws -> [String: Any] {
        MockURLProtocol.reset()
        let responseJSON = #"{"id": "x", "choices": [{"message": {"role": "assistant", "content": "OK"}, "finish_reason": "stop"}], "usage": {}}"#
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseJSON.data(using: .utf8)!, response, nil)]
        _ = try await service.format(text: "hello", systemPrompt: "Format", textLanguage: .en, model: model)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(MockURLProtocol.lastRequestBody)) as? [String: Any])
    }

    func testGPT6LunaSendsReasoningEffortNoneWithoutTemperature() async throws {
        let body = try await requestBody(for: .gpt6Luna)
        XCTAssertEqual(body["reasoning_effort"] as? String, "none")
        XCTAssertNil(body["temperature"])
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 4000)
    }

    func testGPT61SolAndAstraSendReasoningEffortLow() async throws {
        for model in [LLMModel.gpt61Sol, .gpt6Astra] {
            let body = try await requestBody(for: model)
            XCTAssertEqual(body["reasoning_effort"] as? String, "low", "\(model)")
            XCTAssertNil(body["temperature"], "\(model)")
            XCTAssertEqual(body["max_completion_tokens"] as? Int, 4000, "\(model)")
        }
    }

    func testGPT52SendsTemperatureWithoutReasoningEffort() async throws {
        let body = try await requestBody(for: .gpt52)
        XCTAssertEqual(body["temperature"] as? Double, 0.2)
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 4000)
    }

    // MARK: - Model unavailable (spec 015, T089)

    private func formatError(status: Int, body: String) async -> Error? {
        MockURLProtocol.reset()
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(body.data(using: .utf8)!, response, nil)]
        do {
            _ = try await service.format(text: "t", systemPrompt: "p", textLanguage: .en, model: .gpt6Luna)
            return nil
        } catch {
            return error
        }
    }

    func testModelNotFound404() async {
        let error = await formatError(status: 404, body: #"{"error":{"message":"The model does not exist","code":"model_not_found"}}"#)
        XCTAssertEqual(error as? RecordingError, .modelUnavailable(modelName: "GPT-6 Luna", kind: .text))
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testModelNotFound400() async {
        let error = await formatError(status: 400, body: #"{"error":{"code":"model_not_found"}}"#)
        XCTAssertEqual(error as? RecordingError, .modelUnavailable(modelName: "GPT-6 Luna", kind: .text))
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testOther400StaysFormattingFailed() async {
        let error = await formatError(status: 400, body: #"{"error":{"code":"unsupported_value"}}"#)
        guard case .formattingFailed = error as? RecordingError else { return XCTFail("got \(String(describing: error))") }
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }
}
