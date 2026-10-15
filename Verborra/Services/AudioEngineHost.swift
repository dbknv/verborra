import Atomics
@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import os

// MARK: - AudioSetupError (spec 015, contracts/recording-start.md)

enum AudioSetupError: Error, Equatable {
    case deviceUnavailable(step: String)
    /// Node and hardware sample rates still differ after one engine re-create.
    case formatMismatch(node: Double, hardware: Double)
    case objcException(step: String, name: String, reason: String)
    case engineStartFailed(step: String, underlying: String)
    /// Raised by the facade (`AudioCaptureService`), never by the host.
    case timeout(step: String)
    case cancelled

    var errorCode: String {
        switch self {
        case .deviceUnavailable: return "deviceUnavailable"
        case .formatMismatch: return "formatMismatch"
        case .objcException(_, let name, _): return "objcException:\(name)"
        case .engineStartFailed: return "engineStartFailed"
        case .timeout: return "timeout"
        case .cancelled: return "cancelled"
        }
    }

    var step: String {
        switch self {
        case .deviceUnavailable(let step), .objcException(let step, _, _),
             .engineStartFailed(let step, _), .timeout(let step):
            return step
        case .formatMismatch: return "readFormats"
        case .cancelled: return "cancelled"
        }
    }

    var reason: String {
        switch self {
        case .deviceUnavailable: return "device unavailable"
        case .formatMismatch(let node, let hardware): return "node \(node) Hz ≠ hardware \(hardware) Hz"
        case .objcException(_, let name, let reason): return "\(name): \(reason)"
        case .engineStartFailed(_, let underlying): return underlying
        case .timeout(let step): return "timeout at \(step)"
        case .cancelled: return "cancelled"
        }
    }

    var startFailureReason: StartFailureReason {
        switch self {
        case .deviceUnavailable, .cancelled: return .deviceUnavailable
        case .formatMismatch(let node, let hardware): return .formatMismatch(node: node, hardware: hardware)
        case .objcException(_, let name, let reason): return .audioException(name: name, reason: reason)
        case .engineStartFailed(_, let underlying): return .engineStartFailed(underlying)
        case .timeout(let step): return .timeout(step: step)
        }
    }
}

// MARK: - AudioSetupTimings

/// Per-attempt step timings (event E1 in contracts/diagnostic-events.md).
struct AudioSetupTimings: Sendable {
    var engineCreateMs: Double = 0
    var setDeviceMs: Double = 0
    var readFormatsMs: Double = 0
    var installTapMs: Double = 0
    var prepareMs: Double = 0
    var startMs: Double = 0
    /// Filled by the facade; `nil` if the attempt failed before the first-buffer wait.
    var firstBufferMs: Double?
    var nodeSampleRate: Double = 0
    var hwSampleRate: Double = 0
    var channels: UInt32 = 0
    var recreatedForStaleNode = false
}

/// A failure from the host, with the timings collected up to that point.
struct AudioSetupFailure: Error {
    let error: AudioSetupError
    let timings: AudioSetupTimings
}

struct AudioHostStartResult: @unchecked Sendable {
    let timings: AudioSetupTimings
    let nodeFormat: AVAudioFormat
    let resolvedDevice: AudioDeviceID
    let deviceName: String?
}

// MARK: - AudioSetupStep

enum AudioSetupStep: Int, CaseIterable {
    case idle
    case engineCreate
    case setDevice
    case readFormats
    case installTap
    case prepare
    case start
    case btTrigger

    var name: String {
        switch self {
        case .idle: return "idle"
        case .engineCreate: return "engineCreate"
        case .setDevice: return "setDevice"
        case .readFormats: return "readFormats"
        case .installTap: return "installTap"
        case .prepare: return "prepare"
        case .start: return "start"
        case .btTrigger: return "btTrigger"
        }
    }
}

// MARK: - CoreAudioQuery

/// Nonisolated CoreAudio property reads, usable from the host queue.
enum CoreAudioQuery {
    static func nominalSampleRate(_ deviceID: AudioDeviceID) -> Double? {
        var sampleRate: Float64 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate) == noErr else {
            return nil
        }
        return sampleRate
    }

    static func name(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr,
              let cfString = name?.takeRetainedValue() else {
            return nil
        }
        return cfString as String
    }

    static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
    }
}

// MARK: - AudioEngineHosting (contracts/recording-start.md)

/// What `AudioCaptureService` needs from an engine host; lets tests replace the real host.
protocol AudioEngineHosting: AnyObject, Sendable {
    /// The step running right now (for timeout logging).
    var currentStep: AudioSetupStep { get }
    var isEngineRunning: Bool { get }
    func start(
        deviceID: AudioDeviceID?,
        generation: UInt64,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) async throws -> AudioHostStartResult
    func startBluetoothTrigger(deviceID: AudioDeviceID?, generation: UInt64) async throws -> AudioDeviceID
    /// Fire-and-forget teardown of `generation` (or whatever engine is current).
    func teardown(generation: UInt64?)
    func stop() async
}

