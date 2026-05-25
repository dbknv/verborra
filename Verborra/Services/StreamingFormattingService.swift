import Foundation

// MARK: - StreamingFormattingServiceProtocol

protocol StreamingFormattingServiceProtocol: FormattingServiceProtocol {
    func streamFormat(
        text: String,
        systemPrompt: String,
        textLanguage: SupportedLanguage,
        model: LLMModel,
        vocabularyEntries: [VocabularyEntry],
        personalPreferences: String
    ) -> AsyncThrowingStream<String, Error>

    func streamChat(
        messages: [(role: String, content: String)],
        model: LLMModel
    ) -> AsyncThrowingStream<String, Error>

    func cancelStream()
}

extension StreamingFormattingServiceProtocol {
    func streamFormat(text: String, systemPrompt: String, textLanguage: SupportedLanguage, model: LLMModel) -> AsyncThrowingStream<String, Error> {
        streamFormat(text: text, systemPrompt: systemPrompt, textLanguage: textLanguage, model: model, vocabularyEntries: [], personalPreferences: "")
    }
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
        model: LLMModel,
        vocabularyEntries: [VocabularyEntry] = [],
        personalPreferences: String = ""
    ) async throws -> String {
        var result = ""
        for try await token in streamFormat(
            text: text, systemPrompt: systemPrompt, textLanguage: textLanguage,
            model: model, vocabularyEntries: vocabularyEntries, personalPreferences: personalPreferences
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
        model: LLMModel,
        vocabularyEntries: [VocabularyEntry] = [],
        personalPreferences: String = ""
    ) -> AsyncThrowingStream<String, Error> {
        let promptEnhancer = PromptEnhancer()
        let fullSystemPrompt = promptEnhancer.enhance(
            basePrompt: systemPrompt,
            textLanguage: textLanguage,
            vocabularyEntries: vocabularyEntries,
            personalPreferences: personalPreferences
        )
        let messages: [(role: String, content: String)] = [
            ("system", fullSystemPrompt),
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
                        "temperature": "0.2",
                        "maxTokens": "4000",
                        "systemPrompt": String((messages.first(where: { $0.role == "system" })?.content ?? "").prefix(500)),
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
                        self.log.error("Streaming API auth failed", errorCode: "401")
                        throw RecordingError.apiKeyNotConfigured
                    default:
                        self.log.error("Streaming API error", parameters: ["status": "\(httpResponse.statusCode)"], errorCode: "\(httpResponse.statusCode)")
                        throw RecordingError.formattingFailed("Server error: \(httpResponse.statusCode)")
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

        let requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": messagePayload,
            "temperature": 0.2,
            "max_completion_tokens": 4000,
            "stream": true,
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        return request
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
