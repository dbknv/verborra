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

// MARK: - AudioCaptureServiceProtocol

@MainActor
protocol AudioCaptureServiceProtocol: AnyObject {
    var audioLevel: Float { get }
    var currentDuration: TimeInterval { get }
    var onAutoStop: (@Sendable @MainActor () -> Void)? { get set }
    var onDeviceError: (@Sendable @MainActor (_ deviceName: String?, _ reason: DeviceErrorReason) -> Void)? { get set }
    var onDeviceFallback: (@Sendable @MainActor (_ fallbackDeviceName: String) -> Void)? { get set }
    var audioSaveSettings: (enabled: Bool, folderBookmark: Data?)? { get set }
    func startRecording(deviceID: String?, maxDuration: MaxRecordingDuration, awaitBluetoothSwitch: Bool) async throws
    func stopRecording() async throws -> Data
    func resetRecording()
    func updateLevelsFromAtomic()
    func availableInputDevices() -> [(id: String, name: String)]
}

extension AudioCaptureServiceProtocol {
    func startRecording(deviceID: String?, maxDuration: MaxRecordingDuration) async throws {
        try await startRecording(deviceID: deviceID, maxDuration: maxDuration, awaitBluetoothSwitch: false)
    }
}

// MARK: - AudioCaptureService

@MainActor
@Observable
final class AudioCaptureService: AudioCaptureServiceProtocol {
    private var engine: AVAudioEngine?
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
    var onDeviceFallback: (@Sendable @MainActor (_ fallbackDeviceName: String) -> Void)?

    /// Settings for file writing — set before startRecording.
    var audioSaveSettings: (enabled: Bool, folderBookmark: Data?)? {
        didSet {
            // If disabled while writing, stop
            if audioSaveSettings?.enabled == false && audioFileWriter.isWriting {
                stopFileWriting()
            }
        }
    }

    // MARK: - Recording Operations (T010, T011, T012)

