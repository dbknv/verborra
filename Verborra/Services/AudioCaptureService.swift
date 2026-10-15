import Accelerate
import Atomics
@preconcurrency import AVFoundation
import Foundation

// MARK: - DeviceErrorReason

/// Причина ошибки аудио-устройства (FR-012, FR-014).
enum DeviceErrorReason: Sendable {
    /// Устройство отключено (FR-012). Сообщение: «Устройство потеряно»
    case disconnected
    /// Устройство изменило аудио-формат (FR-014). Сообщение: «Аудио-устройство изменило формат»
    case formatChanged
}

// MARK: - StartTimeouts (spec 015, research R7/R31)

/// Time limits for one start attempt.
struct StartTimeouts: Equatable, Sendable {
    /// Engine setup on the host queue.
    var setup: Duration = .milliseconds(1800)
    /// Wait for the first buffer; a running engine without buffers still counts as success.
    var firstBuffer: Duration = .milliseconds(600)
    /// Bluetooth trigger plus the wait for the headset's rate to settle.
    var bluetooth: Duration = .seconds(5)
}

// MARK: - AudioCaptureServiceProtocol

@MainActor
protocol AudioCaptureServiceProtocol: AnyObject {
    var audioLevel: Float { get }
    var currentDuration: TimeInterval { get }
    var onAutoStop: (@Sendable @MainActor () -> Void)? { get set }
    var onDeviceError: (@Sendable @MainActor (_ deviceName: String?, _ reason: DeviceErrorReason) -> Void)? { get set }
    var audioSaveSettings: (enabled: Bool, folderBookmark: Data?)? { get set }
    /// Milliseconds the last attempt spent on the Bluetooth mode switch (0 if none). For event E13.
    var lastBluetoothSwitchMs: Double { get }
    /// One start attempt (spec 015): no retries, never changes the device. Throws `AudioSetupError`
    /// for engine failures, `RecordingError` for permission problems.
    func startRecording(
        deviceID: String?,
        maxDuration: MaxRecordingDuration,
        awaitBluetoothSwitch: Bool,
        attempt: Int,
        timeouts: StartTimeouts
    ) async throws
    /// Abandons a start in progress. Never blocks.
    func cancelStart()
    func stopRecording() async throws -> Data
    func resetRecording()
    func updateLevelsFromAtomic()
    func availableInputDevices() -> [(id: String, name: String)]
}

extension AudioCaptureServiceProtocol {
    func startRecording(
        deviceID: String?,
        maxDuration: MaxRecordingDuration,
        awaitBluetoothSwitch: Bool = false,
        attempt: Int = 1
    ) async throws {
        try await startRecording(
            deviceID: deviceID,
            maxDuration: maxDuration,
            awaitBluetoothSwitch: awaitBluetoothSwitch,
            attempt: attempt,
            timeouts: StartTimeouts()
        )
    }
}

// MARK: - AudioCaptureService

@MainActor
@Observable
final class AudioCaptureService: AudioCaptureServiceProtocol {
    /// spec 015 (US2): every engine call during start/stop runs on the host's queue.
    private var host: any AudioEngineHosting
    @ObservationIgnored private let hostFactory: @MainActor () -> any AudioEngineHosting
    /// Set when a call on the current host timed out; only then is the host abandoned (research R31).
    private nonisolated let hostTimedOut = ManagedAtomic<Bool>(false)
    /// Bumped on every attempt and on cancel; late results from older generations are ignored.
    private var generation: UInt64 = 0
    private nonisolated let activeGeneration = ManagedAtomic<UInt64>(0)
    /// While the engine restarts after a device format change, "engine not running" isn't a disconnect.
    private var isRestartingAfterFormatChange = false
    private(set) var lastBluetoothSwitchMs: Double = 0
    private var maxDurationSeconds: TimeInterval = MaxRecordingDuration.default.timeInterval
    private static let maxFileSize = 25 * 1024 * 1024  // 25 MB
    private var recordingStartTime: Date?
    private let targetSampleRate: Double = 16000
    private var currentDeviceName: String?
    private var currentDeviceIDForRecording: String?

    // MARK: - Device format monitoring

    private var activeListenerDeviceID: AudioDeviceID?
    private var formatListenerBlock: AudioObjectPropertyListenerBlock?
    private var lastKnownSampleRate: Double?

    // Bluetooth A2DP→HFP stabilization (FR-038/039)
    private var btStabilizationContinuation: CheckedContinuation<Double, any Error>?
    private var btStabilizationListenerBlock: AudioObjectPropertyListenerBlock?
    private var btStabilizationDeviceID: AudioDeviceID?
    private var btStabilizationDebounce: DispatchWorkItem?
    private var btStabilizationTimeout: DispatchWorkItem?
    private var drainLogCounter: Int = 0
    private static let drainLogInterval: Int = 50

    // MARK: - Audio File Writer (T032)

    private let audioFileWriter = AudioFileWriter()
    private var isSecurityScopedAccessActive = false
    private var securityScopedURL: URL?

