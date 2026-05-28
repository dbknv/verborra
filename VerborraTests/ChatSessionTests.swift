import XCTest
@testable import Verborra

// MARK: - ChatSessionTests (013-T007, T013)

/// Tests for `ChatSession.prepareMessagesForLLM` covering:
///   - FR-003 / FR-003a / FR-004 — do-not-answer injection (CON-3..CON-4, CON-7)
///   - FR-005 — full session history is included for continuation messages
///   - FR-006 — edited content is read at call time (CON-5)
///   - FR-007 — pair truncation when budget is exceeded (CON-6, SC-008)
///   - INV-3..INV-5 — system always first, last is `user`, no orphan assistant at the head
final class ChatSessionTests: XCTestCase {

    private func makeSession(
        promptContent: String = "BasePrompt",
        voice: SupportedLanguage = .ru,
        text: SupportedLanguage = .ru,
        isSystem: Bool = false,
        systemId: String? = nil
    ) -> ChatSession {
        let prompt = SystemPrompt(
            name: "P",
            content: promptContent,
            isSystem: isSystem,
            systemId: systemId
        )
        return ChatSession(
            systemPrompt: prompt,
            voiceLanguage: voice,
            textLanguage: text
        )
    }

    // MARK: - First-voice-turn injection

    func testInjection_whenFirstVoiceTurnAndAnswerOff_addsRussianInstruction() {
        let session = makeSession(voice: .ru)
        session.addMessage(ChatMessage(role: .transcription, content: "Hello?"))

        let payload = session.prepareMessagesForLLM(
            maxTokenBudget: 1000,
            systemPromptTokens: 10,
            isFirstVoiceTurn: true,
            answerQuestionsInFirstMessage: false
        )

        let system = payload.first!
        XCTAssertEqual(system.role, "system")
        XCTAssertTrue(
            system.content.contains("Не отвечай"),
            "Russian do-not-answer instruction must be injected"
        )
    }

    func testInjection_whenAnswerOn_doesNotAddInstruction() {
        let session = makeSession(voice: .ru)
        session.addMessage(ChatMessage(role: .transcription, content: "Hello?"))

        let payload = session.prepareMessagesForLLM(
            maxTokenBudget: 1000,
            systemPromptTokens: 10,
            isFirstVoiceTurn: true,
            answerQuestionsInFirstMessage: true
        )
        XCTAssertFalse(payload.first!.content.contains("Не отвечай"))
    }

    /// CON-4 / CON-7: subsequent voice turns must not re-inject the instruction.
    func testInjection_whenNotFirstVoiceTurn_doesNotAddInstruction() {
        let session = makeSession(voice: .en)
        session.addMessage(ChatMessage(role: .transcription, content: "anything"))

        let payload = session.prepareMessagesForLLM(
            maxTokenBudget: 1000,
            systemPromptTokens: 10,
            isFirstVoiceTurn: false,
            answerQuestionsInFirstMessage: false
        )
        XCTAssertFalse(payload.first!.content.contains("Do not answer"))
    }

    /// FR-005 refinement: continuation messages must NOT inherit the
    /// dictation-oriented system prompt — the user is chatting about the
    /// formatted output, not asking for more formatting. A minimal chat-mode
    /// system message replaces it.
    func testContinuation_dropsDictationPrompt_keepsChatMode() {
        // Session whose prompt content is a formatting instruction.
        let session = makeSession(
            promptContent: "Fix spelling errors and add punctuation. Return only the corrected text.",
            voice: .ru,
            text: .ru
        )
        session.addMessage(ChatMessage(role: .transcription, content: "Привет мир"))
        session.addMessage(ChatMessage(role: .assistant, content: "Привет, мир."))
        session.addMessage(ChatMessage(role: .user, content: "А что я хотел сказать?"))

        let payload = session.prepareMessagesForLLM(
            maxTokenBudget: 10_000,
            systemPromptTokens: 0,
            isFirstVoiceTurn: false,
            answerQuestionsInFirstMessage: false
        )

        let systemContent = payload.first!.content
        XCTAssertFalse(
            systemContent.contains("Fix spelling errors"),
            "Continuation must not re-apply the dictation prompt"
        )
        XCTAssertFalse(
            systemContent.contains("Return only the corrected text"),
            "Continuation must not re-apply the dictation prompt"
        )
        XCTAssertTrue(
            systemContent.localizedCaseInsensitiveContains("helpful assistant"),
            "Continuation system message should be a generic chat-mode hint"
        )
        XCTAssertTrue(
            systemContent.contains(SupportedLanguage.ru.displayName),
            "Continuation system message must still pin the response language"
        )
    }

