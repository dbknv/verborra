import Foundation

final class ProcessingRouter: ProcessingRouterProtocol {
    private let sttService: any STTServiceProtocol
    private let llmService: any LLMServiceProtocol
    private let log = DiagnosticLogger.logger(for: .api)

    init(settings: AppSettings, apiKeyProvider: @escaping () -> String) {
        self.sttService = TranscriptionService(apiKeyProvider: apiKeyProvider)
        self.llmService = FormattingService(apiKeyProvider: apiKeyProvider)
    }

    init(
        sttService: any STTServiceProtocol,
        llmService: any LLMServiceProtocol
    ) {
        self.sttService = sttService
        self.llmService = llmService
    }

    func transcribe(audioData: Data, language: SupportedLanguage) async throws -> String {
        log.info("Processing route: STT", metadata: ["language": language.apiCode])
        let result = try await sttService.transcribe(audioData: audioData, language: language)
        log.info("STT completed", metadata: ["resultLength": "\(result.count) chars"])
        return result
    }

    func process(text: String, systemPrompt: String) async throws -> String {
        log.info("Processing route: LLM", metadata: ["textLength": "\(text.count) chars"])
        let result = try await llmService.process(text: text, systemPrompt: systemPrompt)
        log.info("LLM completed", metadata: ["resultLength": "\(result.count) chars"])
        return result
    }
}
