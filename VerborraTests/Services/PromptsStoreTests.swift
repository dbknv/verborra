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
        // Persist a prompts file without any system prompt, then reload it
        let userOnly = store.prompts.filter { !$0.isSystem }
        try? JSONEncoder().encode(userOnly).write(to: fileURL, options: .atomic)
        store = PromptsStore(fileURL: fileURL)

        store.ensureSystemPrompts()
        let systemPrompt = store.prompts.first(where: { $0.systemId == "simple-voice-to-text" })
        XCTAssertNotNil(systemPrompt)
        XCTAssertTrue(systemPrompt!.isSystem)
    }

    // MARK: - T018 (013): migration v2 → v3 — force-rewrite simple-voice-to-text content
    //
    // Verifies FR-009a: a previously customized built-in prompt content is replaced
    // by the simplified formulation, `answerQuestionsInFirstMessage` is reset to
    // `false`, and the persisted dataVersion is bumped to 3.

    func testMigration_v2ToV3_forceRewritesSimpleVoiceToText() throws {
        // Use a dedicated file to keep UserDefaults manipulation scoped.
        let dedicatedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-v3-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: dedicatedURL) }

        // 1. Prepare a v2 JSON file with a customised simple-voice-to-text content.
        let customisedV2Prompt: [String: Any] = [
            "id": "55555555-5555-5555-5555-555555555555",
            "name": "User-renamed prompt",
            "content": "TOTALLY CUSTOM USER CONTENT THAT MUST BE OVERWRITTEN",
            "isDefault": true,
            "isSystem": true,
            "systemId": "simple-voice-to-text"
            // No `answerQuestionsInFirstMessage` field → decodes as false.
        ]
        let payload = [customisedV2Prompt]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: dedicatedURL, options: .atomic)

        // 2. Pin dataVersion to 2 so migrateIfNeeded enters the v2→v3 branch.
        // The test host is the app itself — restore the real value afterwards.
        let savedVersion = UserDefaults.standard.object(forKey: "promptsDataVersion")
        UserDefaults.standard.set(2, forKey: "promptsDataVersion")
        defer { UserDefaults.standard.set(savedVersion, forKey: "promptsDataVersion") }

        // 3. Booting the store triggers migration.
        let migrated = PromptsStore(fileURL: dedicatedURL)

        // 4. The simple-voice-to-text content must now equal the new simplified definition.
        let svtt = migrated.prompts.first(where: {
            $0.isSystem && $0.systemId == "simple-voice-to-text"
        })
        XCTAssertNotNil(svtt, "Built-in simple-voice-to-text must be present after migration")

        let expectedContent = SystemPromptDefinition.simpleVoiceToText
            .content(for: LocalizationManager.shared.currentLanguage)
        XCTAssertEqual(svtt?.content, expectedContent, "FR-009a: customised content must be force-rewritten on migration")
        XCTAssertNotEqual(svtt?.content, "TOTALLY CUSTOM USER CONTENT THAT MUST BE OVERWRITTEN")

        // FR-012: `answerQuestionsInFirstMessage` must be reset to false on migration.
        XCTAssertFalse(svtt?.answerQuestionsInFirstMessage ?? true)

        // FR-009b: the migrated built-in must report read-only.
        XCTAssertTrue(svtt?.isReadOnly ?? false)

        // 5. dataVersion key is bumped to current (4 since the v3 → v4 registry re-sync).
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "promptsDataVersion"), 4)
    }

    /// FR-009b: post-migration, the read-only prompt resists `updatePrompt` / `deletePrompt`.
    func testMigration_v3_readOnlyPromptCannotBeMutated() {
        // Take the default-created simple-voice-to-text from `store`.
        guard let svttIndex = store.prompts.firstIndex(where: { $0.isReadOnly }) else {
            XCTFail("Expected a read-only simple-voice-to-text prompt in fresh store")
            return
        }
        var attempt = store.prompts[svttIndex]
        let originalContent = attempt.content
        attempt.content = "user attempts to rewrite this"
        attempt.answerQuestionsInFirstMessage = true

        store.updatePrompt(attempt)

        let after = store.prompts[svttIndex]
        XCTAssertEqual(after.content, originalContent, "Read-only prompt content must be guarded by store")
        XCTAssertFalse(after.answerQuestionsInFirstMessage)

        // Deletion is also blocked.
        let countBefore = store.prompts.count
        store.deletePrompt(after.id)
        XCTAssertEqual(store.prompts.count, countBefore, "Read-only prompt must not be deletable")
    }
}