    func testInjection_localizedByVoiceLanguage_english() {
        let session = makeSession(voice: .en)
        session.addMessage(ChatMessage(role: .transcription, content: "anything"))

        let payload = session.prepareMessagesForLLM(
            maxTokenBudget: 1000,
            systemPromptTokens: 10,
            isFirstVoiceTurn: true,
            answerQuestionsInFirstMessage: false
        )
        XCTAssertTrue(payload.first!.content.contains("Do not answer"))
    }

    // MARK: - Invariants on payload structure

    func testInvariant_systemAlwaysFirst() {
        let session = makeSession()
        session.addMessage(ChatMessage(role: .user, content: "u1"))
        session.addMessage(ChatMessage(role: .assistant, content: "a1"))
        session.addMessage(ChatMessage(role: .user, content: "u2"))

        let payload = session.prepareMessagesForLLM(
            maxTokenBudget: 10_000,
            systemPromptTokens: 5,
            isFirstVoiceTurn: false,
            answerQuestionsInFirstMessage: false
        )
        XCTAssertEqual(payload.first?.role, "system")
    }

    func testInvariant_lastMessageIsUser() {
        let session = makeSession()
        session.addMessage(ChatMessage(role: .user, content: "u1"))
        session.addMessage(ChatMessage(role: .assistant, content: "a1"))
        session.addMessage(ChatMessage(role: .user, content: "u2"))

        let payload = session.prepareMessagesForLLM(
            maxTokenBudget: 10_000,
            systemPromptTokens: 5,
            isFirstVoiceTurn: false,
            answerQuestionsInFirstMessage: false
        )
        XCTAssertEqual(payload.last?.role, "user")
        XCTAssertEqual(payload.last?.content, "u2")
    }

    /// FR-005: full history is included when within budget.
    func testFullHistory_whenWithinBudget() {
        let session = makeSession()
        let texts = ["u1", "a1", "u2", "a2", "u3"]
        let roles: [ChatMessageRole] = [.user, .assistant, .user, .assistant, .user]
        for (text, role) in zip(texts, roles) {
            session.addMessage(ChatMessage(role: role, content: text))
        }

        let payload = session.prepareMessagesForLLM(
            maxTokenBudget: 100_000,
            systemPromptTokens: 5,
            isFirstVoiceTurn: false,
            answerQuestionsInFirstMessage: false
        )
        // 1 system + 5 history
        XCTAssertEqual(payload.count, 6)
        XCTAssertEqual(payload.dropFirst().map { $0.content }, texts)
    }

    // MARK: - Edited content

    /// FR-006: `prepareMessagesForLLM` reads current `message.content`, not a cached snapshot.
    func testEditedContent_isReflectedInPayload() {
        let session = makeSession()
        let user1 = ChatMessage(role: .user, content: "remember 42")
        session.addMessage(user1)
        session.addMessage(ChatMessage(role: .assistant, content: "ok"))
        session.addMessage(ChatMessage(role: .user, content: "what was it?"))

        // Simulate onConfirmEdit on user1.
        user1.content = "remember 99"

        let payload = session.prepareMessagesForLLM(
            maxTokenBudget: 100_000,
            systemPromptTokens: 5,
            isFirstVoiceTurn: false,
            answerQuestionsInFirstMessage: false
        )
        // First user message in payload is at index 1 (after system).
        XCTAssertEqual(payload[1].content, "remember 99", "Edited content must be sent in the payload (FR-006/SC-007)")
    }