// MARK: - AudioEngineHost (spec 015, T050)

/// Owns one `AVAudioEngine` and runs every engine/CoreAudio call made during start and stop
/// on its own serial queue, never on the main thread. Never touches `@MainActor` state.
/// If a call hangs, the facade abandons this host and creates a new one for the next attempt.
final class AudioEngineHost: AudioEngineHosting, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.apeek.verborra.audio-engine", qos: .userInitiated)
    /// Only mutated on `queue`; read under the lock for `isEngineRunning`.
    private let engineBox = OSAllocatedUnfairLock<AVAudioEngine?>(initialState: nil)
    /// Generation of the engine currently owned (only touched on `queue`).
    private var engineGeneration: UInt64 = 0

    private let currentStepRaw = ManagedAtomic<Int>(AudioSetupStep.idle.rawValue)

    /// The step running right now (for timeout logging).
    var currentStep: AudioSetupStep {
        AudioSetupStep(rawValue: currentStepRaw.load(ordering: .relaxed)) ?? .idle
    }

    var isEngineRunning: Bool {
        engineBox.withLock { $0?.isRunning ?? false }
    }

    // MARK: Start

    func start(
        deviceID: AudioDeviceID?,
        generation: UInt64,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) async throws -> AudioHostStartResult {
        try await runOnQueue {
            try self.performStart(deviceID: deviceID, generation: generation, onBuffer: onBuffer)
        }
    }

    /// Starts the engine without a tap so a Bluetooth headset switches to its mic profile (A2DP → HFP).
    /// Returns the resolved device. The next `start` replaces this engine.
    func startBluetoothTrigger(deviceID: AudioDeviceID?, generation: UInt64) async throws -> AudioDeviceID {
        try await runOnQueue {
            self.setStep(.btTrigger)
            defer { self.setStep(.idle) }
            self.discardEngine()
            let engine = AVAudioEngine()
            let resolved = try self.applyDevice(deviceID, to: engine)
            var startError: Error?
            if let exception = VBRTryCatch({
                engine.prepare()
                do { try engine.start() } catch { startError = error }
            }) {
                throw AudioSetupFailure(error: .objcException(step: "btTrigger", name: Self.name(exception), reason: Self.reason(exception)), timings: AudioSetupTimings())
            }
            if let startError {
                throw AudioSetupFailure(error: .engineStartFailed(step: "btTrigger", underlying: startError.localizedDescription), timings: AudioSetupTimings())
            }
            self.engineBox.withLock { $0 = engine }
            self.engineGeneration = generation
            return resolved
        }
    }

    // MARK: Stop

    /// Fire-and-forget teardown of `generation` (or whatever engine is current). Never awaited by cancel paths.
    func teardown(generation: UInt64?) {
        queue.async {
            guard generation == nil || generation == self.engineGeneration else { return }
            self.discardEngine()
        }
    }

    /// Stops the engine after a completed capture.
    func stop() async {
        _ = try? await runOnQueue { self.discardEngine() }
    }

    // MARK: - Private (host queue only)

    private func runOnQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performStart(
        deviceID: AudioDeviceID?,
        generation: UInt64,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) throws -> AudioHostStartResult {
        defer { setStep(.idle) }
        discardEngine()

        var timings = AudioSetupTimings()
        var created = try createEngine(deviceID: deviceID, timings: &timings)

        // 3a: a stale node format means the engine cached an old device rate — re-create once.
        if timings.nodeSampleRate != timings.hwSampleRate {
            timings.recreatedForStaleNode = true
            created = try createEngine(deviceID: deviceID, timings: &timings)
            if timings.nodeSampleRate != timings.hwSampleRate {
                throw AudioSetupFailure(error: .formatMismatch(node: timings.nodeSampleRate, hardware: timings.hwSampleRate), timings: timings)
            }
        }
        let (engine, resolved, format) = (created.engine, created.device, created.format)

        // 4: tap in the node's own format
        setStep(.installTap)
        var clock = ContinuousClock.now
        if let exception = VBRTryCatch({
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, time in
                onBuffer(buffer, time)
            }
        }) {
            throw AudioSetupFailure(error: .objcException(step: "installTap", name: Self.name(exception), reason: Self.reason(exception)), timings: timings)
        }
        timings.installTapMs = Self.ms(since: clock)

        // 5: prepare
        setStep(.prepare)
        clock = ContinuousClock.now
        if let exception = VBRTryCatch({ engine.prepare() }) {
            Self.removeTap(engine)
            throw AudioSetupFailure(error: .objcException(step: "prepare", name: Self.name(exception), reason: Self.reason(exception)), timings: timings)
        }
        timings.prepareMs = Self.ms(since: clock)

        // 6: start
        setStep(.start)
        clock = ContinuousClock.now
        var startError: Error?
        if let exception = VBRTryCatch({
            do { try engine.start() } catch { startError = error }
        }) {
            Self.removeTap(engine)
            throw AudioSetupFailure(error: .objcException(step: "start", name: Self.name(exception), reason: Self.reason(exception)), timings: timings)
        }
        if let startError {
            Self.removeTap(engine)
            throw AudioSetupFailure(error: .engineStartFailed(step: "start", underlying: startError.localizedDescription), timings: timings)
        }
        timings.startMs = Self.ms(since: clock)

        engineBox.withLock { $0 = engine }
        engineGeneration = generation
        return AudioHostStartResult(timings: timings, nodeFormat: format, resolvedDevice: resolved, deviceName: CoreAudioQuery.name(resolved))
    }

    /// Result of steps 1–3.
    private struct CreatedEngine {
        let engine: AVAudioEngine
        let device: AudioDeviceID
        let format: AVAudioFormat
    }

    /// Steps 1–3: create the engine, set the device, read the node and hardware formats.
    private func createEngine(
        deviceID: AudioDeviceID?,
        timings: inout AudioSetupTimings
    ) throws -> CreatedEngine {
        setStep(.engineCreate)
        var clock = ContinuousClock.now
        let engine = AVAudioEngine()
        _ = engine.inputNode
        timings.engineCreateMs += Self.ms(since: clock)

        setStep(.setDevice)
        clock = ContinuousClock.now
        let resolved: AudioDeviceID
        do {
            resolved = try applyDevice(deviceID, to: engine)
        } catch let failure as AudioSetupFailure {
            throw AudioSetupFailure(error: failure.error, timings: timings)
        }
        timings.setDeviceMs += Self.ms(since: clock)

        setStep(.readFormats)
        clock = ContinuousClock.now
        let format = engine.inputNode.outputFormat(forBus: 0)
        let hwRate = CoreAudioQuery.nominalSampleRate(resolved) ?? format.sampleRate
        timings.readFormatsMs += Self.ms(since: clock)
        timings.nodeSampleRate = format.sampleRate
        timings.hwSampleRate = hwRate
        timings.channels = format.channelCount

        guard format.channelCount > 0, format.sampleRate > 0, hwRate > 0 else {
            throw AudioSetupFailure(error: .deviceUnavailable(step: "readFormats"), timings: timings)
        }
        return CreatedEngine(engine: engine, device: resolved, format: format)
    }

    /// Step 2: point the input unit at `deviceID` (nil = system default) and check the result.
    private func applyDevice(_ deviceID: AudioDeviceID?, to engine: AVAudioEngine) throws -> AudioDeviceID {
        guard let deviceID else {
            return engine.inputNode.auAudioUnit.deviceID
        }
        guard CoreAudioQuery.hasInputStreams(deviceID), let audioUnit = engine.inputNode.audioUnit else {
            throw AudioSetupFailure(error: .deviceUnavailable(step: "setDevice"), timings: AudioSetupTimings())
        }
        var device = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioSetupFailure(error: .deviceUnavailable(step: "setDevice"), timings: AudioSetupTimings())
        }
        return deviceID
    }

    private func discardEngine() {
        guard let engine = engineBox.withLock({ $0 }) else { return }
        _ = VBRTryCatch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engineBox.withLock { $0 = nil }
    }

    private func setStep(_ step: AudioSetupStep) {
        currentStepRaw.store(step.rawValue, ordering: .relaxed)
    }

    private static func removeTap(_ engine: AVAudioEngine) {
        _ = VBRTryCatch { engine.inputNode.removeTap(onBus: 0) }
    }

    private static func ms(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    private static func name(_ error: Error) -> String {
        ((error as NSError).userInfo["name"] as? String) ?? "NSException"
    }

    private static func reason(_ error: Error) -> String {
        ((error as NSError).userInfo["reason"] as? String) ?? ""
    }
}

