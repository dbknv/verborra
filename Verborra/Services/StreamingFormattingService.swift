import Foundation

// MARK: - StreamingFormattingServiceProtocol

protocol StreamingFormattingServiceProtocol: FormattingServiceProtocol {
    /// Streams a chat completion using an already-assembled system prompt.
    /// Callers are expected to have run `SystemPromptBuilder.build(_:)` —
    /// this service does NOT enhance the `systemPrompt` it receives.
    func streamFormat(
        text: String,
        systemPrompt: String,
        textLanguage: SupportedLanguage,
        model: LLMModel
    ) -> AsyncThrowingStream<String, Error>

    func streamChat(
        messages: [(role: String, content: String)],
        model: LLMModel
    ) -> AsyncThrowingStream<String, Error>

    func cancelStream()
}

// MARK: - StreamingFormattingService

final class StreamingFormattingService: StreamingFormattingServiceProtocol {
    private let apiKeyProvider: () -> String
    private let session: URLSession
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private var currentTask: Task<Void, Never>?
    private let timeoutInterval: TimeInterval = 60
    private let log = DiagnosticLogger.logger(for: .api)

    init(apiKeyProvider: @escaping () -> String, session: URLSession = .shared) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    // MARK: - FormattingServiceProtocol (non-streaming fallback)

    func format(
        text: String,
        systemPrompt: String,
        textLanguage: SupportedLanguage,
        model: LLMModel
    ) async throws -> String {
        var result = ""
        for try await token in streamFormat(
            text: text, systemPrompt: systemPrompt, textLanguage: textLanguage, model: model
        ) {
            result += token
        }
        return result
    }

    // MARK: - Streaming

    func streamFormat(
        text: String,
        systemPrompt: String,
        textLanguage: SupportedLanguage,
        model: LLMModel
    ) -> AsyncThrowingStream<String, Error> {
        // 014: caller passes an already-assembled prompt (via
        // `SystemPromptBuilder`). The service does NOT enhance it further.
        let messages: [(role: String, content: String)] = [
            ("system", systemPrompt),
            ("user", text)
        ]
        return streamChat(messages: messages, model: model)
    }

    func streamChat(
        messages: [(role: String, content: String)],
        model: LLMModel
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    let request = try self.buildRequest(messages: messages, model: model)

                    // INFO — начало streaming запроса
                    self.log.info("Streaming Chat Completions request", metadata: [
                        "url": self.baseURL,
                        "method": "POST",
                        "model": model.rawValue,
                        "messageCount": "\(messages.count)"
                    ])
                    self.logRequestDetails(request, messages: messages, model: model)

                    let requestStart = Date()
                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw RecordingError.formattingFailed("Invalid response")
                    }

                    if httpResponse.statusCode != 200 {
                        throw await self.failure(status: httpResponse.statusCode, bytes: bytes, model: model)
                    }

