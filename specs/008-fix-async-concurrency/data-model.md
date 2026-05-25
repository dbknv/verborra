# Data Model: Concurrency primitives

**Branch**: `008-fix-async-concurrency`
**Date**: 2026-03-18

## Overview

This feature does not add new data entities (models, tables, stores). All changes concern concurrency primitives — mechanisms for synchronization and data transfer between threads.

## Concurrency primitives

### SPSCRingBuffer\<T\>

**File**: `Verborra/Services/SPSCRingBuffer.swift` (NEW)

Lock-free circular buffer for transferring data from a single producer (audio thread) to a single consumer (main thread).

| Property | Type | Description |
|----------|------|-------------|
| `buffer` | `UnsafeMutableBufferPointer<T?>` | Fixed-size slot array |
| `capacity` | `Int` | Buffer size (256) |
| `writeIndex` | `ManagedAtomic<Int>` | Write index (producer) |
| `readIndex` | `ManagedAtomic<Int>` | Read index (consumer) |

**Invariants**:
- Single producer (audio thread), single consumer (main thread)
- `writeIndex` is modified only by the producer
- `readIndex` is modified only by the consumer
- Buffer full: `(writeIndex + 1) % capacity == readIndex`
- Buffer empty: `writeIndex == readIndex`

**Operations**:

| Method | Thread | Description |
|--------|--------|-------------|
| `write(_ value: T) -> Bool` | Audio thread | Write an element, false if the buffer is full |
| `read() -> T?` | Main thread | Read one element, nil if the buffer is empty |
| `readAll() -> [T]` | Main thread | Read all available elements |
| `reset()` | Main thread | Reset indices (on resetRecording) |

### Accumulating array in AudioCaptureService

| Property | Type | Thread | Description |
|----------|------|--------|-------------|
| `accumulatedBuffers` | `[AVAudioPCMBuffer]` | Main thread | Buffers drained from the ring buffer via `updateLevelsFromAtomic()` every 50-100ms. At stopRecording it is combined with the ring buffer remainder: `accumulatedBuffers + ringBuffer.readAll()`. Cleared on start/reset |

**Invariant**: Ring buffer periodically drained → accumulatedBuffers grows on main thread → stopRecording reads all.

### Atomic properties of AudioCaptureService

| Property | Type | Writer | Reader | Description |
|----------|------|--------|--------|-------------|
| `_atomicAudioLevel` | `ManagedAtomic<UInt32>` | Audio thread | Main thread | Float audioLevel via bitcast |
| `_atomicDuration` | `ManagedAtomic<UInt64>` | Audio thread | Main thread | TimeInterval via bitcast |
| `_isRecording` | `ManagedAtomic<Bool>` | Main thread | Audio thread | Active recording flag |
| `_consecutiveZeroBuffers` | `ManagedAtomic<Int>` | Audio thread | Main thread | Zero-buffer counter |
| `_droppedBuffers` | `ManagedAtomic<Int>` | Audio thread | Main thread | Counter of buffers lost on ring buffer overflow (diagnostics) |

### Memory ordering

| Operation | Ordering | Rationale |
|-----------|----------|-----------|
| audioLevel store/load | `.relaxed` | Single value, stale read acceptable (50ms) |
| duration store/load | `.relaxed` | Same as audioLevel |
| isRecording store | `.releasing` | Publishes recording state for the audio thread |
| isRecording load | `.acquiring` | Sees actual state before processing a buffer |
| ringBuffer write/read | `.releasing`/`.acquiring` | Ensures visibility of buffer data between threads |
| zeroBuffers store/load | `.relaxed` | Approximate value, does not protect other data |

### DeviceErrorReason

**File**: `Verborra/Models/` or `Verborra/Services/AudioCaptureService.swift`

Reason for an audio device error to distinguish FR-012 (disconnect) from FR-014 (format change).

| Case | Description | User-facing message |
|------|-------------|---------------------|
| `disconnected` | Device disconnected (missing from list) | "Device lost" |
| `formatChanged` | Audio format changed (device present, engine stopped) | "Audio device changed format" |

## Changes to existing models

### AudioCaptureServiceProtocol

**File**: `Verborra/Services/AudioCaptureService.swift` (lines 7-15)

**Before**:
```swift
protocol AudioCaptureServiceProtocol: AnyObject {
    var audioLevel: Float { get }
    var currentDuration: TimeInterval { get }
    var onAutoStop: (() -> Void)? { get set }
    var onDeviceError: ((_ deviceName: String?) -> Void)? { get set }
    func startRecording(deviceUID: String?, maxDuration: MaxRecordingDuration) async throws
    func stopRecording() async throws -> Data
    func resetRecording()
}
```

**After**:
```swift
@MainActor
protocol AudioCaptureServiceProtocol: AnyObject {
    var audioLevel: Float { get }
    var currentDuration: TimeInterval { get }
    var onAutoStop: (@Sendable @MainActor () -> Void)? { get set }
    var onDeviceError: (@Sendable @MainActor (_ deviceName: String?, _ reason: DeviceErrorReason) -> Void)? { get set }
    func startRecording(deviceUID: String?, maxDuration: MaxRecordingDuration) async throws
    func stopRecording() async throws -> Data
    func resetRecording()
}
```

### AudioDeviceManagerProtocol

**File**: `Verborra/Services/Protocols.swift` (lines 6-20)

**Before**:
```swift
protocol AudioDeviceManagerProtocol: AnyObject {
    var devices: [AudioDevice] { get }
    var defaultInputDeviceUID: String? { get }
    var onDeviceLost: ((_ uid: String, _ name: String) -> Void)? { get set }
    var onDefaultInputChanged: ((_ newUID: String?) -> Void)? { get set }
    ...
}
```

**After**:
```swift
@MainActor
protocol AudioDeviceManagerProtocol: AnyObject {
    var devices: [AudioDevice] { get }
    var defaultInputDeviceUID: String? { get }
    var onDeviceLost: (@Sendable @MainActor (_ uid: String, _ name: String) -> Void)? { get set }
    var onDefaultInputChanged: (@Sendable @MainActor (_ newUID: String?) -> Void)? { get set }
    ...
}
```

## Data flow diagram

```
Audio Thread (real-time)          Main Thread (@MainActor)
─────────────────────            ──────────────────────────

installTap callback               Timer (50ms) → updateLevelsFromAtomic()
  │                                │
  ├─ RMS calculation               ├─ atomicAudioLevel.load()
  │   └─ atomicAudioLevel.store()  │   └─ audioLevel = Float(bitPattern:)
  │                                │
  ├─ ringBuffer.write(buffer)      ├─ ringBuffer.readAll() → drain
  │                                │   └─ accumulatedBuffers.append(contentsOf:)
  ├─ atomicDuration.store()        │
  │                                ├─ [on stopRecording]
  ├─ zero buffer check             │   └─ accumulatedBuffers + ringBuffer.readAll()
  │   └─ zeroBuffers.store()       │       └─ convertToWAV()
  │                                │
  └─ isRecording.load()            ├─ zeroBuffers.load()
      └─ if false → return early   │   └─ if > 10s → autoStop
                                   │
                                   └─ isRecording.store()
                                       └─ on start/stop
```
