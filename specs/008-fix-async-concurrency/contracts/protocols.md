# Protocol Contracts: Concurrency-Safe Interfaces

**Branch**: `008-fix-async-concurrency`
**Date**: 2026-03-18

> **Note**: Below is the **final** version of the protocols. During incremental implementation (tasks.md), the `updateLevelsFromAtomic()` method is added to the protocol at step T013, not T004.

## DeviceErrorReason

```swift
/// Audio device error reason.
/// Used in onDeviceError callback to distinguish FR-012 (disconnect) from FR-014 (format change).
enum DeviceErrorReason: Sendable {
    /// Device disconnected (FR-012). Message: "Device lost"
    case disconnected
    /// Device changed audio format, e.g. Bluetooth profile switch A2DP -> HFP (FR-014).
    /// Message: "Audio device changed format"
    case formatChanged
}
```

## AudioCaptureServiceProtocol

```swift
/// Audio capture service protocol.
/// All operations are isolated to @MainActor.
/// Audio tap callback is the only nonisolated path.
/// The implementation accepts `AudioDeviceManagerProtocol` via init (weak)
/// to check device presence during device error detection.
@MainActor
protocol AudioCaptureServiceProtocol: AnyObject {
    /// Current audio level (0.0–1.0). Updated from atomic every 50ms.
    var audioLevel: Float { get }

    /// Current recording duration. Updated from atomic every 100ms.
    var currentDuration: TimeInterval { get }

    /// Called on automatic stop of recording
    /// (max duration exceeded, max file size exceeded, silent device).
    /// Guaranteed to be called on MainActor.
    var onAutoStop: (@Sendable @MainActor () -> Void)? { get set }

    /// Called on device error (disconnect, format change).
    /// Guaranteed to be called on MainActor.
    /// reason allows distinguishing FR-012 (disconnected) from FR-014 (formatChanged).
    var onDeviceError: (@Sendable @MainActor (_ deviceName: String?, _ reason: DeviceErrorReason) -> Void)? { get set }

    /// Start recording from the specified device.
    /// - Parameters:
    ///   - deviceUID: device UID or nil for the system default
    ///   - maxDuration: maximum recording duration
    /// - Throws: RecordingError on device access error
    func startRecording(deviceUID: String?, maxDuration: MaxRecordingDuration) async throws

    /// Stop recording and return WAV data.
    /// - Returns: Data with the WAV file
    /// - Throws: RecordingError.notRecording if recording is not active (FR-010)
    func stopRecording() async throws -> Data

    /// Reset recording without saving data.
    func resetRecording()

    /// Update UI properties (audioLevel, currentDuration) from atomic values.
    /// Drain the ring buffer into accumulatedBuffers to prevent data loss (FR-002).
    /// Called from a Timer callback in the ViewModel every 50-100ms.
    /// Also checks silent device detection (FR-013) and device error (engine stopped).
    func updateLevelsFromAtomic()
}
```

## AudioDeviceManagerProtocol

```swift
/// Audio device manager protocol.
/// All operations are isolated to @MainActor.
/// CoreAudio listeners are nonisolated and forward to the main thread.
@MainActor
protocol AudioDeviceManagerProtocol: AnyObject {
    /// List of available input devices.
    var devices: [AudioDevice] { get }

    /// UID of the system default input device.
    var defaultInputDeviceUID: String? { get }

    /// Called when a device is lost (disconnected).
    /// Guaranteed to be called on MainActor.
    var onDeviceLost: (@Sendable @MainActor (_ uid: String, _ name: String) -> Void)? { get set }

    /// Called when the system default input device changes.
    /// Guaranteed to be called on MainActor.
    var onDefaultInputChanged: (@Sendable @MainActor (_ newUID: String?) -> Void)? { get set }

    /// Start monitoring device connect/disconnect events.
    func startMonitoring()

    /// Stop monitoring.
    func stopMonitoring()

    /// Get CoreAudio AudioDeviceID by UID.
    func coreAudioDeviceID(for uid: String) -> AudioDeviceID?

    /// Find a device by UID.
    func device(for uid: String) -> AudioDevice?

    /// Resolve the effective device (selected or system default).
    func resolveEffectiveDevice(selectedUID: String?) -> AudioDevice?

    /// Save the current volume and set it to maximum.
    func saveAndMaximizeVolume(deviceID: AudioDeviceID) -> VolumeState?

    /// Restore the saved volume.
    func restoreVolume(_ state: VolumeState)
}
```

## SPSCRingBuffer API

```swift
/// Lock-free ring buffer for a single producer and a single consumer.
/// Thread-safe without locks — uses atomic operations.
///
/// Producer (audio thread): write()
/// Consumer (main thread): read(), readAll(), reset()
final class SPSCRingBuffer<T>: @unchecked Sendable {
    /// Create a ring buffer with the given capacity.
    /// - Parameter capacity: number of slots (power of 2 recommended)
    init(capacity: Int)

    /// Write an element to the buffer (called only from the producer thread).
    /// - Returns: true if written, false if the buffer is full
    func write(_ value: T) -> Bool

    /// Read one element from the buffer (called only from the consumer thread).
    /// - Returns: the element or nil if the buffer is empty
    func read() -> T?

    /// Read all available elements (called only from the consumer thread).
    /// - Returns: array of elements in write order
    func readAll() -> [T]

    /// Reset indices (called only from the consumer thread when the producer is inactive).
    func reset()

    /// Number of elements in the buffer (approximate, may be stale).
    var count: Int { get }

    /// Buffer is empty (approximate).
    var isEmpty: Bool { get }
}
```

## Thread Safety Contract

### Guarantees

| Component | Isolation | Guarantee |
|-----------|-----------|----------|
| AudioCaptureService | @MainActor | All properties and methods — main thread |
| AudioCaptureService.handleAudioBuffer | nonisolated | Only atomic/lock-free operations |
| AudioDeviceManager | @MainActor | All properties and methods — main thread (same as AudioCaptureService) |
| AudioDeviceManager listeners | nonisolated + listenerQueue (serial) | CoreAudio callbacks serialized, forwarded to the main thread |
| RecordingViewModel | @MainActor | All properties and methods — main thread |
| OnboardingViewModel | @MainActor | All properties and methods — main thread |
| SPSCRingBuffer | @unchecked Sendable | Lock-free, one writer + one reader |

### Forbidden in audio tap callback

- `DispatchQueue.main.async` (closure allocation)
- `NSLock.lock()` / any locks
- Array.append() (potential reallocation)
- Access to @MainActor-isolated properties
- Actor hop (`await`)
- Objective-C message dispatch (where possible)

### Allowed in audio tap callback

- `ManagedAtomic.store/load` (lock-free)
- `SPSCRingBuffer.write()` (lock-free)
- Reading `nonisolated` properties
- Computations (RMS, zero-buffer detection)
