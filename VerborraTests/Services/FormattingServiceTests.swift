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

        let result = try await service.format(text: "привет мир", systemPrompt: "Отформатируй", textLanguage: .ru, model: .gpt41Nano)
        XCTAssertEqual(result, "# Отформатированный текст")
    }

    func testEmptyApiKeyThrows() async {
        let service = FormattingService(apiKeyProvider: { "" }, session: session)
        do {
            _ = try await service.format(text: "test", systemPrompt: "prompt", textLanguage: .en, model: .gpt4oMini)
            XCTFail("Should throw")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .apiKeyNotConfigured)
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

        let result = try await service.format(text: "hello", systemPrompt: "Format nicely", textLanguage: .en, model: .gpt4oMini)
        XCTAssertEqual(result, "Formatted English text")
    }

    func testEmptyResponseThrows() async {
        let responseJSON = """
        {"id": "chatcmpl-123", "choices": [{"message": {"role": "assistant", "content": ""}, "finish_reason": "stop"}], "usage": {}}
        """
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseJSON.data(using: .utf8)!, response, nil)]

        do {
            _ = try await service.format(text: "test", systemPrompt: "prompt", textLanguage: .ru, model: .gpt41Nano)
            XCTFail("Should throw")
        } catch let error as RecordingError {
            if case .formattingFailed = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
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

        _ = try await service.format(text: "hello", systemPrompt: "Format", textLanguage: .en, model: .gpt41Nano)

        let request = MockURLProtocol.lastRequest!
        let bodyData = request.httpBody!
        let body = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]

        XCTAssertEqual(body["model"] as? String, "gpt-4.1-nano")
        XCTAssertEqual(body["temperature"] as? Double, 0.2)
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 4000)

        let messages = body["messages"] as! [[String: String]]
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "hello")
    }

    func testTextLanguageInSystemPrompt() async throws {
        let responseJSON = """
        {
            "id": "chatcmpl-lang",
            "choices": [{"message": {"role": "assistant", "content": "Текст"}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
        }
        """
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseJSON.data(using: .utf8)!, response, nil)]

        _ = try await service.format(text: "тест", systemPrompt: "Отформатируй", textLanguage: .ru, model: .gpt41Nano)

        let request = MockURLProtocol.lastRequest!
        let bodyData = request.httpBody!
        let body = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
        let messages = body["messages"] as! [[String: String]]
        let systemContent = messages[0]["content"]!

        XCTAssertTrue(systemContent.contains("Язык ответа: Русский"), "System prompt should contain language: got \(systemContent)")
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

        _ = try await service.format(text: "test", systemPrompt: "prompt", textLanguage: .en, model: .gpt41Nano)

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
            (successJSON.data(using: .utf8)!, successResponse, nil),
        ]

        let result = try await service.format(text: "test", systemPrompt: "prompt", textLanguage: .en, model: .gpt41Nano)
        XCTAssertEqual(result, "After retry")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testNoRetryOn401() async {
        let error401Response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [
            (Data(), error401Response, nil),
        ]

        do {
            _ = try await service.format(text: "test", systemPrompt: "prompt", textLanguage: .en, model: .gpt41Nano)
            XCTFail("Should throw on 401")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .apiKeyNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(MockURLProtocol.requestCount, 1, "Should not retry on 401")
    }
}
