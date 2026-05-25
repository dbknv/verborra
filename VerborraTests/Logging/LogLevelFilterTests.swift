import Testing
@testable import Verborra

// MARK: - LogLevelFilterTests (T054)

struct LogLevelFilterTests {

    @Test func logLevel_info_isDefault() {
        // Verify default LogLevel is .info (rawValue 2)
        #expect(LogLevel.info.rawValue == 2)
    }

    @Test func logLevel_comparable_ordering() {
        #expect(LogLevel.off < LogLevel.error)
        #expect(LogLevel.error < LogLevel.info)
        #expect(LogLevel.info < LogLevel.debug)
    }

    @Test func shouldLog_respectsHierarchy() {
        // ERROR at INFO level → should log
        #expect(LogLevel.error.shouldLog(at: .info) == true)
        // DEBUG at INFO level → should not log
        #expect(LogLevel.debug.shouldLog(at: .info) == false)
        // INFO at INFO level → should log
        #expect(LogLevel.info.shouldLog(at: .info) == true)
    }

    @Test func shouldLog_off_blocksEverything() {
        #expect(LogLevel.error.shouldLog(at: .off) == false)
        #expect(LogLevel.info.shouldLog(at: .off) == false)
        #expect(LogLevel.debug.shouldLog(at: .off) == false)
    }

    @Test func shouldLog_debug_allowsAll() {
        #expect(LogLevel.error.shouldLog(at: .debug) == true)
        #expect(LogLevel.info.shouldLog(at: .debug) == true)
        #expect(LogLevel.debug.shouldLog(at: .debug) == true)
    }

    @Test func logLevel_displayName_correct() {
        #expect(LogLevel.off.displayName == "OFF")
        #expect(LogLevel.error.displayName == "ERROR")
        #expect(LogLevel.info.displayName == "INFO")
        #expect(LogLevel.debug.displayName == "DEBUG")
    }
}