    // MARK: - Lock-free concurrency primitives (T002, T007)

    private nonisolated let ringBuffer = SPSCRingBuffer<AVAudioPCMBuffer>(capacity: 256)
    private var accumulatedBuffers: [AVAudioPCMBuffer] = []

    private nonisolated let _atomicAudioLevel = ManagedAtomic<UInt32>(0)
    private nonisolated let _atomicDuration = ManagedAtomic<UInt64>(0)
    private nonisolated let _isRecording = ManagedAtomic<Bool>(false)
    private nonisolated let _consecutiveZeroBuffers = ManagedAtomic<Int>(0)
    private nonisolated let _droppedBuffers = ManagedAtomic<Int>(0)
    private nonisolated let _maxDurationBits = ManagedAtomic<UInt64>(0)

    // MARK: - Logging (T024-T030)

    private let logAudio = DiagnosticLogger.logger(for: .audio)
    private let logEngine = DiagnosticLogger.logger(for: .engine)
    private let logTap = DiagnosticLogger.logger(for: .tap)
    private let logStream = DiagnosticLogger.logger(for: .stream)
    private let logBluetooth = DiagnosticLogger.logger(for: .bluetooth)

    // MARK: - Observable properties

    private(set) var audioLevel: Float = 0.0
    private(set) var currentDuration: TimeInterval = 0.0
    var onAutoStop: (@Sendable @MainActor () -> Void)?
    var onDeviceError: (@Sendable @MainActor (_ deviceName: String?, _ reason: DeviceErrorReason) -> Void)?

    /// Settings for file writing — set before startRecording.
    var audioSaveSettings: (enabled: Bool, folderBookmark: Data?)? {
        didSet {
            // If disabled while writing, stop
            if audioSaveSettings?.enabled == false && audioFileWriter.isWriting {
                stopFileWriting()
            }
        }
    }

    init(hostFactory: @escaping @MainActor () -> any AudioEngineHosting = { AudioEngineHost() }) {
        self.hostFactory = hostFactory
        self.host = hostFactory()
    }

    // MARK: - Host lifecycle (spec 015, US9, research R31)

    /// Before each start: a healthy host is reused, so the teardown queued here (or by `resetRecording`)
    /// runs before the next start on the same serial queue and stop/start never overlap (FR-050).
    /// A host whose call timed out is abandoned and replaced.
    func prepareHostForStart() {
        if hostTimedOut.load(ordering: .acquiring) {
            logEngine.info("Audio host abandoned after timeout", metadata: [
                "step": host.currentStep.name
            ])
            host = hostFactory()
            hostTimedOut.store(false, ordering: .releasing)
        } else {
            host.teardown(generation: nil)
        }
    }

    /// Marks the current host as stuck; called from the timeout paths.
    nonisolated func noteHostTimedOut() {
        hostTimedOut.store(true, ordering: .releasing)
    }

    /// Display name for logs and errors: the device's name, "System Default" for nil, else the raw id.
    static func displayName(forDeviceID deviceID: String?, resolver: (AudioDeviceID) -> String?) -> String {
        guard let deviceID else { return "System Default" }
        return AudioDeviceID(deviceID).flatMap(resolver) ?? deviceID
    }

    // MARK: - Recording Operations (T010, T011, T012; spec 015 T051)