// MARK: - raceWithTimeout

/// Runs `operation` and returns its result, or throws `onTimeout()` after `timeout`, or
/// `CancellationError` when the calling task is cancelled — whichever happens first.
/// Unlike a task group it never waits for a stuck operation to finish.
func raceWithTimeout<T: Sendable>(
    _ timeout: Duration,
    onTimeout: @escaping @Sendable () -> Error,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let state = OSAllocatedUnfairLock<CheckedContinuation<T, Error>?>(initialState: nil)
    let tasks = OSAllocatedUnfairLock<[Task<Void, Never>]>(initialState: [])

    @Sendable func finish(_ result: Result<T, Error>) {
        let continuation = state.withLock { value -> CheckedContinuation<T, Error>? in
            defer { value = nil }
            return value
        }
        continuation?.resume(with: result)
        tasks.withLock { $0.forEach { $0.cancel() } }
    }

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            state.withLock { $0 = continuation }
            let work = Task {
                do { finish(.success(try await operation())) } catch { finish(.failure(error)) }
            }
            let timer = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                finish(.failure(onTimeout()))
            }
            tasks.withLock { $0 = [work, timer] }
            if Task.isCancelled { finish(.failure(CancellationError())) }
        }
    } onCancel: {
        finish(.failure(CancellationError()))
    }
}
