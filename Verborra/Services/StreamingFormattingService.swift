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
            ("user", text),
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
                    // DEBUG — детали запроса
                    self.log.debug("Streaming request details", metadata: [
                        "headers": SensitiveMasker.maskHeaders(request.allHTTPHeaderFields ?? [:]).description,
                        "model": model.rawValue,
                        "temperature": model.supportsTemperature ? "0.2" : "omitted",
                        "maxTokens": "4000",
                        "systemPrompt": String((messages.first(where: { $0.role == "system" })?.content ?? "").prefix(4000)),
                        "userText": String((messages.last(where: { $0.role == "user" })?.content ?? "").prefix(500))
                    ])

                    let requestStart = Date()
                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw RecordingError.formattingFailed("Invalid response")
                    }

                    switch httpResponse.statusCode {
                    case 200:
                        break
                    case 401:
                        // Drain a small slice of the body to log the auth error message — useful
                        // to distinguish "invalid key", "key revoked", "org not allowed" etc.
                        let body = await Self.collectBody(bytes, cap: 2000)
                        self.log.error(
                            "Streaming API auth failed",
                            parameters: ["body": body],
                            errorCode: "401"
                        )
                        throw RecordingError.apiKeyNotConfigured
                    default:
                        // Drain the response body so OpenAI's actual error message is captured
                        // in the diagnostic log (e.g. "Unsupported value: 'temperature' does
                        // not support 0.2 with this model. Only the default (1) value is
                        // supported."). Without this the log only shows the HTTP status code,
                        // which is insufficient to root-cause 400/404/422 model-config errors.
                        let body = await Self.collectBody(bytes, cap: 4000)
                        self.log.error(
                            "Streaming API error",
                            parameters: [
                                "status": "\(httpResponse.statusCode)",
                                "model": model.rawValue,
                                "body": body
                            ],
                            errorCode: "\(httpResponse.statusCode)"
                        )
                        throw RecordingError.formattingFailed("Server error \(httpResponse.statusCode): \(String(body.prefix(500)))")
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
                } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                    continuation.finish(throwing: RecordingError.networkUnavailable)
                } catch {
                    continuation.finish(throwing: error)
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

    private func buildRequest(messages: [(role: String, content: String)], model: LLMModel) throws -> URLRequest {
        let apiKey = apiKeyProvider()
        guard !apiKey.isEmpty else {
            throw RecordingError.apiKeyNotConfigured
        }

        let messagePayload = messages.map { ["role": $0.role, "content": $0.content] }

        // GPT-5 reasoning models (`gpt-5-nano`, `gpt-5-mini`) reject any
        // `temperature` other than the default `1` with a 400; omit the key
        // entirely for them. See `LLMModel.supportsTemperature`.
        var requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": messagePayload,
            "max_completion_tokens": 4000,
            "stream": true,
        ]
        if model.supportsTemperature {
            requestBody["temperature"] = 0.2
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