    func startRecording(
        deviceID: String?,
        maxDuration: MaxRecordingDuration,
        awaitBluetoothSwitch: Bool,
        attempt: Int,
        timeouts: StartTimeouts
    ) async throws {
        // FR-010: Ignore duplicate calls
        guard !_isRecording.load(ordering: .acquiring) else {
            logAudio.info("Duplicate startRecording ignored")
            return
        }

        currentDeviceName = Self.displayName(forDeviceID: deviceID, resolver: CoreAudioQuery.name)
        currentDeviceIDForRecording = deviceID
        lastBluetoothSwitchMs = 0
        MainThreadWatchdog.setDevice(name: currentDeviceName, id: deviceID)
        logAudio.info("startRecording", metadata: [
            "deviceID": deviceID ?? "default",
            "attempt": "\(attempt)",
            "maxDuration": "\(maxDuration.timeInterval)s",
            "awaitBluetoothSwitch": "\(awaitBluetoothSwitch)"
        ])

        // Permission check
        let micStatus = PermissionManager.shared.microphoneStatus
        switch micStatus {
        case .denied, .restricted:
            logAudio.error("Microphone permission denied", errorCode: "microphonePermissionDenied")
            throw RecordingError.microphonePermissionDenied
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            PermissionManager.shared.checkMicrophoneStatus()
            if !granted {
                logAudio.error("Microphone permission denied after request", errorCode: "microphonePermissionDenied")
                throw RecordingError.microphonePermissionDenied
            }
        case .granted:
            break
        }

        // Reuse a healthy host; replace one whose call timed out (contracts/recording-start.md)
        prepareHostForStart()

        generation &+= 1
        let gen = generation
        activeGeneration.store(gen, ordering: .releasing)

        // Reset buffers and atomics
        ringBuffer.reset()
        accumulatedBuffers.removeAll()
        _atomicAudioLevel.store(0, ordering: .relaxed)
        _atomicDuration.store(0, ordering: .relaxed)
        _consecutiveZeroBuffers.store(0, ordering: .relaxed)
        _droppedBuffers.store(0, ordering: .relaxed)

        recordingStartTime = Date()
        currentDuration = 0
        audioLevel = 0
        drainLogCounter = 0
        maxDurationSeconds = maxDuration.timeInterval
        _maxDurationBits.store(maxDuration.timeInterval.bitPattern, ordering: .relaxed)

        let audioDeviceID = deviceID.flatMap { AudioDeviceID($0) }
        var timings = AudioSetupTimings()
        var outcome = "failed"
        do {
            // BT A2DP→HFP: start a trigger engine, wait for the rate to settle (own 5 s budget)
            if awaitBluetoothSwitch {
                let btStart = ContinuousClock.now
                try await runBluetoothSwitch(deviceID: audioDeviceID, generation: gen, timeout: timeouts.bluetooth)
                lastBluetoothSwitchMs = Self.ms(since: btStart)
                try checkGeneration(gen)
            }

            let result = try await startHost(deviceID: audioDeviceID, generation: gen, setupTimeout: timeouts.setup)
            timings = result.timings
            try checkGeneration(gen)

            currentDeviceName = result.deviceName ?? currentDeviceName
            MainThreadWatchdog.setDevice(name: currentDeviceName, id: deviceID)
            lastKnownSampleRate = result.timings.nodeSampleRate
            installDeviceFormatListener(deviceID: result.resolvedDevice)
            startFileWritingIfNeeded(deviceName: currentDeviceName ?? "System Default", format: result.nodeFormat)

            // FR-010: Mark as recording after engine started
            _isRecording.store(true, ordering: .releasing)

            // First buffer: if the engine runs but no buffer arrived yet, that still counts as success
            let waitStart = ContinuousClock.now
            let deadline = waitStart + timeouts.firstBuffer
            while ringBuffer.isEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
                try checkGeneration(gen)
            }
            timings.firstBufferMs = Self.ms(since: waitStart)
            if ringBuffer.isEmpty && !host.isEngineRunning {
                throw AudioSetupFailure(error: .engineStartFailed(step: "firstBuffer", underlying: "engine stopped before the first buffer"), timings: timings)
            }

            outcome = "ok"
            logRecordingOnDevice(timings: timings)
            logSetupTimings(timings, attempt: attempt, generation: gen, outcome: outcome)
        } catch {
            let setupError: AudioSetupError
            switch error {
            case let failure as AudioSetupFailure:
                setupError = failure.error
                timings = failure.timings
            case let failure as AudioSetupError:
                setupError = failure
            case is CancellationError:
                setupError = .cancelled
            default:
                setupError = .engineStartFailed(step: host.currentStep.name, underlying: error.localizedDescription)
            }
            outcome = {
                switch setupError {
                case .timeout: return "timeout"
                case .cancelled: return "cancelled"
                default: return "failed"
                }
            }()

            // Only clean up if this attempt is still the current one; a cancel already did it.
            if activeGeneration.load(ordering: .acquiring) == gen {
                _isRecording.store(false, ordering: .releasing)
                removeDeviceFormatListener()
                stopFileWriting()
                cleanupBTStabilization()
            }
            host.teardown(generation: gen)

            logSetupTimings(timings, attempt: attempt, generation: gen, outcome: outcome)
            if setupError != .cancelled {
                logEngine.error(
                    "Audio setup failed",
                    parameters: [
                        "step": setupError.step,
                        "attempt": "\(attempt)",
                        "deviceName": currentDeviceName ?? "Unknown",
                        "deviceID": deviceID ?? "default",
                        "nodeSampleRate": "\(timings.nodeSampleRate)",
                        "hwSampleRate": "\(timings.hwSampleRate)",
                        "reason": setupError.reason
                    ],
                    errorCode: setupError.errorCode
                )
            }
            throw setupError
        }
    }

    func cancelStart() {
        generation &+= 1
        activeGeneration.store(generation, ordering: .releasing)
        _isRecording.store(false, ordering: .releasing)
        host.teardown(generation: nil)
        if let continuation = btStabilizationContinuation {
            btStabilizationContinuation = nil
            continuation.resume(throwing: AudioSetupError.cancelled)
        }
        cleanupBTStabilization()
        removeDeviceFormatListener()
        stopFileWriting()
        ringBuffer.reset()
        accumulatedBuffers.removeAll()
    }

    // MARK: - Private: start helpers (spec 015)

    private func checkGeneration(_ gen: UInt64) throws {
        guard activeGeneration.load(ordering: .acquiring) == gen, !Task.isCancelled else {
            throw AudioSetupError.cancelled
        }
    }

    /// Host start raced against `setupTimeout`; on timeout the step that hung is reported.
    private func startHost(deviceID: AudioDeviceID?, generation gen: UInt64, setupTimeout: Duration) async throws -> AudioHostStartResult {
        let host = self.host
        let timedOut = hostTimedOut
        let generationCheck = activeGeneration
        let onBuffer: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { [weak self] buffer, time in
            guard generationCheck.load(ordering: .relaxed) == gen else { return }
            self?.handleAudioBuffer(buffer, time: time)
        }
        return try await raceWithTimeout(setupTimeout, onTimeout: {
            timedOut.store(true, ordering: .releasing)
            return AudioSetupError.timeout(step: host.currentStep.name)
        }, operation: {
            try await host.start(deviceID: deviceID, generation: gen, onBuffer: onBuffer)
        })
    }

    /// Trigger engine + wait for the headset's rate to settle, both within `timeout` (research R31, FR-049).
    private func runBluetoothSwitch(deviceID: AudioDeviceID?, generation gen: UInt64, timeout: Duration) async throws {
        let host = self.host
        let timedOut = hostTimedOut
        let started = ContinuousClock.now
        let resolvedID = try await raceWithTimeout(timeout, onTimeout: {
            timedOut.store(true, ordering: .releasing)
            return AudioSetupError.timeout(step: "btTrigger")
        }, operation: {
            try await host.startBluetoothTrigger(deviceID: deviceID, generation: gen)
        })
        let initialRate = Self.deviceNominalSampleRate(for: resolvedID) ?? 48000
        logBluetooth.info("bt_switch_engine_started", metadata: [
            "deviceName": currentDeviceName ?? "Unknown",
            "deviceID": "\(resolvedID)",
            "initialRate": "\(initialRate)"
        ])
        let remaining = timeout - (ContinuousClock.now - started)
        let finalRate = try await awaitBluetoothStabilization(
            deviceID: resolvedID,
            initialRate: initialRate,
            timeout: max(remaining, .milliseconds(1))
        )
        logBluetooth.info("bt_switch_stabilized", metadata: [
            "deviceName": currentDeviceName ?? "Unknown",
            "deviceID": "\(resolvedID)",
            "finalRate": "\(finalRate)"
        ])
    }

    private func logRecordingOnDevice(timings: AudioSetupTimings) {
        // FR-012: Log device ID, name, and sample rate at recording start
        logAudio.info("Recording on device", metadata: [
            "deviceName": currentDeviceName ?? "System Default",
            "deviceID": currentDeviceIDForRecording ?? "default",
            "sampleRate": "\(timings.nodeSampleRate)"
        ])
    }

    /// Event E1 (contracts/diagnostic-events.md).
    private func logSetupTimings(_ timings: AudioSetupTimings, attempt: Int, generation gen: UInt64, outcome: String) {
        func ms(_ value: Double) -> String { String(format: "%.1f", value) }
        logEngine.info("Audio setup timings", metadata: [
            "attempt": "\(attempt)",
            "generation": "\(gen)",
            "outcome": outcome,
            "deviceName": currentDeviceName ?? "Unknown",
            "deviceID": currentDeviceIDForRecording ?? "default",
            "engineCreateMs": ms(timings.engineCreateMs),
            "setDeviceMs": ms(timings.setDeviceMs),
            "readFormatsMs": ms(timings.readFormatsMs),
            "installTapMs": ms(timings.installTapMs),
            "prepareMs": ms(timings.prepareMs),
            "startMs": ms(timings.startMs),
            "firstBufferMs": timings.firstBufferMs.map(ms) ?? "",
            "nodeSampleRate": "\(timings.nodeSampleRate)",
            "hwSampleRate": "\(timings.hwSampleRate)",
            "channels": "\(timings.channels)",
            "recreatedForStaleNode": "\(timings.recreatedForStaleNode)"
        ])
    }

    private static func ms(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    func stopRecording() async throws -> Data {
        // FR-010: throw if not recording
        guard _isRecording.load(ordering: .acquiring) else {
            throw RecordingError.notRecording
        }

        _isRecording.store(false, ordering: .releasing)

        let duration = currentDuration
        logAudio.info("stopRecording", metadata: [
            "deviceName": currentDeviceName ?? "Unknown",
            "deviceID": currentDeviceIDForRecording ?? "default",
            "duration": String(format: "%.1fs", duration)
        ])

        removeDeviceFormatListener()
        stopFileWriting()
        await host.stop()
        audioLevel = 0

        // T011: Combine accumulated + remaining from ring buffer
        let remaining = ringBuffer.readAll()
        let buffers = accumulatedBuffers + remaining
        accumulatedBuffers.removeAll()

        logAudio.debug("stopRecording details", metadata: [
            "deviceName": currentDeviceName ?? "Unknown",
            "deviceID": currentDeviceIDForRecording ?? "default",
            "bufferCount": "\(buffers.count)",
            "duration": String(format: "%.1fs", duration)
        ])

        guard !buffers.isEmpty else {
            logAudio.error("No audio buffers captured (silence)",
                          parameters: ["deviceName": currentDeviceName ?? "Unknown", "deviceID": currentDeviceIDForRecording ?? "default"],
                          errorCode: "silenceDetected")
            throw RecordingError.silenceDetected
        }

        return try convertToWAV(buffers: buffers)
    }

    func resetRecording() {
        // FR-010: Ignore if not recording
        guard _isRecording.load(ordering: .acquiring) else {
            logAudio.info("Reset ignored — not recording")
            return
        }

        _isRecording.store(false, ordering: .releasing)
        logAudio.info("resetRecording", metadata: [
            "deviceName": currentDeviceName ?? "Unknown",
            "deviceID": currentDeviceIDForRecording ?? "default"
        ])

        removeDeviceFormatListener()
        lastKnownSampleRate = nil
        stopFileWriting()
        host.teardown(generation: nil)
        ringBuffer.reset()
        accumulatedBuffers.removeAll()
        _atomicAudioLevel.store(0, ordering: .relaxed)
        _atomicDuration.store(0, ordering: .relaxed)
        audioLevel = 0
        currentDuration = 0
        recordingStartTime = nil
    }

    // MARK: - updateLevelsFromAtomic (T013, T013a, T013b)

    func updateLevelsFromAtomic() {
        // Read atomic audio level
        let levelBits = _atomicAudioLevel.load(ordering: .relaxed)
        audioLevel = Float(bitPattern: levelBits)

        // Read atomic duration
        let durationBits = _atomicDuration.load(ordering: .relaxed)
        currentDuration = TimeInterval(bitPattern: durationBits)

        // Drain ring buffer into accumulatedBuffers (FR-002)
        let drained = ringBuffer.readAll()
        if !drained.isEmpty {
            accumulatedBuffers.append(contentsOf: drained)
        }

        // T035: Log ring buffer stats at drain time (FR-023) — throttled
        let dropped = _droppedBuffers.load(ordering: .relaxed)
        if !drained.isEmpty {
            drainLogCounter += 1
            if drainLogCounter == 1 || drainLogCounter % Self.drainLogInterval == 0 {
                logTap.debug("Ring buffer drain", metadata: [
                    "deviceName": currentDeviceName ?? "System Default",
                    "deviceID": currentDeviceIDForRecording ?? "default",
                    "drained": "\(drained.count)",
                    "accumulated": "\(accumulatedBuffers.count)",
                    "dropped": "\(dropped)",
                    "drainCycle": "\(drainLogCounter)"
                ])
            }
        }
        if dropped > 0 {
            logTap.error("Ring buffer overflow: \(dropped) buffers dropped",
                        parameters: ["deviceName": currentDeviceName ?? "Unknown", "deviceID": currentDeviceIDForRecording ?? "default"],
                        errorCode: "ringBufferOverflow")
        }

        guard _isRecording.load(ordering: .acquiring) else { return }

        // T013a: Silent device detection (FR-013)
        let zeroCount = _consecutiveZeroBuffers.load(ordering: .relaxed)
        // Approximate: at 48kHz with 4096 buffer ≈ 85ms per buffer, 10s ≈ 117 buffers
        // Conservative threshold: 100 consecutive zero buffers ≈ 8.5s at 48kHz
        if zeroCount > 100 {
            logAudio.info("Silent device detected, triggering autoStop", metadata: [
                "deviceName": currentDeviceName ?? "Unknown",
                "deviceID": currentDeviceIDForRecording ?? "default",
                "zeroBufferCount": "\(zeroCount)"
            ])
            triggerAutoStop()
            return
        }

        // T013b: Device error detection (engine stopped unexpectedly)
        if !isRestartingAfterFormatChange && !host.isEngineRunning {
            _isRecording.store(false, ordering: .releasing)
            let name = currentDeviceName
            logAudio.error("Engine stopped unexpectedly",
                          parameters: ["deviceName": currentDeviceName ?? "Unknown", "deviceID": currentDeviceIDForRecording ?? "default"],
                          errorCode: "deviceError")
            // Simple heuristic: if engine stopped, it's likely a disconnect
            onDeviceError?(name, .disconnected)
        }
    }

    // MARK: - Device Enumeration

    func availableInputDevices() -> [(id: String, name: String)] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID -> (id: String, name: String)? in
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else {
                return nil
            }

            guard let name = Self.deviceName(for: deviceID) else { return nil }
            return (id: String(deviceID), name: name)
        }
    }

    func logAvailableDevices() {
        let devices = availableInputDevices()
        logAudio.debug("Available input devices", metadata: [
            "count": "\(devices.count)",
            "devices": devices.map { "\($0.name) (\($0.id))" }.joined(separator: ", ")
        ])
    }

    func logBluetoothEvent(_ event: String, deviceID: String, metadata: [String: String]? = nil) {
        guard BluetoothLogThrottle.shared.shouldLog(deviceID: deviceID) else { return }
        logBluetooth.info(event, metadata: metadata)
    }

    // MARK: - Private: nonisolated audio handler (T008)

    /// Audio tap callback — executes on real-time audio thread.
    /// Only lock-free operations allowed.
    private nonisolated func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard _isRecording.load(ordering: .acquiring) else { return }

        // Calculate audio level (RMS)
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var rms: Float = 0
        for i in 0..<frameLength {
            rms += channelData[i] * channelData[i]
        }
        rms = sqrt(rms / Float(max(frameLength, 1)))
        let level = min(rms * 5, 1.0)

        // Atomic store for audioLevel (R-003)
        _atomicAudioLevel.store(level.bitPattern, ordering: .relaxed)

        // Calculate and store duration atomically
        // Use a simple counter-based approach since we can't access recordingStartTime
        let currentBits = _atomicDuration.load(ordering: .relaxed)
        let currentDur = TimeInterval(bitPattern: currentBits)
        let bufferDuration = TimeInterval(buffer.frameLength) / buffer.format.sampleRate
        let newDuration = currentDur + bufferDuration
        _atomicDuration.store(newDuration.bitPattern, ordering: .relaxed)

        // Write to ring buffer (FR-002)
        if !ringBuffer.write(buffer) {
            _ = _droppedBuffers.wrappingIncrementThenLoad(ordering: .relaxed)
        }

        // Write to disk file if enabled (T032)
        if audioFileWriter.isWriting {
            try? audioFileWriter.write(buffer: buffer)
        }

        // Zero buffer detection (FR-013, R-008)
        var maxAmplitude: Float = 0
        vDSP_maxmgv(channelData, 1, &maxAmplitude, vDSP_Length(frameLength))
        if maxAmplitude == 0.0 {
            _ = _consecutiveZeroBuffers.wrappingIncrementThenLoad(ordering: .relaxed)
        } else {
            _consecutiveZeroBuffers.store(0, ordering: .relaxed)
        }

        // Check max duration (auto-stop via atomic)
        let maxDurBits = _maxDurationBits.load(ordering: .relaxed)
        let maxDur = TimeInterval(bitPattern: maxDurBits)
        if newDuration >= maxDur {
            _isRecording.store(false, ordering: .releasing)
            DispatchQueue.main.async { [weak self] in
                self?.onAutoStop?()
            }
            return
        }

        // Estimate data size
        let estimatedBytes = Int(newDuration * 16000 * 2) + 44
        if estimatedBytes >= 25 * 1024 * 1024 {
            _isRecording.store(false, ordering: .releasing)
            DispatchQueue.main.async { [weak self] in
                self?.onAutoStop?()
            }
        }
    }

    // MARK: - Bluetooth A2DP→HFP Stabilization

    /// Wait for BT sample rate to stabilize after engine start (300ms debounce, `timeout` overall).
    /// Works for both A2DP→HFP switch and already-HFP with potential rate transients.
    private func awaitBluetoothStabilization(deviceID: AudioDeviceID, initialRate: Double, timeout: Duration) async throws -> Double {
        let timeoutSeconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        return try await withCheckedThrowingContinuation { continuation in
            self.btStabilizationContinuation = continuation
            self.btStabilizationDeviceID = deviceID

            // Listen for sample rate change
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.handleBTStabilizationEvent()
                }
            }
            self.btStabilizationListenerBlock = block

            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, block)

            // Initial check after 300ms — if rate already stable (e.g. already HFP), resolve early
            let initialCheck = DispatchWorkItem { [weak self] in
                guard let self, self.btStabilizationContinuation != nil else { return }
                let currentRate = Self.deviceNominalSampleRate(for: deviceID) ?? 0
                if currentRate > 0 && currentRate <= 24000 {
                    // Already at HFP rate — stable
                    self.cleanupBTStabilization()
                    self.btStabilizationContinuation = nil
                    continuation.resume(returning: currentRate)
                }
                // Otherwise keep waiting for listener events
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: initialCheck)

            // Overall timeout: what is left of the Bluetooth budget (FR-014, FR-049)
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, let cont = self.btStabilizationContinuation else { return }
                self.cleanupBTStabilization()
                let currentRate = Self.deviceNominalSampleRate(for: deviceID) ?? initialRate
                self.logBluetooth.info("bt_switch_timeout", metadata: [
                    "deviceName": self.currentDeviceName ?? "Unknown",
                    "deviceID": "\(deviceID)",
                    "currentRate": "\(currentRate)"
                ])
                cont.resume(returning: currentRate)
            }
            self.btStabilizationTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
        }
    }

    /// Called when sample rate property changes during BT stabilization.
    private func handleBTStabilizationEvent() {
        guard let deviceID = btStabilizationDeviceID else { return }

        let newRate = Self.deviceNominalSampleRate(for: deviceID) ?? 0
        // Only accept HFP-range rate (≤24kHz) — ignore spurious A2DP notifications
        // caused by engine setup. We're waiting specifically for the HFP switch.
        guard newRate > 0, newRate <= 24000 else { return }

        // Debounce: wait 300ms, then confirm rate is still HFP
        btStabilizationDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let cont = self.btStabilizationContinuation else { return }
            let finalRate = Self.deviceNominalSampleRate(for: deviceID) ?? newRate
            guard finalRate <= 24000 else { return } // Rate changed back — keep waiting
            self.cleanupBTStabilization()
            self.btStabilizationContinuation = nil
            cont.resume(returning: finalRate)
        }
        btStabilizationDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Remove BT stabilization listener and cancel pending work.
    private func cleanupBTStabilization() {
        btStabilizationDebounce?.cancel()
        btStabilizationDebounce = nil
        btStabilizationTimeout?.cancel()
        btStabilizationTimeout = nil
        btStabilizationContinuation = nil

        if let deviceID = btStabilizationDeviceID, let block = btStabilizationListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, nil, block)
        }
        btStabilizationListenerBlock = nil
        btStabilizationDeviceID = nil
    }

    // MARK: - Device Format Change Monitoring

    /// Query the device's actual nominal sample rate via CoreAudio
    private static func deviceNominalSampleRate(for deviceID: AudioDeviceID) -> Double? {
        CoreAudioQuery.nominalSampleRate(deviceID)
    }

    /// Install CoreAudio property listener for sample rate changes (AirPods mode switching)
    private func installDeviceFormatListener(deviceID: AudioDeviceID) {
        removeDeviceFormatListener()
        activeListenerDeviceID = deviceID

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.handleDeviceFormatChange()
            }
        }
        formatListenerBlock = block

        var sampleRateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &sampleRateAddress, nil, block)
        if status != noErr {
            logBluetooth.error("Failed to add sample rate listener", parameters: [
                "deviceName": Self.deviceName(for: deviceID) ?? "Unknown",
                "deviceID": "\(deviceID)",
                "status": "\(status)"
            ], errorCode: "listenerInstallFailed")
        } else {
            logBluetooth.info("Device format listener installed", metadata: [
                "deviceName": Self.deviceName(for: deviceID) ?? "Unknown",
                "deviceID": "\(deviceID)"
            ])
        }
    }

    private func removeDeviceFormatListener() {
        guard let deviceID = activeListenerDeviceID, let block = formatListenerBlock else { return }
        var sampleRateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &sampleRateAddress, nil, block)
        logBluetooth.debug("Device format listener removed", metadata: [
            "deviceName": Self.deviceName(for: deviceID) ?? "Unknown",
            "deviceID": "\(deviceID)"
        ])
        formatListenerBlock = nil
        activeListenerDeviceID = nil
    }

    /// Handle device format/sample rate change — restart engine and reset recording from scratch
    private func handleDeviceFormatChange() {
        guard _isRecording.load(ordering: .acquiring) else { return }

        let deviceID = activeListenerDeviceID
        let newRate = deviceID.flatMap { Self.deviceNominalSampleRate(for: $0) }

        // Ignore spurious notifications where sample rate hasn't actually changed
        if let newRate, let lastRate = lastKnownSampleRate, newRate == lastRate {
            logBluetooth.debug("Format listener fired but sample rate unchanged, ignoring", metadata: [
                "deviceName": currentDeviceName ?? "Unknown",
                "deviceID": deviceID.map { "\($0)" } ?? "unknown",
                "sampleRate": "\(newRate)"
            ])
            return
        }

        logBluetooth.info("Device format changed, restarting recording", metadata: [
            "deviceName": currentDeviceName ?? "Unknown",
            "deviceID": deviceID.map { "\($0)" } ?? "unknown",
            "newSampleRate": newRate.map { "\($0)" } ?? "unknown",
            "oldSampleRate": lastKnownSampleRate.map { "\($0)" } ?? "unknown"
        ])

        // Stop current engine and file writing (teardown runs on the host queue)
        removeDeviceFormatListener()
        stopFileWriting()
        isRestartingAfterFormatChange = true
        generation &+= 1
        let gen = generation
        activeGeneration.store(gen, ordering: .releasing)
        host.teardown(generation: nil)

        // Reset all buffers — recording starts from scratch
        ringBuffer.reset()
        accumulatedBuffers.removeAll()
        _atomicAudioLevel.store(0, ordering: .relaxed)
        _atomicDuration.store(0, ordering: .relaxed)
        _consecutiveZeroBuffers.store(0, ordering: .relaxed)
        _droppedBuffers.store(0, ordering: .relaxed)
        drainLogCounter = 0
        recordingStartTime = Date()
        currentDuration = 0
        audioLevel = 0

        // Restart with a fresh engine off the main thread
        if hostTimedOut.load(ordering: .acquiring) {
            host = hostFactory()
            hostTimedOut.store(false, ordering: .releasing)
        }
        let restartDeviceID = currentDeviceIDForRecording.flatMap { AudioDeviceID($0) }
        Task { @MainActor in
            defer { self.isRestartingAfterFormatChange = false }
            do {
                let result = try await self.startHost(deviceID: restartDeviceID, generation: gen, setupTimeout: .milliseconds(2400))
                try self.checkGeneration(gen)
                self.lastKnownSampleRate = result.timings.nodeSampleRate
                self.installDeviceFormatListener(deviceID: result.resolvedDevice)
                // Restart file writing with new format (FR-024)
                self.startFileWritingIfNeeded(deviceName: self.currentDeviceName ?? "System Default", format: result.nodeFormat)
                self.logBluetooth.info("Recording restarted after format change", metadata: [
                    "deviceName": self.currentDeviceName ?? "Unknown",
                    "deviceID": self.currentDeviceIDForRecording ?? "default"
                ])
            } catch {
                guard self.activeGeneration.load(ordering: .acquiring) == gen else { return }
                self._isRecording.store(false, ordering: .releasing)
                self.host.teardown(generation: gen)
                self.logBluetooth.error("Failed to restart after format change",
                                        parameters: [
                                            "deviceName": self.currentDeviceName ?? "Unknown",
                                            "deviceID": self.currentDeviceIDForRecording ?? "default",
                                            "error": "\(error)"
                                        ],
                                        errorCode: "formatChangeRestartFailed")
                self.onDeviceError?(self.currentDeviceName, .formatChanged)
            }
        }
    }

    // MARK: - File Writing (T032)

    private func startFileWritingIfNeeded(deviceName: String, format tapFormat: AVAudioFormat) {
        guard let settings = audioSaveSettings, settings.enabled else { return }
        guard let bookmarkData = settings.folderBookmark else {
            logAudio.info("Audio save enabled but no folder bookmark")
            return
        }

        var isStale = false
        guard let folderURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            logAudio.error("Failed to resolve audio save folder bookmark", errorCode: "bookmarkResolveFailed")
            return
        }

        guard folderURL.startAccessingSecurityScopedResource() else {
            logAudio.error("Failed to access security-scoped folder", errorCode: "securityScopeAccessFailed")
            return
        }
        isSecurityScopedAccessActive = true
        securityScopedURL = folderURL

        do {
            _ = try audioFileWriter.startWriting(
                deviceName: deviceName,
                sampleRate: tapFormat.sampleRate,
                format: tapFormat,
                folder: folderURL
            )
        } catch {
            logAudio.error("Failed to start file writing: \(error.localizedDescription)",
                          errorCode: "fileWriteStartFailed")
            stopFileWriting()
        }
    }

    private func stopFileWriting() {
        audioFileWriter.stopWriting()
        if isSecurityScopedAccessActive {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            isSecurityScopedAccessActive = false
            securityScopedURL = nil
        }
    }

    private func triggerAutoStop() {
        _isRecording.store(false, ordering: .releasing)
        onAutoStop?()
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        CoreAudioQuery.name(deviceID)
    }

    // MARK: - WAV Conversion

    private func convertToWAV(buffers: [AVAudioPCMBuffer]) throws -> Data {
        let hardwareFormat = buffers[0].format
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw RecordingError.transcriptionFailed("Failed to create target audio format")
        }

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            throw RecordingError.transcriptionFailed("Failed to create audio converter")
        }

        var allSamples = Data()

        for buffer in buffers {
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * targetSampleRate / hardwareFormat.sampleRate
            )
            guard frameCount > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount)
            else { continue }

            var error: NSError?
            var isDone = false
            nonisolated(unsafe) let inputBuffer = buffer
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if isDone {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                isDone = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            if let error {
                throw RecordingError.transcriptionFailed("Audio conversion error: \(error.localizedDescription)")
            }

            if let int16Data = convertedBuffer.int16ChannelData {
                let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
                allSamples.append(Data(bytes: int16Data[0], count: byteCount))
            }

            converter.reset()
        }

        guard !allSamples.isEmpty else {
            throw RecordingError.silenceDetected
        }

        if allSamples.count + 44 > Self.maxFileSize {
            throw RecordingError.fileSizeLimitReached
        }

        return makeWAVHeader(dataSize: allSamples.count, sampleRate: Int(targetSampleRate)) + allSamples
    }

    private func makeWAVHeader(dataSize: Int, sampleRate: Int) -> Data {
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate * Int(channels) * Int(bitsPerSample / 8))
        let blockAlign = Int16(channels * bitsPerSample / 8)
        let chunkSize = Int32(36 + dataSize)
        let subchunk2Size = Int32(dataSize)

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(withUnsafeBytes(of: chunkSize.littleEndian) { Data($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(withUnsafeBytes(of: Int32(16).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: Int16(1).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: Int32(sampleRate).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        header.append(contentsOf: "data".utf8)
        header.append(withUnsafeBytes(of: subchunk2Size.littleEndian) { Data($0) })
        return header
    }
}
