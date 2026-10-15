import Foundation

// MARK: - FormattingServiceProtocol (T021)

protocol FormattingServiceProtocol {
    /// Sends an already-assembled system prompt to the chat completions API.
    /// Callers are expected to have run `SystemPromptBuilder.build(_:)` before
    /// invoking this method — the service does NOT enhance or modify the
    /// `systemPrompt` it receives.
    func format(text: String, systemPrompt: String, textLanguage: SupportedLanguage, model: LLMModel) async throws -> String
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
        model: LLMModel
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

        // 014: callers pass an already-assembled prompt (via
        // `SystemPromptBuilder`). The service does NOT enhance it further.
        // `temperature` and `reasoning_effort` are set per exact model — see the
        // tables in `LLMModel.supportsTemperature` / `LLMModel.reasoningEffort`.
        var requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_completion_tokens": 4000
        ]
        if model.supportsTemperature {
            requestBody["temperature"] = 0.2
        }
        if let effort = model.reasoningEffort {
            requestBody["reasoning_effort"] = effort.rawValue
        }

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
            "temperature": model.supportsTemperature ? "0.2" : "omitted",
            "reasoningEffort": model.reasoningEffort?.rawValue ?? "omitted",
            "maxTokens": "4000",
            "systemPrompt": String(systemPrompt.prefix(200)),
            "userText": String(text.prefix(200))
        ])

        let result = try await performWithRetry(request: request, model: model)
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

    private func performWithRetry(request: URLRequest, model: LLMModel) async throws -> String {
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
                    let body = String(data: data, encoding: .utf8) ?? ""
                    log.error(
                        "Chat Completions API auth failed",
                        parameters: ["body": String(body.prefix(2000))],
                        errorCode: "401"
                    )
                    throw RecordingError.apiKeyNotConfigured
                case 429, 500...599:
                    let body = String(data: data, encoding: .utf8) ?? ""
                    log.error(
                        "Chat Completions API transient error",
                        parameters: [
                            "status": "\(httpResponse.statusCode)",
                            "attempt": "\(attempt + 1)",
                            "body": String(body.prefix(2000))
                        ],
                        errorCode: "\(httpResponse.statusCode)"
                    )
                    lastError = RecordingError.formattingFailed("Server error: \(httpResponse.statusCode)")
                    if attempt < maxRetries - 1 {
                        let delay = pow(2.0, Double(attempt))
                        try await Task.sleep(for: .seconds(delay))
                    }
                    continue
                default:
                    // 4xx other than 401 — surface OpenAI's error body so the log shows
                    // e.g. "Unsupported value: 'temperature' does not support 0.2 with
                    // this model. Only the default (1) value is supported." instead of
                    // just the HTTP status code.
                    let message = String(data: data, encoding: .utf8) ?? "Status \(httpResponse.statusCode)"
                    // spec 015 (FR-040): the model isn't available — say so, never fall back to another model
                    if RecordingError.isModelUnavailable(status: httpResponse.statusCode, body: message) {
                        let openAIError = RecordingError.openAIError(in: message)
                        log.error(
                            "Model unavailable",
                            parameters: [
                                "method": "format",
                                "model": model.rawValue,
                                "status": "\(httpResponse.statusCode)",
                                "message": String((openAIError.message ?? message).prefix(500))
                            ],
                            errorCode: openAIError.code ?? "\(httpResponse.statusCode)"
                        )
                        throw RecordingError.modelUnavailable(modelName: model.displayName, kind: .text)
                    }
                    log.error(
                        "Chat Completions API error",
                        parameters: [
                            "status": "\(httpResponse.statusCode)",
                            "body": String(message.prefix(2000))
                        ],
                        errorCode: "\(httpResponse.statusCode)"
                    )
                    throw RecordingError.formattingFailed(message)
                }
            } catch let error as RecordingError {
                // Retryable statuses (429, 5xx) `continue` above; any RecordingError thrown
                // inside the loop (4xx, empty response) is final — retrying a 400 only delays the error.
                throw error
            } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                throw RecordingError.networkUnavailable
            } catch {
                lastError = RecordingError.formattingFailed(error.localizedDescription)
            }
        }

        throw lastError
    }

    private func parseResponse(_ data: Data) throws -> String {
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = response.choices.first?.message.content, !content.isEmpty else {
            throw RecordingError.formattingFailed("Empty response from API")
        }
        return content
    }
}

// MARK: - Chat Completions response

private struct ChatResponse: Decodable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let message: ChatMessageContent
}

private struct ChatMessageContent: Decodable {
    let content: String
}
