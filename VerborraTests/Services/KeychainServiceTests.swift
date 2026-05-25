import XCTest
@testable import Verborra

// MARK: - MockKeychainService (T038)

final class MockKeychainService: KeychainServiceProtocol {
    var storage: [String: String] = [:]
    var saveCallCount = 0
    var retrieveCallCount = 0
    var deleteCallCount = 0
    var shouldThrowOnSave = false

    func save(_ value: String, forKey key: String) throws {
        saveCallCount += 1
        if shouldThrowOnSave {
            throw KeychainError.saveFailed(-1)
        }
        storage[key] = value
    }

    func retrieve(forKey key: String) throws -> String? {
        retrieveCallCount += 1
        return storage[key]
    }

    func delete(forKey key: String) throws {
        deleteCallCount += 1
        storage.removeValue(forKey: key)
    }
}

final class KeychainServiceTests: XCTestCase {
    var mockKeychain: MockKeychainService!

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainService()
    }

    func testSaveAndRetrieve() throws {
        try mockKeychain.save("test-key-123", forKey: "openai-api-key")
        let retrieved = try mockKeychain.retrieve(forKey: "openai-api-key")
        XCTAssertEqual(retrieved, "test-key-123")
        XCTAssertEqual(mockKeychain.saveCallCount, 1)
        XCTAssertEqual(mockKeychain.retrieveCallCount, 1)
    }

    func testRetrieveNonExistent() throws {
        let result = try mockKeychain.retrieve(forKey: "nonexistent")
        XCTAssertNil(result)
    }

    func testDelete() throws {
        try mockKeychain.save("value", forKey: "key")
        try mockKeychain.delete(forKey: "key")
        let result = try mockKeychain.retrieve(forKey: "key")
        XCTAssertNil(result)
        XCTAssertEqual(mockKeychain.deleteCallCount, 1)
    }

    func testOverwrite() throws {
        try mockKeychain.save("old", forKey: "key")
        try mockKeychain.save("new", forKey: "key")
        let result = try mockKeychain.retrieve(forKey: "key")
        XCTAssertEqual(result, "new")
    }
}

// MARK: - V019: Real KeychainService Tests

final class RealKeychainServiceTests: XCTestCase {
    var keychainService: KeychainService!
    let testService = "com.apeek.Verborra.tests"
    let testKeyPrefix = "test-keychain-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        keychainService = KeychainService(service: testService)
    }

    override func tearDown() {
        // Clean up test keys
        try? keychainService.delete(forKey: testKeyPrefix)
        try? keychainService.delete(forKey: "\(testKeyPrefix)-delete")
        try? keychainService.delete(forKey: "\(testKeyPrefix)-overwrite")
        super.tearDown()
    }

    func testRealKeychainSaveAndRetrieve() throws {
        let testValue = "test-api-key-\(UUID().uuidString)"
        try keychainService.save(testValue, forKey: testKeyPrefix)
        let retrieved = try keychainService.retrieve(forKey: testKeyPrefix)
        XCTAssertEqual(retrieved, testValue)
    }

    func testRealKeychainDelete() throws {
        let key = "\(testKeyPrefix)-delete"
        try keychainService.save("to-be-deleted", forKey: key)

        // Verify it exists
        let before = try keychainService.retrieve(forKey: key)
        XCTAssertNotNil(before)

        // Delete and verify nil
        try keychainService.delete(forKey: key)
        let after = try keychainService.retrieve(forKey: key)
        XCTAssertNil(after)
    }

    func testRealKeychainOverwrite() throws {
        let key = "\(testKeyPrefix)-overwrite"
        try keychainService.save("first-value", forKey: key)
        try keychainService.save("second-value", forKey: key)

        let retrieved = try keychainService.retrieve(forKey: key)
        XCTAssertEqual(retrieved, "second-value")
    }
}
