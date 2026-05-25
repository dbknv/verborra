import Foundation
import Testing
@testable import Verborra

// MARK: - LogFileManagerTests (T023)

struct LogFileManagerTests {

    @Test func logsDirectoryURL_isInApplicationSupport() {
        let url = LogFileManager.shared.logsDirectoryURL()
        #expect(url.path.contains("Application Support"))
        #expect(url.path.contains("Verborra/Logs"))
    }

    @Test func currentLogFileURL_hasCorrectFormat() {
        let url = LogFileManager.shared.currentLogFileURL()
        let filename = url.lastPathComponent
        #expect(filename.hasPrefix("verborra-"))
        #expect(filename.hasSuffix(".jsonl"))
        // Format: verborra-yyyy-MM-ddTHH.jsonl
        #expect(filename.contains("T"))
    }

    @Test func rotateIfNeeded_sameHour_returnsNil() {
        let current = LogFileManager.shared.currentLogFileURL()
        let result = LogFileManager.shared.rotateIfNeeded(currentFileURL: current)
        #expect(result == nil)
    }

    @Test func rotateIfNeeded_differentHour_returnsNewURL() {
        let fakeOldURL = LogFileManager.shared.logsDirectoryURL()
            .appendingPathComponent("verborra-2020-01-01T00.jsonl")
        let result = LogFileManager.shared.rotateIfNeeded(currentFileURL: fakeOldURL)
        #expect(result != nil)
        #expect(result?.lastPathComponent != fakeOldURL.lastPathComponent)
    }

    @Test func cleanupOldLogs_removesOldFiles() throws {
        let manager = LogFileManager.shared
        manager.ensureLogsDirectory()
        let dir = manager.logsDirectoryURL()

        // Create a fake old file
        let oldFile = dir.appendingPathComponent("verborra-2020-01-01T00.jsonl")
        FileManager.default.createFile(atPath: oldFile.path, contents: "test".data(using: .utf8))

        manager.cleanupOldLogs(retentionHours: 1)

        #expect(!FileManager.default.fileExists(atPath: oldFile.path))
    }
}
