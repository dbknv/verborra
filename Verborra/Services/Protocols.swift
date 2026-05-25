import Foundation

// MARK: - STTServiceProtocol

protocol STTServiceProtocol {
    func transcribe(audioData: Data, language: SupportedLanguage) async throws -> String
}

// MARK: - LLMServiceProtocol

protocol LLMServiceProtocol {
    func process(text: String, systemPrompt: String) async throws -> String
}

// MARK: - ProcessingRouterProtocol

protocol ProcessingRouterProtocol {
    func transcribe(audioData: Data, language: SupportedLanguage) async throws -> String
    func process(text: String, systemPrompt: String) async throws -> String
}
