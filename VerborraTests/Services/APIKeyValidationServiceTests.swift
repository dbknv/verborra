import XCTest
@testable import Verborra

final class APIKeyValidationServiceTests: XCTestCase {
    var service: APIKeyValidationService!
    var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        service = APIKeyValidationService(session: session)
    }

    func testValidKeyReturnsTrue() async throws {
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com/v1/models")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(Data("{}".utf8), response, nil)]

        let result = try await service.validate(apiKey: "sk-valid-key-12345678901234567890")
        XCTAssertTrue(result)
    }

    func testInvalidKeyReturnsFalse() async throws {
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com/v1/models")!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(Data(), response, nil)]

        let result = try await service.validate(apiKey: "sk-invalid-key-1234567890123456")
        XCTAssertFalse(result)
    }

    func testNetworkErrorThrows() async {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockResponses = [(Data(), response, error)]

        do {
            _ = try await service.validate(apiKey: "sk-test-key-12345678901234567890")
            XCTFail("Should throw")
        } catch {
            // Expected network error
        }
    }
}
