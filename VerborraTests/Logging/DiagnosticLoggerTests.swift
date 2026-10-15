import Foundation
import os
import Testing
@testable import Verborra

// MARK: - DiagnosticLoggerTests (T022)

struct DiagnosticLoggerTests {

    @Test func sessionId_isStable() {
        let id1 = DiagnosticLogger.sessionId
        let id2 = DiagnosticLogger.sessionId
        #expect(id1 == id2)
    }

    @Test func sessionId_isValidUUID() {
        let id = DiagnosticLogger.sessionId
        #expect(UUID(uuidString: id) != nil)
    }

    @Test func loggerFactory_createsLoggerForCategory() {
        // Проверяем, что создаётся без crash
        _ = DiagnosticLogger.logger(for: .audio)
    }

    @Test func logLevel_shouldLog_hierarchy() {
        // OFF → ничего
        #expect(LogLevel.error.shouldLog(at: .off) == false)
        #expect(LogLevel.info.shouldLog(at: .off) == false)
        #expect(LogLevel.debug.shouldLog(at: .off) == false)

        // ERROR → только error
        #expect(LogLevel.error.shouldLog(at: .error) == true)
        #expect(LogLevel.info.shouldLog(at: .error) == false)
        #expect(LogLevel.debug.shouldLog(at: .error) == false)

        // INFO → error + info
        #expect(LogLevel.error.shouldLog(at: .info) == true)
        #expect(LogLevel.info.shouldLog(at: .info) == true)
        #expect(LogLevel.debug.shouldLog(at: .info) == false)

        // DEBUG → всё
        #expect(LogLevel.error.shouldLog(at: .debug) == true)
        #expect(LogLevel.info.shouldLog(at: .debug) == true)
        #expect(LogLevel.debug.shouldLog(at: .debug) == true)
    }
}

// MARK: - WARN + thread-safe filtering (spec 015, T007)

/// Shared global state (filter snapshot, providers, test sink) — run serially.
@Suite(.serialized)
struct DiagnosticLoggerWarnTests {

    /// Collects entries whose message carries this test's marker.
    private final class Capture: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: [LogEntry]())
        let marker = UUID().uuidString
        func append(_ entry: LogEntry) {
            guard entry.message.contains(marker) else { return }
            lock.withLock { $0.append(entry) }
        }
        var entries: [LogEntry] { lock.withLock { $0 } }
    }

    private final class CallCounter: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: 0)
        func hit() { lock.withLock { $0 += 1 } }
        var count: Int { lock.withLock { $0 } }
    }

    private final class SpyStateProvider: AppStateProvider, @unchecked Sendable {
        let counter = CallCounter()
        func currentAppState() -> AppState {
            counter.hit()
            return AppState(activeDevice: nil, recordingStatus: "idle", recordingDuration: nil, currentOperation: nil)
        }
    }

    /// Runs `body` with a snapshot, a capture sink and spy providers, then restores globals.
    private func withLogger(
        level: LogLevel,
        recording: Bool = false,
        _ body: (Capture, CallCounter, SpyStateProvider) -> Void
    ) {
        let savedSnapshot = DiagnosticLogger.filterSnapshot.withLock { $0 }
        let savedLevelProvider = DiagnosticLogger.logLevelProvider
        let savedRecordingProvider = DiagnosticLogger.isRecordingActiveProvider
        let savedStateProvider = DiagnosticLogger.appStateProvider
        defer {
            DiagnosticLogger.filterSnapshot.withLock { $0 = savedSnapshot }
            DiagnosticLogger.logLevelProvider = savedLevelProvider
            DiagnosticLogger.isRecordingActiveProvider = savedRecordingProvider
            DiagnosticLogger.appStateProvider = savedStateProvider
            DiagnosticLogger.testEntrySink.withLock { $0 = nil }
        }

        let capture = Capture()
        let providerCalls = CallCounter()
        let stateProvider = SpyStateProvider()
        DiagnosticLogger.filterSnapshot.withLock { $0 = LogFilterSnapshot(level: level, isRecordingActive: recording) }
        DiagnosticLogger.logLevelProvider = { providerCalls.hit(); return .debug }
        DiagnosticLogger.isRecordingActiveProvider = { providerCalls.hit(); return false }
        DiagnosticLogger.appStateProvider = stateProvider
        DiagnosticLogger.testEntrySink.withLock { $0 = { capture.append($0) } }

        withExtendedLifetime(stateProvider) {
            body(capture, providerCalls, stateProvider)
        }
    }

    @Test(arguments: [LogLevel.error, .info, .debug])
    func warn_isWritten_whenLoggingIsOn(level: LogLevel) {
        withLogger(level: level) { capture, _, _ in
            DiagnosticLogger.logger(for: .watchdog).warn("warn \(capture.marker)", metadata: ["k": "v"])
            #expect(capture.entries.count == 1)
            #expect(capture.entries.first?.level == "WARN")
            #expect(capture.entries.first?.metadata == ["k": "v"])
            #expect(capture.entries.first?.category == "watchdog")
        }
    }

    @Test func warn_isNotWritten_whenOff() {
        withLogger(level: .off) { capture, _, _ in
            DiagnosticLogger.logger(for: .watchdog).warn("warn \(capture.marker)")
            #expect(capture.entries.isEmpty)
        }
    }

    @Test func warn_encodesWarnLevelInJSONL() throws {
        let entry = LogEntry(severityLabel: "WARN", category: .hotkey, sessionId: "s", message: "m")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any]
        #expect(json?["level"] as? String == "WARN")
    }

    @Test func warn_neverCallsAppStateProvider() {
        withLogger(level: .debug) { capture, _, stateProvider in
            DiagnosticLogger.logger(for: .watchdog).warn("warn \(capture.marker)")
            #expect(capture.entries.count == 1)
            #expect(stateProvider.counter.count == 0)
        }
    }

    @Test func warnAndError_fromBackgroundQueue_useOnlyTheSnapshot() {
        withLogger(level: .error) { capture, providerCalls, stateProvider in
            let logger = DiagnosticLogger.logger(for: .watchdog)
            let group = DispatchGroup()
            DispatchQueue.global().async(group: group) {
                logger.warn("warn \(capture.marker)")
                logger.error("error \(capture.marker)")
                logger.info("info \(capture.marker)")
            }
            group.wait()
            // Snapshot level ERROR: WARN and ERROR are written, INFO is filtered out.
            #expect(capture.entries.map(\.level).sorted() == ["ERROR", "WARN"])
            #expect(providerCalls.count == 0)
            #expect(stateProvider.counter.count == 0)
            let errorEntry = capture.entries.first { $0.level == "ERROR" }
            #expect(errorEntry?.error?.state == nil)
        }
    }

    @Test func deferredOff_writesOnlyErrorWhileRecording() {
        withLogger(level: .off, recording: true) { capture, _, _ in
            let logger = DiagnosticLogger.logger(for: .audio)
            logger.debug("debug \(capture.marker)")
            logger.info("info \(capture.marker)")
            logger.error("error \(capture.marker)")
            #expect(capture.entries.map(\.level) == ["ERROR"])
        }
    }
}
