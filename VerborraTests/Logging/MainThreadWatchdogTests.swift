import Testing
@testable import Verborra

// MARK: - MainThreadWatchdogTests (spec 015, T048)

struct MainThreadWatchdogTests {

    @Test func noWarningWhilePongsArrive() {
        var detector = StallDetector(threshold: 2.0)
        var now = 0.0
        for _ in 0..<20 {
            now += 0.5
            #expect(detector.evaluate(now: now, lastPong: now - 0.5) == .none)
        }
    }

    @Test func oneWarningPerStallThenRecovery() {
        var detector = StallDetector(threshold: 2.0)
        let lastPong = 10.0
        #expect(detector.evaluate(now: 11.5, lastPong: lastPong) == .none)
        #expect(detector.evaluate(now: 12.0, lastPong: lastPong) == .warn(stallMs: 2000))
        #expect(detector.evaluate(now: 12.5, lastPong: lastPong) == .none)
        #expect(detector.evaluate(now: 13.0, lastPong: lastPong) == .none)
        // Main thread answers again at 13.2
        #expect(detector.evaluate(now: 13.5, lastPong: 13.2) == .recovered(stallMs: 3200))
        #expect(detector.evaluate(now: 14.0, lastPong: 13.7) == .none)
    }

    @Test func newStallAfterRecoveryWarnsAgain() {
        var detector = StallDetector(threshold: 2.0)
        _ = detector.evaluate(now: 2.0, lastPong: 0.0)
        _ = detector.evaluate(now: 3.0, lastPong: 2.9)
        #expect(detector.evaluate(now: 6.0, lastPong: 3.5) == .warn(stallMs: 2500))
    }

    @Test func hangContextTracksStageAndDevice() {
        MainThreadWatchdog.setStage("starting.1")
        MainThreadWatchdog.setDevice(name: "USB Mic", id: "200")
        let context = MainThreadWatchdog.hangContext.withLock { $0 }
        #expect(context.stage == "starting.1")
        #expect(context.deviceName == "USB Mic")
        #expect(context.deviceID == "200")
        MainThreadWatchdog.setStage("idle")
    }

    @Test func watchdogStageNames() {
        #expect(RecordingViewModel.watchdogStage(for: .starting(attempt: 2)) == "starting.2")
        #expect(RecordingViewModel.watchdogStage(for: .recording(duration: 0, remaining: 1)) == "recording")
        #expect(RecordingViewModel.watchdogStage(for: .error(.deviceUnavailable)) == "error")
    }
}
