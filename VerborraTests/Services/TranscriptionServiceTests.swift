import XCTest
@testable import Verborra

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol {
    static var mockResponses: [(data: Data, response: URLResponse, error: Error?)] = []
    static var requestCount = 0
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
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

    static func reset() {
        mockResponses = []
        requestCount = 0
        lastRequest = nil
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
        let responseData = #"{"text": "Привет мир"}"#.data(using: .utf8)!
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseData, response, nil)]

        let result = try await service.transcribe(audioData: Data([0, 1, 2]), language: .ru, model: .gpt4oMiniTranscribe)
        XCTAssertEqual(result, "Привет мир")
    }

    func testEmptyApiKeyThrows() async {
        let service = TranscriptionService(apiKeyProvider: { "" }, session: session)
        do {
            _ = try await service.transcribe(audioData: Data(), language: nil, model: .whisper1)
            XCTFail("Should throw")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .apiKeyNotConfigured)
        }
    }

    func testSilenceDetected() async {
        let responseData = #"{"text": "  "}"#.data(using: .utf8)!
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseData, response, nil)]

        do {
            _ = try await service.transcribe(audioData: Data([0]), language: nil, model: .whisper1)
            XCTFail("Should throw silenceDetected")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .silenceDetected)
        }
    }

    func testDifferentModelUsed() async throws {
        let responseData = #"{"text": "Hello world"}"#.data(using: .utf8)!
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseData, response, nil)]

        let result = try await service.transcribe(audioData: Data([0, 1, 2]), language: .en, model: .whisper1)
        XCTAssertEqual(result, "Hello world")
    }

    func testNilLanguageAccepted() async throws {
        let responseData = #"{"text": "Test"}"#.data(using: .utf8)!
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseData, response, nil)]

        let result = try await service.transcribe(audioData: Data([0, 1, 2]), language: nil, model: .gpt4oTranscribe)
        XCTAssertEqual(result, "Test")
    }

    func testUnauthorizedThrows() async {
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(Data(), response, nil)]

        do {
            _ = try await service.transcribe(audioData: Data([0]), language: nil, model: .whisper1)
            XCTFail("Should throw")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .apiKeyNotConfigured)
        }
    }

    // MARK: - V017: Extended Tests

    func testMultipartFormDataBody() async throws {
        let responseData = #"{"text": "Hello"}"#.data(using: .utf8)!
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseData, response, nil)]

        _ = try await service.transcribe(audioData: Data([0, 1, 2]), language: .en, model: .whisper1)

        let request = MockURLProtocol.lastRequest!
        let contentType = request.value(forHTTPHeaderField: "Content-Type")!
        XCTAssertTrue(contentType.contains("multipart/form-data"))
        XCTAssertTrue(contentType.contains("boundary="))

        let bodyString = String(data: request.httpBody!, encoding: .utf8)!
        XCTAssertTrue(bodyString.contains("name=\"file\""), "Body should contain file field")
        XCTAssertTrue(bodyString.contains("name=\"model\""), "Body should contain model field")
        XCTAssertTrue(bodyString.contains("whisper-1"), "Body should contain model value")
        XCTAssertTrue(bodyString.contains("name=\"response_format\""), "Body should contain response_format field")
        XCTAssertTrue(bodyString.contains("json"), "Body should contain json response_format value")
        XCTAssertTrue(bodyString.contains("name=\"language\""), "Body should contain language field")
    }

    func testRetryOn429() async throws {
        let error429Response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 429, httpVersion: nil, headerFields: nil)!
        let successData = #"{"text": "Retried OK"}"#.data(using: .utf8)!
        let successResponse = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockResponses = [
            (Data(), error429Response, nil),
            (successData, successResponse, nil),
        ]

        let result = try await service.transcribe(audioData: Data([0, 1, 2]), language: nil, model: .whisper1)
        XCTAssertEqual(result, "Retried OK")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testRetryOn500() async throws {
        let error500Response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let successData = #"{"text": "Server recovered"}"#.data(using: .utf8)!
        let successResponse = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockResponses = [
            (Data(), error500Response, nil),
            (successData, successResponse, nil),
        ]

        let result = try await service.transcribe(audioData: Data([0, 1, 2]), language: nil, model: .whisper1)
        XCTAssertEqual(result, "Server recovered")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testNoRetryOn400() async {
        let error400Response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 400, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [
            ("Bad request".data(using: .utf8)!, error400Response, nil),
        ]

        do {
            _ = try await service.transcribe(audioData: Data([0]), language: nil, model: .whisper1)
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
        let responseData = #"{"text": "Timeout test"}"#.data(using: .utf8)!
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(responseData, response, nil)]

        _ = try await service.transcribe(audioData: Data([0, 1, 2]), language: nil, model: .whisper1)

        let request = MockURLProtocol.lastRequest!
        XCTAssertEqual(request.timeoutInterval, 60, "Request timeout should be 60 seconds")
    }
}