    // MARK: - Pair truncation (T013)

    /// SC-008: budget pressure drops oldest user/assistant pairs while preserving
    /// system + the newest user. No middle / tail messages are removed.
    func testPairTruncation_keepsTailAndSystem() {
        let session = makeSession()
        // Build 3 user/assistant pairs + a new user message (very small content for predictable tokens).
        let pairs: [(ChatMessageRole, String)] = [
            (.user, "u1"), (.assistant, "a1"),
            (.user, "u2"), (.assistant, "a2"),
            (.user, "u3"), (.assistant, "a3"),
            (.user, "u4-new")
        ]
        for (role, content) in pairs {
            session.addMessage(ChatMessage(role: role, content: content))
        }
        // Budget that fits the new user + one pair (~3 tokens each, ~12 budget).
        let payload = session.prepareMessagesForLLM(
            maxTokenBudget: 15,
            systemPromptTokens: 0,
            isFirstVoiceTurn: false,
            answerQuestionsInFirstMessage: false
        )
        // System + at most a few tail items.
        XCTAssertEqual(payload.first?.role, "system")
        XCTAssertEqual(payload.last?.content, "u4-new")
        // No element from the prefix u1/a1 must remain.
        XCTAssertFalse(payload.contains(where: { $0.content == "u1" }))
        XCTAssertFalse(payload.contains(where: { $0.content == "a1" }))
        // No orphan assistant at the head of the historical selection.
        if payload.count > 2 {
            XCTAssertEqual(payload[1].role, "user", "After system, history must begin with a user message")
        }
    }

    /// Edge case: even when only the new user message fits, the result is `[system, u-new]`.
    func testPairTruncation_extremelyTightBudget_keepsOnlySystemAndNewUser() {
        let session = makeSession()
        session.addMessage(ChatMessage(role: .user, content: "u1"))
        session.addMessage(ChatMessage(role: .assistant, content: "a1"))
        session.addMessage(ChatMessage(role: .user, content: "u2-new"))

        let payload = session.prepareMessagesForLLM(
            maxTokenBudget: 3,             // ~1 message
            systemPromptTokens: 0,
            isFirstVoiceTurn: false,
            answerQuestionsInFirstMessage: false
        )
        XCTAssertEqual(payload.first?.role, "system")
        XCTAssertEqual(payload.last?.content, "u2-new")
        XCTAssertFalse(payload.contains(where: { $0.content == "u1" }))
        XCTAssertFalse(payload.contains(where: { $0.content == "a1" }))
    }

    /// INV-5: an orphan assistant at the head of the selected window must be dropped.
    func testPairTruncation_dropsOrphanedAssistantAtHead() {
        let session = makeSession()
        // Force a scenario where after token-bounded selection from the tail, the
        // earliest element in `selected` is `assistant`. Use 2-token messages and a
        // budget that selects (u2-new, a1) — orphan a1 must be removed.
        //
        // History: u1, a1, u2-new   (3 messages)
        // Budget: enough for u2-new + a1 but NOT for u1 → window = [a1, u2-new]
        // After orphan trim: window = [u2-new]
        session.addMessage(ChatMessage(role: .user, content: "u1xxxxxxxx"))      // big
        session.addMessage(ChatMessage(role: .assistant, content: "a1"))         // small
        session.addMessage(ChatMessage(role: .user, content: "u2-new"))          // small

        let payload = session.prepareMessagesForLLM(
            maxTokenBudget: 5,
            systemPromptTokens: 0,
            isFirstVoiceTurn: false,
            answerQuestionsInFirstMessage: false
        )
        // System + (no orphan assistant) + u2-new
        XCTAssertEqual(payload.first?.role, "system")
        XCTAssertFalse(payload.contains(where: { $0.content == "a1" }), "Orphan assistant at the head must be removed")
        XCTAssertEqual(payload.last?.content, "u2-new")
    }
}