                    var accumulated = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))

                        if json == "[DONE]" {
                            let elapsed = Date().timeIntervalSince(requestStart)
                            self.log.info("Streaming Chat Completions completed", metadata: [
                                "elapsed": String(format: "%.2fs", elapsed),
                                "resultLength": "\(accumulated.count) chars"
                            ])
                            self.log.debug("Streaming response body", metadata: [
                                "content": String(accumulated.prefix(500))
                            ])
                            continuation.finish()
                            return
                        }

                        if let token = self.parseSSEToken(json) {
                            accumulated += token
                            continuation.yield(token)
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapNetworkError(error))
                }
            }

            self.currentTask = task

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func cancelStream() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Private

    /// Internal (not private) so tests can check the request shape (spec 015, T022).
    func buildRequest(messages: [(role: String, content: String)], model: LLMModel) throws -> URLRequest {
        let apiKey = apiKeyProvider()
        guard !apiKey.isEmpty else {
            throw RecordingError.apiKeyNotConfigured
        }

        let messagePayload = messages.map { ["role": $0.role, "content": $0.content] }

        // `temperature` and `reasoning_effort` are set per exact model — see the
        // tables in `LLMModel.supportsTemperature` / `LLMModel.reasoningEffort`.
        // The shape matches `FormattingService.format` apart from `stream`.
        var requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": messagePayload,
            "max_completion_tokens": 4000,
            "stream": true
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
        request.timeoutInterval = timeoutInterval
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        return request
    }

    /// Drains the response byte stream into a UTF-8 string, capped at `cap`
    /// bytes. Used to surface OpenAI's HTTP error body (typically a small JSON
    /// payload like `{"error":{"message":"…","type":"invalid_request_error"}}`)
    /// in the diagnostic log when the streaming call returns a non-200 status.
    /// Silently truncates at the cap to avoid flooding the log on a runaway
    /// payload; failures while reading are swallowed and the partial body is
    /// returned (a partial error message is more useful than nothing).
    /// Lost or missing connectivity becomes `.networkUnavailable`; other errors pass through.
    private static func mapNetworkError(_ error: Error) -> Error {
        guard let urlError = error as? URLError,
              [.notConnectedToInternet, .networkConnectionLost].contains(urlError.code) else { return error }
        return RecordingError.networkUnavailable
    }

    /// DEBUG — детали запроса
    private func logRequestDetails(_ request: URLRequest, messages: [(role: String, content: String)], model: LLMModel) {
        log.debug("Streaming request details", metadata: [
            "headers": SensitiveMasker.maskHeaders(request.allHTTPHeaderFields ?? [:]).description,
            "model": model.rawValue,
            "temperature": model.supportsTemperature ? "0.2" : "omitted",
            "reasoningEffort": model.reasoningEffort?.rawValue ?? "omitted",
            "maxTokens": "4000",
            "systemPrompt": String((messages.first(where: { $0.role == "system" })?.content ?? "").prefix(4000)),
            "userText": String((messages.last(where: { $0.role == "user" })?.content ?? "").prefix(500))
        ])
    }

    /// Maps a non-200 response to the error to throw, logging OpenAI's message from the body.
    private func failure(status: Int, bytes: URLSession.AsyncBytes, model: LLMModel) async -> Error {
        if status == 401 {
            // Drain a small slice of the body to log the auth error message — useful
            // to distinguish "invalid key", "key revoked", "org not allowed" etc.
            let body = await Self.collectBody(bytes, cap: 2000)
            log.error("Streaming API auth failed", parameters: ["body": body], errorCode: "401")
            return RecordingError.apiKeyNotConfigured
        }
        // Drain the response body so OpenAI's actual error message is captured
        // in the diagnostic log (e.g. "Unsupported value: 'temperature' does
        // not support 0.2 with this model. Only the default (1) value is
        // supported."). Without this the log only shows the HTTP status code,
        // which is insufficient to root-cause 400/404/422 model-config errors.
        let body = await Self.collectBody(bytes, cap: 4000)
        // spec 015 (FR-040): the model isn't available — say so, never fall back to another model
        if RecordingError.isModelUnavailable(status: status, body: body) {
            let openAIError = RecordingError.openAIError(in: body)
            log.error(
                "Model unavailable",
                parameters: [
                    "method": "streamFormat",
                    "model": model.rawValue,
                    "status": "\(status)",
                    "message": String((openAIError.message ?? body).prefix(500))
                ],
                errorCode: openAIError.code ?? "\(status)"
            )
            return RecordingError.modelUnavailable(modelName: model.displayName, kind: .text)
        }
        log.error(
            "Streaming API error",
            parameters: [
                "status": "\(status)",
                "model": model.rawValue,
                "body": body
            ],
            errorCode: "\(status)"
        )
        return RecordingError.formattingFailed("Server error \(status): \(String(body.prefix(500)))")
    }

    private static func collectBody(_ bytes: URLSession.AsyncBytes, cap: Int) async -> String {
        var data = Data()
        data.reserveCapacity(min(cap, 4096))
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= cap { break }
            }
        } catch {
            // Connection may close mid-error; partial body still useful.
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parseSSEToken(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = parsed["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else {
            return nil
        }
        return content
    }
}
