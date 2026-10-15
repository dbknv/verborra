import Atomics
import Foundation
import os

// MARK: - HangContext (spec 015, T057)

/// What the app was doing, for the stall report. Written from the main thread, read from the watchdog queue.
struct HangContext: Sendable {
    var stage: String
    var deviceName: String?
    var deviceID: String?
    var stageEnteredAt: Date
}

// MARK: - StallDetector

/// Pure stall logic: one WARN per stall longer than `threshold`, one "recovered" when the main thread answers again.
struct StallDetector {
    enum Event: Equatable {
        case none
        case warn(stallMs: Int)
        case recovered(stallMs: Int)
    }

    let threshold: TimeInterval
    private var stallStart: TimeInterval?
    private var warned = false

    init(threshold: TimeInterval = 2.0) {
        self.threshold = threshold
    }

    /// `now` and `lastPong` are seconds on the same monotonic clock.
    mutating func evaluate(now: TimeInterval, lastPong: TimeInterval) -> Event {
        let silence = now - lastPong
        if silence >= threshold {
            if !warned {
                warned = true
                stallStart = lastPong
                return .warn(stallMs: Int((silence * 1000).rounded()))
            }
            return .none
        }
        if warned, let start = stallStart {
            warned = false
            stallStart = nil
            return .recovered(stallMs: Int(((lastPong - start) * 1000).rounded()))
        }
        return .none
    }
}

// MARK: - MainThreadWatchdog

/// Detects main-thread stalls (FR-011). Runs on its own queue and never calls `@MainActor` APIs
/// or the logger's main-thread providers — only the thread-safe `DiagnosticLogger.filterSnapshot`.
final class MainThreadWatchdog: @unchecked Sendable {
    static let hangContext = OSAllocatedUnfairLock(
        initialState: HangContext(stage: "idle", deviceName: nil, deviceID: nil, stageEnteredAt: Date())
    )

    static func setStage(_ stage: String) {
        hangContext.withLock {
            guard $0.stage != stage else { return }
            $0.stage = stage
            $0.stageEnteredAt = Date()
        }
    }

    static func setDevice(name: String?, id: String?) {
        hangContext.withLock {
            $0.deviceName = name
            $0.deviceID = id
        }
    }

    private let queue = DispatchQueue(label: "dev.apeek.verborra.watchdog", qos: .utility)
    private let interval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var detector: StallDetector
    private let lastPong = ManagedAtomic<UInt64>(DispatchTime.now().uptimeNanoseconds)
    private let log = DiagnosticLogger.logger(for: .watchdog)

    init(interval: TimeInterval = 0.5, threshold: TimeInterval = 2.0) {
        self.interval = interval
        self.detector = StallDetector(threshold: threshold)
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            self.lastPong.store(DispatchTime.now().uptimeNanoseconds, ordering: .relaxed)
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + self.interval, repeating: self.interval)
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
        }
    }

    // MARK: - Private (watchdog queue)

    private func tick() {
        let isOff = DiagnosticLogger.filterSnapshot.withLock { $0.level == .off && !$0.isRecordingActive }
        let pong = lastPong
        DispatchQueue.main.async {
            pong.store(DispatchTime.now().uptimeNanoseconds, ordering: .relaxed)
        }
        guard !isOff else { return }

        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        let last = Double(lastPong.load(ordering: .relaxed)) / 1e9
        switch detector.evaluate(now: now, lastPong: last) {
        case .none:
            break
        case .warn(let stallMs):
            let context = Self.hangContext.withLock { $0 }
            log.warn("Main thread unresponsive", metadata: [
                "stage": context.stage,
                "stageAgeMs": "\(Int(Date().timeIntervalSince(context.stageEnteredAt) * 1000))",
                "deviceName": context.deviceName ?? "",
                "deviceID": context.deviceID ?? "",
                "stallMs": "\(stallMs)"
            ])
        case .recovered(let stallMs):
            let stage = Self.hangContext.withLock { $0.stage }
            log.info("Main thread recovered", metadata: [
                "stage": stage,
                "stallMs": "\(stallMs)"
            ])
        }
    }
}
