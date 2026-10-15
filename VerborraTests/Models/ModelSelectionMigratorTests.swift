import XCTest
@testable import Verborra

// MARK: - ModelSelectionMigratorTests (spec 015, T029)

final class ModelSelectionMigratorTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    private let sttKey = ModelSelectionMigrator.sttKey
    private let llmKey = ModelSelectionMigrator.llmKey

    override func setUp() {
        super.setUp()
        suiteName = "ModelSelectionMigratorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func run() -> [ModelSelectionMigrator.Migration] {
        ModelSelectionMigrator.run(defaults: defaults, log: nil)
    }

    func testCurrentValuesAreUnchanged() {
        defaults.set("gpt-5.4", forKey: llmKey)
        defaults.set("gpt-transcribe", forKey: sttKey)
        defaults.set(true, forKey: ModelSelectionMigrator.onboardingCompletedKey)

        XCTAssertEqual(run(), [])
        XCTAssertEqual(defaults.string(forKey: llmKey), "gpt-5.4")
        XCTAssertEqual(defaults.string(forKey: sttKey), "gpt-transcribe")
    }

    func testRemovedTextModelsMoveToNewDefault() {
        for old in ["gpt-5.1", "gpt-5-mini", "gpt-5.5-pro"] {
            defaults.set(old, forKey: llmKey)
            defaults.set("gpt-transcribe", forKey: sttKey)

            XCTAssertEqual(run(), [.init(kind: .llm, old: old, new: "gpt-6-luna", reason: .removed)], old)
            XCTAssertEqual(defaults.string(forKey: llmKey), "gpt-6-luna")
        }
    }

    func testRemovedSpeechModelMovesToGPTTranscribe() {
        defaults.set("whisper-1", forKey: sttKey)
        defaults.set("gpt-5.2", forKey: llmKey)

        XCTAssertEqual(run(), [.init(kind: .stt, old: "whisper-1", new: "gpt-transcribe", reason: .removed)])
        XCTAssertEqual(defaults.string(forKey: sttKey), "gpt-transcribe")
        XCTAssertEqual(defaults.string(forKey: llmKey), "gpt-5.2")
    }

    func testUnknownValueIsTreatedAsRemoved() {
        defaults.set("foo", forKey: llmKey)
        defaults.set("foo", forKey: sttKey)

        XCTAssertEqual(run(), [
            .init(kind: .stt, old: "foo", new: "gpt-transcribe", reason: .removed),
            .init(kind: .llm, old: "foo", new: "gpt-6-luna", reason: .removed)
        ])
    }

    func testExistingUserWithoutSavedModelsInheritedOldDefaults() {
        defaults.set(true, forKey: ModelSelectionMigrator.onboardingCompletedKey)

        XCTAssertEqual(run(), [
            .init(kind: .stt, old: "gpt-4o-mini-transcribe", new: "gpt-transcribe", reason: .inheritedDefault),
            .init(kind: .llm, old: "gpt-5.1", new: "gpt-6-luna", reason: .inheritedDefault)
        ])
        XCTAssertEqual(defaults.string(forKey: sttKey), "gpt-transcribe")
        XCTAssertEqual(defaults.string(forKey: llmKey), "gpt-6-luna")
    }

    func testFreshInstallWritesNothing() {
        XCTAssertEqual(run(), [])
        XCTAssertNil(defaults.object(forKey: sttKey))
        XCTAssertNil(defaults.object(forKey: llmKey))
    }

    func testSecondRunIsNoOp() {
        defaults.set("gpt-5-nano", forKey: llmKey)
        defaults.set(true, forKey: ModelSelectionMigrator.onboardingCompletedKey)
        XCTAssertEqual(run().count, 2)

        let sttAfterFirst = defaults.string(forKey: sttKey)
        let llmAfterFirst = defaults.string(forKey: llmKey)
        XCTAssertEqual(run(), [])
        XCTAssertEqual(defaults.string(forKey: sttKey), sttAfterFirst)
        XCTAssertEqual(defaults.string(forKey: llmKey), llmAfterFirst)
    }
}
