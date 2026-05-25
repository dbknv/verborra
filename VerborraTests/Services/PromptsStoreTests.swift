import XCTest
@testable import Verborra

final class PromptsStoreTests: XCTestCase {
    var store: PromptsStore!
    var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-prompts-\(UUID().uuidString).json")
        store = PromptsStore(fileURL: fileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    func testDefaultPromptCreated() {
        XCTAssertFalse(store.prompts.isEmpty)
        XCTAssertTrue(store.prompts[0].isDefault)
        // T040: Default prompt is now a system prompt
        XCTAssertTrue(store.prompts[0].isSystem)
        XCTAssertEqual(store.prompts[0].systemId, "simple-voice-to-text")
    }

    func testDefaultPromptProperty() {
        let defaultPrompt = store.defaultPrompt
        XCTAssertTrue(defaultPrompt.isDefault)
    }

    func testAddPrompt() {
        let prompt = SystemPrompt(name: "Test", content: "content")
        store.addPrompt(prompt)
        XCTAssertEqual(store.prompts.count, 2)
        XCTAssertEqual(store.prompts.last?.name, "Test")
    }

    func testUpdatePrompt() {
        // Add a user prompt (not system) to test update
        let prompt = SystemPrompt(name: "User Prompt", content: "content")
        store.addPrompt(prompt)
        var toUpdate = store.prompts.first(where: { $0.id == prompt.id })!
        toUpdate.name = "Updated"
        store.updatePrompt(toUpdate)
        XCTAssertEqual(store.prompts.first(where: { $0.id == prompt.id })?.name, "Updated")
    }

    func testDeletePrompt() {
        let prompt = SystemPrompt(name: "ToDelete", content: "content")
        store.addPrompt(prompt)
        XCTAssertEqual(store.prompts.count, 2)

        store.deletePrompt(prompt.id)
        XCTAssertEqual(store.prompts.count, 1)
    }

    func testCannotDeleteLastPrompt() {
        // Add a user prompt, delete it, system prompt remains
        let prompt = SystemPrompt(name: "Extra", content: "content")
        store.addPrompt(prompt)
        store.deletePrompt(prompt.id)
        XCTAssertEqual(store.prompts.count, 1)
        XCTAssertTrue(store.prompts[0].isSystem)
    }

    func testSetDefault() {
        let prompt = SystemPrompt(name: "New Default", content: "content")
        store.addPrompt(prompt)
        store.setDefault(prompt.id)

        XCTAssertFalse(store.prompts[0].isDefault)
        XCTAssertTrue(store.prompts.first(where: { $0.id == prompt.id })!.isDefault)
    }

    func testPersistence() {
        let prompt = SystemPrompt(name: "Persistent", content: "data")
        store.addPrompt(prompt)

        let store2 = PromptsStore(fileURL: fileURL)
        XCTAssertEqual(store2.prompts.count, 2)
        XCTAssertEqual(store2.prompts.last?.name, "Persistent")
    }

    // MARK: - T046: System prompt protection

    func testCannotDeleteSystemPrompt() {
        let systemPromptId = store.prompts.first(where: { $0.isSystem })!.id
        store.deletePrompt(systemPromptId)
        // System prompt should still be there
        XCTAssertNotNil(store.prompts.first(where: { $0.id == systemPromptId }))
    }

    func testCannotUpdateSystemPrompt() {
        var systemPrompt = store.prompts.first(where: { $0.isSystem })!
        let originalName = systemPrompt.name
        systemPrompt.name = "Hacked"
        store.updatePrompt(systemPrompt)
        // Name should remain unchanged
        XCTAssertEqual(store.prompts.first(where: { $0.id == systemPrompt.id })?.name, originalName)
    }

    // MARK: - T043: updateSystemPrompts

    func testUpdateSystemPrompts_changesNameAndContent() {
        let enName = SystemPromptDefinition.simpleVoiceToText.name(for: .en)
        let ruName = SystemPromptDefinition.simpleVoiceToText.name(for: .ru)

        store.updateSystemPrompts(for: .en)
        XCTAssertEqual(store.prompts.first(where: { $0.isSystem })?.name, enName)

        store.updateSystemPrompts(for: .ru)
        XCTAssertEqual(store.prompts.first(where: { $0.isSystem })?.name, ruName)
    }

    // MARK: - T044: ensureSystemPrompts

    func testEnsureSystemPrompts_addsIfMissing() {
        // Remove all system prompts manually
        store.prompts.removeAll(where: { $0.isSystem })
        store.save()

        store.ensureSystemPrompts()
        let systemPrompt = store.prompts.first(where: { $0.systemId == "simple-voice-to-text" })
        XCTAssertNotNil(systemPrompt)
        XCTAssertTrue(systemPrompt!.isSystem)
    }
}
