import Foundation

// MARK: - ChatSessionProtocol

protocol ChatSessionProtocol {
    var messages: [ChatMessage] { get }
    func addMessage(_ message: ChatMessage)
    func updateLastAssistantContent(_ content: String)
    func prepareMessagesForLLM(maxTokenBudget: Int, systemPromptTokens: Int) -> [(role: String, content: String)]
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

    func prepareMessagesForLLM(maxTokenBudget: Int, systemPromptTokens: Int) -> [(role: String, content: String)] {
        let availableBudget = max(0, maxTokenBudget - systemPromptTokens)

        // Build system prompt message
        let systemContent = systemPrompt.contentForLanguage(voiceLanguage)
        var result: [(role: String, content: String)] = [
            ("system", "\(systemContent)\n\nЯзык ответа: \(textLanguage.displayName)")
        ]

        // Collect messages from newest to oldest (excluding system role)
        let conversationMessages = messages.filter { $0.role != .system }
        var selectedMessages: [(role: String, content: String)] = []
        var totalTokens = 0

        for message in conversationMessages.reversed() {
            let tokens = TokenEstimator.estimateTokens(message.content)
            if totalTokens + tokens > availableBudget {
                break
            }
            let apiRole: String
            switch message.role {
            case .system: continue
            case .transcription, .user: apiRole = "user"
            case .assistant: apiRole = "assistant"
            }
            selectedMessages.insert((apiRole, message.content), at: 0)
            totalTokens += tokens
        }

        result.append(contentsOf: selectedMessages)
        return result
    }

    func reset() {
        messages.removeAll()
        audioData = nil
    }
}
