import Testing
import Foundation
@testable import Verborra

// MARK: - Mocks

private final class MockSTTService: STTServiceProtocol {
    var resultText = "transcribed text"
    var error: Error?
    var callCount = 0

    func transcribe(audioData: Data, language: SupportedLanguage) async throws -> String {
        callCount += 1
        if let error { throw error }
        return resultText
    }
}

private final class MockLLMService: LLMServiceProtocol {
    var resultText = "formatted text"
    var error: Error?
    var callCount = 0

    func process(text: String, systemPrompt: String) async throws -> String {
        callCount += 1
        if let error { throw error }
        return resultText
    }
}

// MARK: - ProcessingRouter Tests

@Suite("ProcessingRouter Tests")
struct ProcessingRouterTests {
    private let testAudio = Data([0x00, 0x01, 0x02])

    @Test("Router delegates transcription to STT service")
    func transcribeRouting() async throws {
        let sttService = MockSTTService()
        sttService.resultText = "transcribed"

        let router = ProcessingRouter(
            sttService: sttService,
            llmService: MockLLMService()
        )

        let result = try await router.transcribe(audioData: testAudio, language: .ru)
        #expect(result == "transcribed")
        #expect(sttService.callCount == 1)
    }

    @Test("Router delegates processing to LLM service")
    func processRouting() async throws {
        let llmService = MockLLMService()
        llmService.resultText = "formatted"

        let router = ProcessingRouter(
            sttService: MockSTTService(),
            llmService: llmService
        )

        let result = try await router.process(text: "test", systemPrompt: "prompt")
        #expect(result == "formatted")
        #expect(llmService.callCount == 1)
    }

    @Test("Router propagates STT errors")
    func sttErrorPropagation() async throws {
        let sttService = MockSTTService()
        sttService.error = ProcessingError.apiKeyMissing

        let router = ProcessingRouter(
            sttService: sttService,
            llmService: MockLLMService()
        )

        do {
            _ = try await router.transcribe(audioData: testAudio, language: .ru)
            Issue.record("Expected ProcessingError to be thrown")
        } catch is ProcessingError {
            // Expected
        }
    }

    @Test("Router propagates LLM errors")
    func llmErrorPropagation() async throws {
        let llmService = MockLLMService()
        llmService.error = ProcessingError.apiKeyMissing

        let router = ProcessingRouter(
            sttService: MockSTTService(),
            llmService: llmService
        )

        do {
            _ = try await router.process(text: "test", systemPrompt: "prompt")
            Issue.record("Expected ProcessingError to be thrown")
        } catch is ProcessingError {
            // Expected
        }
    }
}
