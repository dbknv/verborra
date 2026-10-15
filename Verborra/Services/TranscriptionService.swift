import Foundation

// MARK: - TranscriptionServiceProtocol (T020)

protocol TranscriptionServiceProtocol {
    func transcribe(audioData: Data, language: SupportedLanguage?, model: STTModel) async throws -> String
}

// MARK: - TranscriptionService

final class TranscriptionService: TranscriptionServiceProtocol, STTServiceProtocol {
    private let apiKeyProvider: () -> String
    private let session: URLSession
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"
    private let maxRetries = 3
    private let log = DiagnosticLogger.logger(for: .api)

    init(apiKeyProvider: @escaping () -> String, session: URLSession = .shared) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    // STTServiceProtocol conformance (uses default STT model)
    func transcribe(audioData: Data, language: SupportedLanguage) async throws -> String {
        try await transcribe(audioData: audioData, language: language, model: .default)
    }

    func transcribe(audioData: Data, language: SupportedLanguage?, model: STTModel) async throws -> String {
        // T039: INFO — начало запроса
        log.info("Transcription API request", metadata: [
            "url": baseURL,
            "method": "POST",
            "payloadSize": "\(audioData.count) bytes",
            "model": model.rawValue,
            "language": language?.apiCode ?? "auto"
        ])
        let requestStart = Date()

        let apiKey = apiKeyProvider()
        guard !apiKey.isEmpty else {
            log.error("API key not configured", errorCode: "apiKeyNotConfigured")
            throw RecordingError.apiKeyNotConfigured
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body = Data()

        // file field
        body.appendMultipart(boundary: boundary, name: "file", filename: "audio.wav", mimeType: "audio/wav", data: audioData)

        // model field
        body.appendMultipart(boundary: boundary, name: "model", value: model.rawValue)

        // language field: name depends on the model (FR-033)
        let languageFieldName: String
        switch model.languageField {
        case .singular: languageFieldName = "language"
        case .languagesArray: languageFieldName = "languages[]"
        }
        if let language {
            body.appendMultipart(boundary: boundary, name: languageFieldName, value: language.apiCode)
        }

        // response_format
        body.appendMultipart(boundary: boundary, name: "response_format", value: "json")

        body.append(Data("--\(boundary)--\r\n".utf8))
        request.httpBody = body

        // T039: DEBUG — заголовки и параметры запроса
        log.debug("Transcription API request details", metadata: [
            "headers": SensitiveMasker.maskHeaders(request.allHTTPHeaderFields ?? [:]).description,
            "model": model.rawValue,
            "language": language?.apiCode ?? "auto",
            "languageField": languageFieldName,
            "responseFormat": "json",
            "audioSize": "\(audioData.count) bytes"
        ])

        let result = try await performWithRetry(request: request, model: model)
        let elapsed = Date().timeIntervalSince(requestStart)
        log.info("Transcription API response", metadata: [
            "status": "200",
            "elapsed": String(format: "%.2fs", elapsed),
            "resultLength": "\(result.count) chars"
        ])
        log.debug("Transcription API response body", metadata: [
            "transcription": String(result.prefix(500))
        ])
        return result
    }

    private func performWithRetry(request: URLRequest, model: STTModel) async throws -> String {
        var lastError: Error = RecordingError.transcriptionFailed("Unknown error")

        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw RecordingError.transcriptionFailed("Invalid response")
                }

                switch httpResponse.statusCode {
                case 200:
                    return try parseResponse(data)
                case 401:
                    throw RecordingError.apiKeyNotConfigured
                case 400:
                    // V009: Don't retry on 400 (client error)
                    let message = String(data: data, encoding: .utf8) ?? "Bad request"
                    try throwIfModelUnavailable(status: 400, body: message, model: model)
                    throw RecordingError.transcriptionFailed(message)
                case 413:
                    throw RecordingError.fileSizeLimitReached
                case 429, 500...599:
                    lastError = RecordingError.transcriptionFailed("Server error: \(httpResponse.statusCode)")
                    if attempt < maxRetries - 1 {
                        let delay = pow(2.0, Double(attempt))
                        try await Task.sleep(for: .seconds(delay))
                    }
                    continue
                default:
                    let message = String(data: data, encoding: .utf8) ?? "Status \(httpResponse.statusCode)"
                    try throwIfModelUnavailable(status: httpResponse.statusCode, body: message, model: model)
                    throw RecordingError.transcriptionFailed(message)
                }
            } catch let error as RecordingError {
                // Retryable statuses (429, 5xx) `continue` above; any RecordingError thrown
                // inside the loop (400, 401, 413, silence, bad response) is final (V009).
                throw error
            } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                throw RecordingError.networkUnavailable
            } catch {
                lastError = RecordingError.transcriptionFailed(error.localizedDescription)
            }
        }

        throw lastError
    }

    /// spec 015 (FR-040): the model isn't available — say so, never fall back to another model.
    private func throwIfModelUnavailable(status: Int, body: String, model: STTModel) throws {
        guard RecordingError.isModelUnavailable(status: status, body: body) else { return }
        let openAIError = RecordingError.openAIError(in: body)
        log.error(
            "Model unavailable",
            parameters: [
                "method": "transcribe",
                "model": model.rawValue,
                "status": "\(status)",
                "message": String((openAIError.message ?? body).prefix(500))
            ],
            errorCode: openAIError.code ?? "\(status)"
        )
        throw RecordingError.modelUnavailable(modelName: model.displayName, kind: .speechToText)
    }

    private func parseResponse(_ data: Data) throws -> String {
        struct TranscriptionResponse: Decodable {
            let text: String
        }
        let response = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        guard !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecordingError.silenceDetected
        }
        return response.text
    }
}

// MARK: - Data + Multipart

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append(Data("--\(boundary)\r\n".utf8))
        append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        append(data)
        append(Data("\r\n".utf8))
    }

    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append(Data("--\(boundary)\r\n".utf8))
        append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        append(Data("\(value)\r\n".utf8))
    }
}
