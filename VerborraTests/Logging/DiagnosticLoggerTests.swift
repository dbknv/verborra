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
        let logger = DiagnosticLogger.logger(for: .audio)
        // Проверяем, что создаётся без crash
        #expect(logger != nil)
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
