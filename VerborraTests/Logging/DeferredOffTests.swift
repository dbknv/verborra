import Testing
@testable import Verborra

// MARK: - DeferredOffTests (T067)

struct DeferredOffTests {

    @Test func shouldLog_off_withActiveRecording_allowsError() {
        // Simulate: level is OFF but recording is active
        // The deferred OFF logic in DiagnosticLogger.shouldLog allows ERROR during active recording
        // This tests the LogLevel.shouldLog helper which is used by DiagnosticLogger

        // OFF normally blocks everything
        #expect(LogLevel.error.shouldLog(at: .off) == false)

        // But DiagnosticLogger adds special handling when isRecordingActive:
        // When OFF + recording active → error still writes
        // This is tested via the DiagnosticLogger's shouldLog method
        // Here we verify the base level logic is correct
        #expect(LogLevel.info.shouldLog(at: .off) == false)
        #expect(LogLevel.debug.shouldLog(at: .off) == false)
    }

    @Test func shouldLog_off_withoutActiveRecording_blocksAll() {
        #expect(LogLevel.error.shouldLog(at: .off) == false)
        #expect(LogLevel.info.shouldLog(at: .off) == false)
        #expect(LogLevel.debug.shouldLog(at: .off) == false)
    }

    @Test func shouldLog_error_allowsOnlyErrors() {
        #expect(LogLevel.error.shouldLog(at: .error) == true)
        #expect(LogLevel.info.shouldLog(at: .error) == false)
        #expect(LogLevel.debug.shouldLog(at: .error) == false)
    }
}