    func startRecording(deviceID: String?, maxDuration: MaxRecordingDuration, awaitBluetoothSwitch: Bool = false) async throws {
        // FR-010: Ignore duplicate calls
        guard !_isRecording.load(ordering: .acquiring) else {
            logAudio.info("Duplicate startRecording ignored")
            return
        }

        let deviceName: String
        if let deviceID, let id = AudioDeviceID(deviceID) {
            deviceName = Self.deviceName(for: id) ?? deviceID
        } else {
            deviceName = "System Default"
        }
        currentDeviceName = deviceName
        logAudio.info("startRecording", metadata: [
            "deviceName": deviceName,
            "deviceID": deviceID ?? "default",
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

        // Clean state
        if let existingEngine = engine {
            existingEngine.inputNode.removeTap(onBus: 0)
            existingEngine.stop()
        }
        engine = AVAudioEngine()

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

        currentDeviceIDForRecording = deviceID

        // BT A2DP→HFP: start engine to trigger switch, wait for stabilization, restart
        if awaitBluetoothSwitch {
            let resolvedID = try startEngineForBTSwitch(deviceID: deviceID)
            let initialRate = Self.deviceNominalSampleRate(for: resolvedID) ?? 48000

            logBluetooth.info("bt_switch_engine_started", metadata: [
                "deviceName": deviceName,
                "deviceID": "\(resolvedID)",
                "initialRate": "\(initialRate)"
            ])

            let finalRate = try await awaitBluetoothStabilization(
                deviceID: resolvedID,
                initialRate: initialRate
            )

            logBluetooth.info("bt_switch_stabilized", metadata: [
                "deviceName": deviceName,
                "deviceID": "\(resolvedID)",
                "finalRate": "\(finalRate)"
            ])

            // Stop trigger engine, create fresh one for actual recording
            if let triggerEngine = engine {
                triggerEngine.stop()
            }
            engine = AVAudioEngine()
        }

        try prepareAndStartEngine(deviceID: deviceID)

        // Start file writing if enabled (T032)
        startFileWritingIfNeeded(deviceName: deviceName)

        // FR-010: Mark as recording after engine started
        _isRecording.store(true, ordering: .releasing)

        // FR-009: Wait for Bluetooth device to start delivering data (T015)
        for _ in 0..<50 {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if !ringBuffer.isEmpty { break }
        }
        if ringBuffer.isEmpty && _isRecording.load(ordering: .acquiring) {
            // Check if engine is still running - device may have failed silently
            if engine?.isRunning == false {
                _isRecording.store(false, ordering: .releasing)
                logAudio.error("Device not responding after 5s timeout",
                              parameters: ["deviceName": currentDeviceName ?? "Unknown", "deviceID": currentDeviceIDForRecording ?? "default"],
                              errorCode: "deviceNotResponding")
                throw RecordingError.deviceNotResponding
            }
        }
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

        guard let currentEngine = engine else {
            throw RecordingError.notRecording
        }

        removeDeviceFormatListener()
        stopFileWriting()
        currentEngine.inputNode.removeTap(onBus: 0)
        currentEngine.stop()
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
        if let currentEngine = engine {
            currentEngine.inputNode.removeTap(onBus: 0)
            currentEngine.stop()
        }
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
        if engine?.isRunning == false {
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

    /// Start engine without tap to trigger A2DP→HFP switch. Returns resolved AudioDeviceID.
    private func startEngineForBTSwitch(deviceID: String?) throws -> AudioDeviceID {
        guard let currentEngine = engine else { throw RecordingError.microphoneNotAvailable }

        var resolvedDeviceID: AudioDeviceID

        if let deviceID, let device = selectDevice(id: deviceID) {
            setInputDevice(device, on: currentEngine)
            resolvedDeviceID = device
        } else {
            resolvedDeviceID = currentEngine.inputNode.auAudioUnit.deviceID
        }

        currentEngine.prepare()
        try currentEngine.start()
        return resolvedDeviceID
    }

    /// Wait for BT sample rate to stabilize after engine start (300ms debounce, 5s timeout).
    /// Works for both A2DP→HFP switch and already-HFP with potential rate transients.
    private func awaitBluetoothStabilization(deviceID: AudioDeviceID, initialRate: Double) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
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

            // 5s overall timeout (FR-014)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeout)
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

    // MARK: - Private: Engine Setup

    private func prepareAndStartEngine(deviceID: String?) throws {
        guard let currentEngine = engine else { return }
        logEngine.info("Preparing audio engine", metadata: [
            "deviceName": currentDeviceName ?? "Unknown",
            "deviceID": deviceID ?? "default"
        ])

        var resolvedDeviceID: AudioDeviceID?

        if let deviceID, let device = selectDevice(id: deviceID) {
            setInputDevice(device, on: currentEngine)
            resolvedDeviceID = device
            let deviceName = Self.deviceName(for: device) ?? "Unknown"
            logAudio.info("Device selected", metadata: [
                "deviceName": deviceName,
                "deviceID": deviceID
            ])
        } else {
            resolvedDeviceID = currentEngine.inputNode.auAudioUnit.deviceID
            let defaultName = Self.deviceName(for: resolvedDeviceID!) ?? "System Default"
            logAudio.info("Using default device", metadata: [
                "deviceName": defaultName,
                "deviceID": "\(resolvedDeviceID!)"
            ])
        }

        let inputNode = currentEngine.inputNode

        // Query actual hardware sample rate from CoreAudio (not from inputNode which may lag)
        let actualSampleRate: Double
        if let devID = resolvedDeviceID, let hwRate = Self.deviceNominalSampleRate(for: devID) {
            actualSampleRate = hwRate
        } else {
            actualSampleRate = inputNode.outputFormat(forBus: 0).sampleRate
        }

        logEngine.debug("Engine hardware format", metadata: [
            "deviceName": currentDeviceName ?? "System Default",
            "deviceID": currentDeviceIDForRecording ?? "default",
            "actualHWSampleRate": "\(actualSampleRate)",
            "nodeOutputSampleRate": "\(inputNode.outputFormat(forBus: 0).sampleRate)",
            "channels": "\(inputNode.outputFormat(forBus: 0).channelCount)"
        ])

        guard actualSampleRate > 0, inputNode.outputFormat(forBus: 0).channelCount > 0 else {
            logEngine.error("Invalid hardware format", parameters: [
                "deviceName": currentDeviceName ?? "Unknown",
                "deviceID": currentDeviceIDForRecording ?? "default",
                "sampleRate": "\(actualSampleRate)",
                "channels": "\(inputNode.outputFormat(forBus: 0).channelCount)"
            ], errorCode: "microphoneNotAvailable")
            throw RecordingError.microphoneNotAvailable
        }

        // Create tap format matching actual hardware sample rate
        let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: actualSampleRate,
            channels: 1,
            interleaved: false
        )

        installRecordingTap(on: inputNode, format: tapFormat)

        let resolvedName = resolvedDeviceID.flatMap { Self.deviceName(for: $0) } ?? "Unknown"

        currentEngine.prepare()
        do {
            try currentEngine.start()
            // FR-012: Log device ID, name, and sample rate at recording start
            logAudio.info("Recording on device", metadata: [
                "deviceName": resolvedName,
                "deviceID": currentDeviceIDForRecording ?? "default",
                "sampleRate": "\(actualSampleRate)"
            ])
            // Install format change listener on the active device
            lastKnownSampleRate = actualSampleRate
            if let devID = resolvedDeviceID {
                installDeviceFormatListener(deviceID: devID)
            }
        } catch {
            logEngine.error("Engine start failed, retrying with default device",
                           parameters: [
                               "deviceName": currentDeviceName ?? "Unknown",
                               "deviceID": deviceID ?? "default"
                           ],
                           errorCode: "\(error)")

            inputNode.removeTap(onBus: 0)
            currentEngine.stop()
            engine = AVAudioEngine()

            guard let retryEngine = engine else { return }
            let retryNode = retryEngine.inputNode
            let defaultDeviceID = retryNode.auAudioUnit.deviceID
            let defaultName = Self.deviceName(for: defaultDeviceID) ?? "System Default"

            let retrySampleRate: Double
            if let hwRate = Self.deviceNominalSampleRate(for: defaultDeviceID) {
                retrySampleRate = hwRate
            } else {
                retrySampleRate = retryNode.outputFormat(forBus: 0).sampleRate
            }

            guard retrySampleRate > 0, retryNode.outputFormat(forBus: 0).channelCount > 0 else {
                logEngine.error("Retry with default device failed",
                               parameters: ["deviceName": defaultName, "deviceID": "\(defaultDeviceID)"],
                               errorCode: "microphoneNotAvailable")
                throw RecordingError.microphoneNotAvailable
            }

            logEngine.debug("Retry engine format", metadata: [
                "deviceName": defaultName,
                "deviceID": "\(defaultDeviceID)",
                "sampleRate": "\(retrySampleRate)",
                "channels": "\(retryNode.outputFormat(forBus: 0).channelCount)"
            ])

            let retryTapFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: retrySampleRate,
                channels: 1,
                interleaved: false
            )
            installRecordingTap(on: retryNode, format: retryTapFormat)
            retryEngine.prepare()
            try retryEngine.start()
            // Update internal state to reflect actual device
            currentDeviceName = defaultName
            currentDeviceIDForRecording = nil // nil = system default

            logAudio.info("Recording on device (fallback to default)", metadata: [
                "deviceName": defaultName,
                "originalDevice": resolvedName,
                "sampleRate": "\(retrySampleRate)"
            ])
            lastKnownSampleRate = retrySampleRate
            installDeviceFormatListener(deviceID: defaultDeviceID)

            // Notify UI about fallback
            onDeviceFallback?(defaultName)
        }
    }

    /// T009: Install tap with explicit format matching hardware
    private func installRecordingTap(on inputNode: AVAudioInputNode, format: AVAudioFormat?) {
        let tapFormat = format ?? inputNode.outputFormat(forBus: 0)
        logTap.info("Installing recording tap", metadata: [
            "deviceName": currentDeviceName ?? "System Default",
            "deviceID": currentDeviceIDForRecording ?? "default",
            "bufferSize": "4096",
            "sampleRate": "\(tapFormat.sampleRate)",
            "channels": "\(tapFormat.channelCount)"
        ])

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            self?.handleAudioBuffer(buffer, time: time)
        }
    }

    // MARK: - Device Format Change Monitoring

    /// Query the device's actual nominal sample rate via CoreAudio
    private static func deviceNominalSampleRate(for deviceID: AudioDeviceID) -> Double? {
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

        // Stop current engine and file writing
        removeDeviceFormatListener()
        stopFileWriting()
        if let currentEngine = engine {
            currentEngine.inputNode.removeTap(onBus: 0)
            currentEngine.stop()
        }

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

        // Restart with fresh engine
        engine = AVAudioEngine()
        do {
            try prepareAndStartEngine(deviceID: currentDeviceIDForRecording)
            // Restart file writing with new format (FR-024)
            startFileWritingIfNeeded(deviceName: currentDeviceName ?? "System Default")
            logBluetooth.info("Recording restarted after format change", metadata: [
                "deviceName": currentDeviceName ?? "Unknown",
                "deviceID": currentDeviceIDForRecording ?? "default"
            ])
        } catch {
            _isRecording.store(false, ordering: .releasing)
            logBluetooth.error("Failed to restart after format change",
                              parameters: [
                                  "deviceName": currentDeviceName ?? "Unknown",
                                  "deviceID": currentDeviceIDForRecording ?? "default",
                                  "error": "\(error)"
                              ],
                              errorCode: "formatChangeRestartFailed")
            onDeviceError?(currentDeviceName, .formatChanged)
        }
    }

    // MARK: - File Writing (T032)

    private func startFileWritingIfNeeded(deviceName: String) {
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

        guard let engine = engine else { return }
        let inputNode = engine.inputNode
        let tapFormat = inputNode.outputFormat(forBus: 0)

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
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // T016/R-004: Use Unmanaged<CFString>? for safe CoreAudio interaction
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name) == noErr,
              let cfString = name?.takeRetainedValue() else {
            return nil
        }
        return cfString as String
    }

    private func selectDevice(id: String) -> AudioDeviceID? {
        guard let deviceID = AudioDeviceID(id) else { return nil }
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
        return deviceID
    }

    private func setInputDevice(_ deviceID: AudioDeviceID, on targetEngine: AVAudioEngine) {
        var deviceID = deviceID
        let audioUnit = targetEngine.inputNode.audioUnit!
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
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
