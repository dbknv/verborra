import Foundation

// MARK: - ChatSessionProtocol

protocol ChatSessionProtocol {
    var messages: [ChatMessage] { get }
    func addMessage(_ message: ChatMessage)
    func updateLastAssistantContent(_ content: String)
    /// Builds the payload for an OpenAI Chat Completions request from this session.
    ///
    /// - Parameters:
    ///   - maxTokenBudget: total token budget for the message array.
    ///   - systemPromptTokens: estimated token cost of the system prompt (already accounted in budget).
    ///   - isFirstVoiceTurn: `true` only for the very first voice-transcribed turn of this session.
    ///   - answerQuestionsInFirstMessage: value of the active prompt's toggle.
    ///
    /// When `isFirstVoiceTurn && !answerQuestionsInFirstMessage`, the `DoNotAnswerInstruction`
    /// for the session's `voiceLanguage` is injected into the system message.
    /// History exceeding the budget is truncated from the oldest end **in user/assistant pairs**;
    /// an orphaned assistant at the head of the selection is also dropped.
    func prepareMessagesForLLM(
        maxTokenBudget: Int,
        systemPromptTokens: Int,
        isFirstVoiceTurn: Bool,
        answerQuestionsInFirstMessage: Bool
    ) -> [(role: String, content: String)]
    var lastAssistantMessage: ChatMessage? { get }
    func reset()
}

// MARK: - ChatSession

@Observable
final class ChatSession: ChatSessionProtocol {
    private(set) var messages: [ChatMessage] = []
    var systemPrompt: SystemPrompt
    var voiceLanguage: SupportedLanguage
    var textLanguage: SupportedLanguage
    var audioDevice: String?
    var audioData: Data?

    private let log = DiagnosticLogger.logger(for: .api)

    init(
        systemPrompt: SystemPrompt,
        voiceLanguage: SupportedLanguage,
        textLanguage: SupportedLanguage,
        audioDevice: String? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.voiceLanguage = voiceLanguage
        self.textLanguage = textLanguage
        self.audioDevice = audioDevice
    }

    func addMessage(_ message: ChatMessage) {
        messages.append(message)
    }

    func insertSystemMessage(_ message: ChatMessage) {
        messages.insert(message, at: 0)
    }

    var lastAssistantMessage: ChatMessage? {
        messages.last { $0.role == .assistant }
    }

    func updateLastAssistantContent(_ content: String) {
        guard let message = lastAssistantMessage else { return }
        message.content = content
    }

    func prepareMessagesForLLM(
        maxTokenBudget: Int,
        systemPromptTokens: Int,
        isFirstVoiceTurn: Bool,
        answerQuestionsInFirstMessage: Bool
    ) -> [(role: String, content: String)] {
        let availableBudget = max(0, maxTokenBudget - systemPromptTokens)

        // Build system prompt message (with optional do-not-answer injection).
        let basePrompt = systemPrompt.contentForLanguage(voiceLanguage)
        var systemContent = basePrompt
        if isFirstVoiceTurn && !answerQuestionsInFirstMessage {
            systemContent += "\n\n" + DoNotAnswerInstruction.text(for: voiceLanguage)
        }
        systemContent += "\n\nЯзык ответа: \(textLanguage.displayName)"
        var result: [(role: String, content: String)] = [("system", systemContent)]

        // Collect non-system messages and map roles for API.
        let conversationMessages = messages.filter { $0.role != .system }
        let apiMessages: [(role: String, content: String)] = conversationMessages.map { message in
            let apiRole: String
            switch message.role {
            case .system: apiRole = "system"                              // unreachable after filter
            case .transcription, .user: apiRole = "user"
            case .assistant: apiRole = "assistant"
            }
            return (apiRole, message.content)
        }

        // Walk from newest to oldest, accumulating into `selectedReversed`.
        // Stop when the next message would exceed the budget.
        var selectedReversed: [(role: String, content: String)] = []
        var totalTokens = 0
        for message in apiMessages.reversed() {
            let tokens = TokenEstimator.estimateTokens(message.content)
            if totalTokens + tokens > availableBudget {
                break
            }
            selectedReversed.append(message)
            totalTokens += tokens
        }

        // Flip to chronological order.
        var selected = Array(selectedReversed.reversed())

        // Enforce pair-truncation: drop any leading orphaned assistant(s) so the
        // selection always begins with a `user` message (or is empty).
        while let first = selected.first, first.role == "assistant" {
            selected.removeFirst()
        }

        result.append(contentsOf: selected)

        // T019 / Principle 6: surface enough to diagnose payload composition
        // without exposing user content at INFO level.
        let droppedCount = apiMessages.count - selected.count
        let injectedDoNotAnswer = isFirstVoiceTurn && !answerQuestionsInFirstMessage
        log.info("prepareMessagesForLLM done", metadata: [
            "messageCount": "\(result.count)",
            "droppedFromHistory": "\(droppedCount)",
            "isFirstVoiceTurn": "\(isFirstVoiceTurn)",
            "answerQuestionsInFirstMessage": "\(answerQuestionsInFirstMessage)",
            "injectedDoNotAnswer": "\(injectedDoNotAnswer)",
            "totalTokens": "\(totalTokens)",
            "availableBudget": "\(availableBudget)"
        ])
        log.debug("prepareMessagesForLLM system content", metadata: [
            "system": String(systemContent.prefix(2000))
        ])
        return result
    }

    func reset() {
        messages.removeAll()
        audioData = nil
    }
}
