import XCTest
@testable import Verborra

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol {
    static var mockResponses: [(data: Data, response: URLResponse, error: Error?)] = []
    static var requestCount = 0
    static var lastRequest: URLRequest?
    /// URLSession hands URLProtocol the body as a stream, so `lastRequest.httpBody` is nil.
    static var lastRequestBody: Data?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastRequestBody = request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        let index = min(Self.requestCount, Self.mockResponses.count - 1)
        Self.requestCount += 1

        guard index >= 0, index < Self.mockResponses.count else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let mock = Self.mockResponses[index]
        if let error = mock.error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocol(self, didReceive: mock.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: mock.data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    static func reset() {
        mockResponses = []
        requestCount = 0
        lastRequest = nil
        lastRequestBody = nil
    }
}

final class TranscriptionServiceTests: XCTestCase {
    var service: TranscriptionService!
    var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        service = TranscriptionService(apiKeyProvider: { "sk-test-key-12345678901234567890" }, session: session)
    }

    func testSuccessfulTranscription() async throws {
        let responseData = Data(#"{"text": "Привет мир"}"#.utf8)
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseData, response, nil)]

        let result = try await service.transcribe(audioData: Data([0, 1, 2]), language: .ru, model: .gptTranscribe)
        XCTAssertEqual(result, "Привет мир")
    }

    func testEmptyApiKeyThrows() async {
        let service = TranscriptionService(apiKeyProvider: { "" }, session: session)
        do {
            _ = try await service.transcribe(audioData: Data(), language: nil, model: .gptTranscribe)
            XCTFail("Should throw")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .apiKeyNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSilenceDetected() async {
        let responseData = Data(#"{"text": "  "}"#.utf8)
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseData, response, nil)]

        do {
            _ = try await service.transcribe(audioData: Data([0]), language: nil, model: .gptTranscribe)
            XCTFail("Should throw silenceDetected")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .silenceDetected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDifferentModelUsed() async throws {
        let responseData = Data(#"{"text": "Hello world"}"#.utf8)
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseData, response, nil)]

        let result = try await service.transcribe(audioData: Data([0, 1, 2]), language: .en, model: .gptTranscribe)
        XCTAssertEqual(result, "Hello world")
    }

    func testNilLanguageAccepted() async throws {
        let responseData = Data(#"{"text": "Test"}"#.utf8)
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseData, response, nil)]

        let result = try await service.transcribe(audioData: Data([0, 1, 2]), language: nil, model: .gptTranscribe)
        XCTAssertEqual(result, "Test")
    }

    func testUnauthorizedThrows() async {
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(Data(), response, nil)]

        do {
            _ = try await service.transcribe(audioData: Data([0]), language: nil, model: .gptTranscribe)
            XCTFail("Should throw")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .apiKeyNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - V017: Extended Tests

    func testMultipartFormDataBody() async throws {
        let responseData = Data(#"{"text": "Hello"}"#.utf8)
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseData, response, nil)]

        _ = try await service.transcribe(audioData: Data([0, 1, 2]), language: .en, model: .gptTranscribe)

        let request = MockURLProtocol.lastRequest!
        let contentType = request.value(forHTTPHeaderField: "Content-Type")!
        XCTAssertTrue(contentType.contains("multipart/form-data"))
        XCTAssertTrue(contentType.contains("boundary="))

        let bodyString = String(data: MockURLProtocol.lastRequestBody!, encoding: .utf8)!
        XCTAssertTrue(bodyString.contains("name=\"file\""), "Body should contain file field")
        XCTAssertTrue(bodyString.contains("name=\"model\""), "Body should contain model field")
        XCTAssertTrue(bodyString.contains("gpt-transcribe"), "Body should contain model value")
        XCTAssertTrue(bodyString.contains("name=\"response_format\""), "Body should contain response_format field")
        XCTAssertTrue(bodyString.contains("json"), "Body should contain json response_format value")
        XCTAssertTrue(bodyString.contains("name=\"languages[]\""), "Body should contain languages[] field")
    }

    func testRetryOn429() async throws {
        let error429Response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 429, httpVersion: nil, headerFields: nil)!
        let successData = Data(#"{"text": "Retried OK"}"#.utf8)
        let successResponse = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockResponses = [
            (Data(), error429Response, nil),
            (successData, successResponse, nil)
        ]

        let result = try await service.transcribe(audioData: Data([0, 1, 2]), language: nil, model: .gptTranscribe)
        XCTAssertEqual(result, "Retried OK")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testRetryOn500() async throws {
        let error500Response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let successData = Data(#"{"text": "Server recovered"}"#.utf8)
        let successResponse = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockResponses = [
            (Data(), error500Response, nil),
            (successData, successResponse, nil)
        ]

        let result = try await service.transcribe(audioData: Data([0, 1, 2]), language: nil, model: .gptTranscribe)
        XCTAssertEqual(result, "Server recovered")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testNoRetryOn400() async {
        let error400Response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 400, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [
            (Data("Bad request".utf8), error400Response, nil)
        ]

        do {
            _ = try await service.transcribe(audioData: Data([0]), language: nil, model: .gptTranscribe)
            XCTFail("Should throw on 400")
        } catch let error as RecordingError {
            if case .transcriptionFailed = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(MockURLProtocol.requestCount, 1, "Should not retry on 400")
    }

    func testTimeoutConfiguration() async throws {
        let responseData = Data(#"{"text": "Timeout test"}"#.utf8)
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseData, response, nil)]

        _ = try await service.transcribe(audioData: Data([0, 1, 2]), language: nil, model: .gptTranscribe)

        let request = MockURLProtocol.lastRequest!
        XCTAssertEqual(request.timeoutInterval, 60, "Request timeout should be 60 seconds")
    }

    // MARK: - GPT Transcribe request shape (spec 015, T026)

    private func multipartBody(language: SupportedLanguage?, responseJSON: String = #"{"text": "OK"}"#) async throws -> (body: String, result: String) {
        MockURLProtocol.reset()
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(Data(responseJSON.utf8), response, nil)]
        let result = try await service.transcribe(audioData: Data([0, 1, 2]), language: language, model: .gptTranscribe)
        return (String(bytes: MockURLProtocol.lastRequestBody ?? Data(), encoding: .utf8) ?? "", result)
    }

    func testLanguageIsSentAsLanguagesArray() async throws {
        let body = try await multipartBody(language: .ru).body
        XCTAssertTrue(body.contains("name=\"languages[]\"\r\n\r\nru\r\n"), body)
        XCTAssertFalse(body.contains("name=\"language\""))
    }

    func testNoLanguageFieldWhenAuto() async throws {
        let body = try await multipartBody(language: nil).body
        XCTAssertFalse(body.contains("name=\"languages[]\""))
        XCTAssertFalse(body.contains("name=\"language\""))
    }

    func testModelAndResponseFormatFields() async throws {
        let body = try await multipartBody(language: .en).body
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ngpt-transcribe\r\n"))
        XCTAssertTrue(body.contains("name=\"response_format\"\r\n\r\njson\r\n"))
    }

    func testResponseWithLanguagesArrayParses() async throws {
        let result = try await multipartBody(
            language: .ru,
            responseJSON: #"{"text":"привет","languages":[{"code":"ru"}]}"#
        ).result
        XCTAssertEqual(result, "привет")
    }

    // MARK: - Model unavailable (spec 015, T089)

    private func transcribeError(status: Int, body: String) async -> Error? {
        MockURLProtocol.reset()
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(Data(body.utf8), response, nil)]
        do {
            _ = try await service.transcribe(audioData: Data([0]), language: nil, model: .gptTranscribe)
            return nil
        } catch {
            return error
        }
    }

    func testTranscriptionModelNotFound404() async {
        let error = await transcribeError(status: 404, body: "{}")
        XCTAssertEqual(error as? RecordingError, .modelUnavailable(modelName: "GPT Transcribe", kind: .speechToText))
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testTranscriptionModelNotFound400() async {
        let error = await transcribeError(status: 400, body: #"{"error":{"code":"model_not_available"}}"#)
        XCTAssertEqual(error as? RecordingError, .modelUnavailable(modelName: "GPT Transcribe", kind: .speechToText))
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testTranscriptionOther400StaysFailed() async {
        let error = await transcribeError(status: 400, body: #"{"error":{"code":"invalid_value"}}"#)
        guard case .transcriptionFailed = error as? RecordingError else { return XCTFail("got \(String(describing: error))") }
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }
}
