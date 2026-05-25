# Internal Contracts (Protocols): 002-app-settings-onboarding

**Date**: 2026-03-05

## STTServiceProtocol

Protocol for speech recognition abstraction (cloud and local processing).

```swift
protocol STTServiceProtocol {
    /// Transcribe audio data into text
    /// - Parameters:
    ///   - audioData: WAV audio (for cloud) or nil (for streaming)
    ///   - language: recognition language
    /// - Returns: recognized text
    func transcribe(audioData: Data, language: SupportedLanguage) async throws -> String
}
```

**Implementations**:
- `TranscriptionService` (existing, cloud) — sends WAV to the OpenAI Whisper API
- `LocalSTTService` (new, local) — uses SpeechAnalyzer (macOS 26+)

## STTStreamingServiceProtocol

Extended protocol for streaming transcription (local only).

```swift
protocol STTStreamingServiceProtocol: STTServiceProtocol {
    /// Start streaming transcription from the microphone
    /// - Parameters:
    ///   - language: recognition language
    ///   - onPartialResult: callback with intermediate results
    func startStreaming(language: SupportedLanguage, onPartialResult: @escaping (String) -> Void) async throws

    /// Stop streaming and obtain the final result
    func stopStreaming() async throws -> String
}
```

## LLMServiceProtocol

Protocol for text processing abstraction (cloud and local processing).

```swift
protocol LLMServiceProtocol {
    /// Process text using a prompt
    /// - Parameters:
    ///   - text: input text to process
    ///   - systemPrompt: system instruction (user prompt)
    /// - Returns: processed text
    func process(text: String, systemPrompt: String) async throws -> String
}
```

**Implementations**:
- `FormattingService` (existing, cloud) — sends to the OpenAI Chat Completions API
- `LocalLLMService` (new, local) — uses Foundation Models (macOS 26+)

## ProcessingRouterProtocol

Protocol for routing requests between local and cloud processing.

```swift
protocol ProcessingRouterProtocol {
    /// Current STT mode
    var sttMode: ProcessingMode { get }

    /// Current LLM mode
    var llmMode: ProcessingMode { get }

    /// Whether local processing is available
    var isLocalAvailable: Bool { get }

    /// Transcribe audio via the current STT mode
    func transcribe(audioData: Data, language: SupportedLanguage) async throws -> String

    /// Process text via the current LLM mode
    func process(text: String, systemPrompt: String) async throws -> String
}
```

## OnboardingServiceProtocol

Protocol for managing onboarding.

```swift
protocol OnboardingServiceProtocol {
    /// Whether onboarding should be shown
    var shouldShowOnboarding: Bool { get }

    /// Current step
    var currentStep: OnboardingStep { get set }

    /// Complete onboarding
    func completeOnboarding()

    /// Reset onboarding (for debugging)
    func resetOnboarding()
}
```

## Errors

```swift
enum ProcessingError: LocalizedError {
    case localProcessingUnavailable   // Apple Intelligence unavailable
    case apiKeyMissing                // No API key for cloud mode
    case contextWindowExceeded        // Text too long for the local model (4096 tokens)
    case modelNotSupported(String)    // Server does not support the selected model
    case transcriptionFailed(Error)   // Transcription error
    case formattingFailed(Error)      // Formatting error
}
```
