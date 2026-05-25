import Foundation

// MARK: - FormattingServiceProtocol (T021)

protocol FormattingServiceProtocol {
    func format(text: String, systemPrompt: String, textLanguage: SupportedLanguage, model: LLMModel, vocabularyEntries: [VocabularyEntry], personalPreferences: String) async throws -> String
}

extension FormattingServiceProtocol {
    func format(text: String, systemPrompt: String, textLanguage: SupportedLanguage, model: LLMModel) async throws -> String {
        try await format(text: text, systemPrompt: systemPrompt, textLanguage: textLanguage, model: model, vocabularyEntries: [], personalPreferences: "")
    }
}

// MARK: - FormattingService

final class FormattingService: FormattingServiceProtocol, LLMServiceProtocol {
    private let apiKeyProvider: () -> String
    private let session: URLSession
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let maxRetries = 3
    private let log = DiagnosticLogger.logger(for: .api)

    init(apiKeyProvider: @escaping () -> String, session: URLSession = .shared) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    // LLMServiceProtocol conformance (uses default model and Russian)
    func process(text: String, systemPrompt: String) async throws -> String {
        try await format(text: text, systemPrompt: systemPrompt, textLanguage: .ru, model: .default)
    }

    func format(
        text: String,
        systemPrompt: String,
        textLanguage: SupportedLanguage,
        model: LLMModel,
        vocabularyEntries: [VocabularyEntry] = [],
        personalPreferences: String = ""
    ) async throws -> String {
        // T040: INFO — начало запроса
        log.info("Chat Completions API request", metadata: [
            "url": baseURL,
            "method": "POST",
            "model": model.rawValue,
            "textLength": "\(text.count) chars"
        ])
        log.debug("Chat Completions request details", metadata: [
            "systemPromptLength": "\(systemPrompt.count) chars",
            "textLanguage": textLanguage.displayName
        ])
        let requestStart = Date()

        let apiKey = apiKeyProvider()
        guard !apiKey.isEmpty else {
            log.error("API key not configured", errorCode: "apiKeyNotConfigured")
            throw RecordingError.apiKeyNotConfigured
        }

        let promptEnhancer = PromptEnhancer()
        let fullSystemPrompt = promptEnhancer.enhance(
            basePrompt: systemPrompt,
            textLanguage: textLanguage,
            vocabularyEntries: vocabularyEntries,
            personalPreferences: personalPreferences
        )

        let requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                ["role": "system", "content": fullSystemPrompt],
                ["role": "user", "content": text],
            ],
            "temperature": 0.2,
            "max_completion_tokens": 4000,
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // T040: DEBUG — заголовки, тело запроса
        log.debug("Chat Completions request body", metadata: [
            "headers": SensitiveMasker.maskHeaders(request.allHTTPHeaderFields ?? [:]).description,
            "model": model.rawValue,
            "temperature": "0.2",
            "maxTokens": "4000",
            "systemPrompt": String(fullSystemPrompt.prefix(200)),
            "userText": String(text.prefix(200))
        ])

        let result = try await performWithRetry(request: request)
        let elapsed = Date().timeIntervalSince(requestStart)
        log.info("Chat Completions API response", metadata: [
            "status": "200",
            "elapsed": String(format: "%.2fs", elapsed),
            "resultLength": "\(result.count) chars"
        ])
        log.debug("Chat Completions response body", metadata: [
            "content": String(result.prefix(500))
        ])
        return result
    }

    private func performWithRetry(request: URLRequest) async throws -> String {
        var lastError: Error = RecordingError.formattingFailed("Unknown error")

        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw RecordingError.formattingFailed("Invalid response")
                }

                switch httpResponse.statusCode {
                case 200:
                    return try parseResponse(data)
                case 401:
                    throw RecordingError.apiKeyNotConfigured
                case 429, 500...599:
                    lastError = RecordingError.formattingFailed("Server error: \(httpResponse.statusCode)")
                    if attempt < maxRetries - 1 {
                        let delay = pow(2.0, Double(attempt))
                        try await Task.sleep(for: .seconds(delay))
                    }
                    continue
                default:
                    let message = String(data: data, encoding: .utf8) ?? "Status \(httpResponse.statusCode)"
                    throw RecordingError.formattingFailed(message)
                }
            } catch let error as RecordingError {
                switch error {
                case .apiKeyNotConfigured:
                    throw error
                default:
                    lastError = error
                }
            } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                throw RecordingError.networkUnavailable
            } catch {
                lastError = RecordingError.formattingFailed(error.localizedDescription)
            }
        }

        throw lastError
    }

    private func parseResponse(_ data: Data) throws -> String {
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = response.choices.first?.message.content, !content.isEmpty else {
            throw RecordingError.formattingFailed("Empty response from API")
        }
        return content
    }
}
