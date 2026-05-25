import Foundation

// MARK: - APIKeyValidationServiceProtocol (T016)

protocol APIKeyValidationServiceProtocol {
    func validate(apiKey: String) async throws -> Bool
}

// MARK: - APIKeyValidationService

final class APIKeyValidationService: APIKeyValidationServiceProtocol {
    private let session: URLSession
    private let baseURL = "https://api.openai.com/v1/models"
    private let log = DiagnosticLogger.logger(for: .api)

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validate(apiKey: String) async throws -> Bool {
        guard !apiKey.isEmpty else { return false }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIKeyValidationError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            log.info("API key validation result", metadata: ["valid": "true"])
            return true
        case 401:
            log.info("API key validation result", metadata: ["valid": "false"])
            return false
        default:
            throw APIKeyValidationError.unexpectedStatus(httpResponse.statusCode)
        }
    }
}

// MARK: - APIKeyValidationError

enum APIKeyValidationError: LocalizedError {
    case invalidResponse
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return LocalizationManager.shared.string("error.invalidResponse")
        case .unexpectedStatus(let code):
            return LocalizationManager.shared.string("error.unexpectedStatus", args: code)
        }
    }
}
