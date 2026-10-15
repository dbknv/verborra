import XCTest
@testable import Verborra

final class ChatSessionTests: XCTestCase {
    var session: ChatSession!

    override func setUp() {
        super.setUp()
        let prompt = SystemPrompt(name: "Test", content: "You are a test assistant")
        session = ChatSession(
            systemPrompt: prompt,
            voiceLanguage: .en,
            textLanguage: .ru
        )
    }

    func testAddMessage() {
        let message = ChatMessage(role: .user, content: "Hello")
        session.addMessage(message)
        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(session.messages.first?.content, "Hello")
    }

    func testLastAssistantMessage() {
        session.addMessage(ChatMessage(role: .user, content: "Hi"))
        session.addMessage(ChatMessage(role: .assistant, content: "Hello!"))
        session.addMessage(ChatMessage(role: .user, content: "How are you?"))

        XCTAssertEqual(session.lastAssistantMessage?.content, "Hello!")
    }

    func testLastAssistantMessageIsNilWhenNoAssistant() {
        session.addMessage(ChatMessage(role: .user, content: "Hi"))
        XCTAssertNil(session.lastAssistantMessage)
    }

    func testUpdateLastAssistantContent() {
        session.addMessage(ChatMessage(role: .assistant, content: ""))
        session.updateLastAssistantContent("Updated content")
        XCTAssertEqual(session.lastAssistantMessage?.content, "Updated content")
    }

    func testUpdateLastAssistantContentDoesNothingWithNoAssistant() {
        session.addMessage(ChatMessage(role: .user, content: "Hi"))
        session.updateLastAssistantContent("Should not appear")
        XCTAssertNil(session.lastAssistantMessage)
    }

    func testReset() {
        session.addMessage(ChatMessage(role: .user, content: "Hi"))
        session.addMessage(ChatMessage(role: .assistant, content: "Hello"))
        session.audioData = Data([1, 2, 3])

        session.reset()

        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertNil(session.audioData)
    }

    func testPrepareMessagesForLLM() {
        session.addMessage(ChatMessage(role: .user, content: "Translate this"))
        session.addMessage(ChatMessage(role: .assistant, content: "Here is the translation"))

        let budget = 10000
        let systemTokens = 100
        let messages = session.prepareMessagesForLLM(maxTokenBudget: budget, systemPromptTokens: systemTokens, isFirstVoiceTurn: false, answerQuestionsInFirstMessage: false)

        // System prompt + 2 messages
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0].role, "system")
        XCTAssertEqual(messages[1].role, "user")
        XCTAssertEqual(messages[2].role, "assistant")
    }

    func testPrepareMessagesTranscriptionRoleMapsToUser() {
        session.addMessage(ChatMessage(role: .transcription, content: "Dictated text"))

        let messages = session.prepareMessagesForLLM(maxTokenBudget: 10000, systemPromptTokens: 50, isFirstVoiceTurn: false, answerQuestionsInFirstMessage: false)

        XCTAssertEqual(messages.count, 2) // system + transcription-as-user
        XCTAssertEqual(messages[1].role, "user")
        XCTAssertEqual(messages[1].content, "Dictated text")
    }

    func testContextTruncationDropsOldMessages() {
        // Create many messages to exceed budget
        for i in 0..<25 {
            let role: ChatMessageRole = i % 2 == 0 ? .user : .assistant
            let content = String(repeating: "A", count: 300) // ~100 tokens each
            session.addMessage(ChatMessage(role: role, content: content))
        }

        // Tight budget: only few messages should fit
        let budget = 500 // ~500 tokens total
        let systemTokens = 100
        // First voice turn: the session's own prompt is the system message
        let messages = session.prepareMessagesForLLM(maxTokenBudget: budget, systemPromptTokens: systemTokens, isFirstVoiceTurn: true, answerQuestionsInFirstMessage: false)

        // Should have system prompt + only last few messages
        XCTAssertTrue(messages.count < 25 + 1) // less than all + system
        XCTAssertEqual(messages[0].role, "system")

        // System prompt is always first
        XCTAssertTrue(messages[0].content.contains("test assistant"))
    }

    func testSystemPromptAlwaysPreserved() {
        for _ in 0..<10 {
            session.addMessage(ChatMessage(role: .user, content: String(repeating: "X", count: 600)))
            session.addMessage(ChatMessage(role: .assistant, content: String(repeating: "Y", count: 600)))
        }

        let messages = session.prepareMessagesForLLM(maxTokenBudget: 300, systemPromptTokens: 50, isFirstVoiceTurn: false, answerQuestionsInFirstMessage: false)

        XCTAssertFalse(messages.isEmpty)
        XCTAssertEqual(messages[0].role, "system")
    }
}
