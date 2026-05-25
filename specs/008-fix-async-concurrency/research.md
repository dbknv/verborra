# Research: Swift Concurrency and race condition fixes

**Branch**: `008-fix-async-concurrency`
**Date**: 2026-03-18

## R-001: Actor vs @MainActor for AudioCaptureService

### Decision

Use `@MainActor @Observable final class` instead of Swift Actor for AudioCaptureService.

### Rationale

The specification FR-001 proposed isolating AudioCaptureService into an actor. However, research revealed a fundamental conflict:

1. **`@Observable` is incompatible with custom actor** — SwiftUI reads properties synchronously inside `View.body`, while a custom actor requires `await` for every access
2. **The `AudioCaptureServiceProtocol`** defines synchronous properties (`audioLevel: Float { get }`) that are incompatible with actor isolation
3. **`installTap` callback** runs on the real-time audio thread and cannot perform an actor hop (suspend)

### Alternatives

| Variant | Verdict | Reason for rejection |
|---------|---------|----------------------|
| `@MainActor @Observable final class` | ✅ Selected | Compatible with SwiftUI, @Observable, protocols |
| Swift Actor | ❌ | Conflicts with @Observable and synchronous SwiftUI API |
| Serial DispatchQueue | ❌ | Complicates integration, duplicates MainActor |

### Architectural diagram

```
                    installTap callback (real-time thread)
                         │
                    [nonisolated func]
                         │
              ┌──────────┴──────────┐
              │                     │
    Atomic<UInt32>            SPSC Ring Buffer
    (audioLevel)              (AVAudioPCMBuffer)
              │                     │
              └──────────┬──────────┘
                         │
                    Timer (50ms, main thread)
                         │
                    @MainActor @Observable
                    AudioCaptureService
                         │
                    SwiftUI View (reads audioLevel)
```

### Impact on the specification

FR-001 needs to be adjusted: instead of "isolate AudioCaptureService into an actor" → "isolate AudioCaptureService via @MainActor, use lock-free mechanisms for the audio thread". The serialization semantics are preserved (all mutations on the main thread), but without custom actor restrictions.

### Sources

- [Hacking with Swift: Do not use an actor for SwiftUI data models](https://www.hackingwithswift.com/quick-start/concurrency/important-do-not-use-an-actor-for-your-swiftui-data-models)
- [Apple Developer Forums: Observation and MainActor](https://developer.apple.com/forums/thread/731822)
- [Swift Forums: @Observable macro conflicting with @MainActor](https://forums.swift.org/t/observable-macro-conflicting-with-mainactor/67309)

---

## R-002: Lock-free ring buffer for audio tap callback

### Decision

Implement an SPSC (Single-Producer, Single-Consumer) ring buffer based on `swift-atomics` to pass `AVAudioPCMBuffer` from the audio callback to the main thread.

### Rationale

The current code uses `NSLock` to protect `audioBuffers: [AVAudioPCMBuffer]` (line 26, AudioCaptureService.swift). This violates two rules of the real-time audio thread:

1. **Locks are forbidden** — NSLock can block the audio thread, leading to dropped audio frames
2. **Memory allocation is forbidden** — `Array.append()` can trigger a reallocation

### Alternatives

| Variant | Verdict | Reason for rejection |
|---------|---------|----------------------|
| SPSC Ring Buffer + swift-atomics | ✅ Selected | Lock-free, allocation-free, standard audio practice |
| `os_unfair_lock` | ❌ | Still a lock, forbidden on the real-time thread |
| `OSAllocatedUnfairLock` | ❌ | Lock, although safer in Swift |
| Accumulate into `Data` inside the callback | ❌ | Memory allocation on the real-time thread |

### Technical implementation

```swift
import Atomics

final class SPSCRingBuffer<T> {
    private let buffer: UnsafeMutableBufferPointer<T?>
    private let capacity: Int
    private let writeIndex = ManagedAtomic<Int>(0)
    private let readIndex = ManagedAtomic<Int>(0)

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = .allocate(capacity: capacity)
        self.buffer.initialize(repeating: nil)
    }

    /// Called from the audio thread (producer)
    func write(_ value: T) -> Bool {
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        let next = (write + 1) % capacity
        guard next != read else { return false } // Buffer full
        buffer[write] = value
        writeIndex.store(next, ordering: .releasing)
        return true
    }

    /// Called from the main thread (consumer)
    func read() -> T? {
        let read = readIndex.load(ordering: .relaxed)
        let write = writeIndex.load(ordering: .acquiring)
        guard read != write else { return nil } // Buffer empty
        let value = buffer[read]
        buffer[read] = nil
        readIndex.store((read + 1) % capacity, ordering: .releasing)
        return value
    }

    /// Read all available elements
    func readAll() -> [T] {
        var results: [T] = []
        while let value = read() {
            results.append(value)
        }
        return results
    }
}
```

**Buffer size**: 256 slots. With bufferSize=4096 and sampleRate=16kHz one buffer ≈ 256ms. 256 slots = ~65 seconds of buffering, which exceeds the maximum recording duration (5 minutes at the correct drain rate).

### Dependency

Add `apple/swift-atomics` to Package.swift:

```swift
.package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0")
```

---

## R-003: Atomic Float for audioLevel

### Decision

Use `ManagedAtomic<UInt32>` with a Float ↔ UInt32 bitcast for lock-free transfer of audioLevel from the audio thread.

### Rationale

The current code (lines 209-212, AudioCaptureService.swift) uses `DispatchQueue.main.async` to update audioLevel from the audio tap callback. This:
1. Creates a race condition (audio thread writes, main thread reads)
2. `DispatchQueue.main.async` — a closure allocation on the real-time thread

### Technical implementation

```swift
private let _atomicAudioLevel = ManagedAtomic<UInt32>(0)

// In the audio tap callback (nonisolated, real-time thread):
let level = min(rms * 5, 1.0)
_atomicAudioLevel.store(level.bitPattern, ordering: .relaxed)

// In the Timer callback (main thread):
let bits = _atomicAudioLevel.load(ordering: .relaxed)
audioLevel = Float(bitPattern: bits)
```

**Ordering `.relaxed`** is sufficient: audioLevel is a single value that does not protect other data. A stale read by one frame (50ms) is visually imperceptible.

---

## R-004: Eliminating CFString UnsafeMutableRawPointer

### Decision

Replace the direct `&uid` (inout CFString) with `withUnsafeMutablePointer` + `Unmanaged<CFString>` for safe passing into the CoreAudio API.

### Rationale

The current code (lines 308-313, AudioDeviceManager.swift) passes `&uid` where `uid: CFString`. Swift warns: "Forming 'UnsafeMutableRawPointer' to a variable of type 'CFString'" — CFString is a reference type, and `MemoryLayout<CFString>.size` returns the pointer size, not the object size.

### Technical implementation

```swift
private func getDeviceUID(for deviceID: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
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
```

**Key change**: `Unmanaged<CFString>?` instead of `CFString` — CoreAudio returns a retained CFString reference, `takeRetainedValue()` correctly manages memory.

### Alternatives

| Variant | Verdict | Reason for rejection |
|---------|---------|----------------------|
| `Unmanaged<CFString>?` + `takeRetainedValue` | ✅ Selected | Correct memory handling, no warnings |
| `withUnsafeMutablePointer` to `CFString` | ❌ | Does not solve the reference type issue |
| `UnsafeMutablePointer.allocate` + memcpy | ❌ | Excessively complex |

---

## R-005: Replacing callback closures with @Sendable / AsyncStream

### Decision

Replace non-Sendable closure callbacks (`onAutoStop`, `onDeviceError`, `onDeviceLost`, `onDefaultInputChanged`) with `@Sendable` closures annotated with `@MainActor`.

### Rationale

The current callbacks (AudioCaptureService lines 36-37, Protocols.swift lines 9-10) are non-Sendable closures, which triggers "Capture of 'self' with non-Sendable type" warnings in ViewModels.

### Alternatives

| Variant | Verdict | Reason for rejection |
|---------|---------|----------------------|
| `@Sendable @MainActor` closures | ✅ Selected | Minimal API changes, explicit thread safety |
| AsyncStream | ❌ | Requires significant rework of consumer code |
| Delegate pattern via protocol | ❌ | Complicates DI and testing |
| Combine Publisher | ❌ | Adds a Combine dependency, excessive |

### Technical implementation

```swift
// Protocol:
protocol AudioCaptureServiceProtocol: AnyObject {
    var audioLevel: Float { get }
    var currentDuration: TimeInterval { get }
    var onAutoStop: (@Sendable @MainActor () -> Void)? { get set }
    var onDeviceError: (@Sendable @MainActor (_ deviceName: String?) -> Void)? { get set }
    func startRecording(deviceUID: String?, maxDuration: MaxRecordingDuration) async throws
    func stopRecording() async throws -> Data
    func resetRecording()
}

// Call from the audio tap:
DispatchQueue.main.async { [weak self] in
    self?.onDeviceError?(deviceName)  // Guaranteed main thread
}
```

Similarly for `AudioDeviceManagerProtocol`:
```swift
var onDeviceLost: (@Sendable @MainActor (_ uid: String, _ name: String) -> Void)? { get set }
var onDefaultInputChanged: (@Sendable @MainActor (_ newUID: String?) -> Void)? { get set }
```

---

## R-006: Eliminating redundant Task { @MainActor in } in Timer callbacks

### Decision

Remove `Task { @MainActor in }` wrappers from Timer callbacks that already run on the main thread.

### Rationale

Timer.scheduledTimer callbacks (RecordingViewModel lines 818-835, OnboardingViewModel lines 135-140) are already invoked on the main thread (main RunLoop). Wrapping them in `Task { @MainActor in }` creates:

1. **Redundant context switch**: main → async → main
2. **Unpredictable execution order**: the Task may run in the next run loop cycle
3. **Potential stale state**: between Task creation and execution, state can change

### Technical implementation

**Before**:
```swift
durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
    guard let self, let start = self.recordingStart else { return }
    Task { @MainActor in
        let duration = Date().timeIntervalSince(start)
        self.state = .recording(duration: duration, remaining: remaining)
    }
}
```

**After**:
```swift
durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
    guard let self, let start = self.recordingStart else { return }
    let duration = Date().timeIntervalSince(start)
    let remaining = max(0, maxSeconds - duration)
    self.state = .recording(duration: duration, remaining: remaining)
    if remaining <= 0 {
        self.stopRecording()
    }
}
```

Similarly for levelTimer, inputDurationTimer, inputLevelTimer.

For OnboardingViewModel — remove `DispatchQueue.main.async` from the Timer callback (triple nesting: Task @MainActor → Timer → DispatchQueue.main.async).

---

## R-007: nonisolated escape hatch for the installTap callback

### Decision

Mark the audio tap handler as a `nonisolated` function to escape `@MainActor` isolation.

### Rationale

After adding `@MainActor` to AudioCaptureService, the `installTap` closure inherits MainActor isolation. But the audio tap callback runs on the real-time audio thread — executing on MainActor would block the audio thread.

### Technical implementation

```swift
@MainActor
@Observable
final class AudioCaptureService: AudioCaptureServiceProtocol {

    /// Audio tap callback — runs on the real-time audio thread
    /// nonisolated so it does not inherit @MainActor isolation
    private nonisolated func handleAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        time: AVAudioTime
    ) {
        // Lock-free operations only:
        // 1. Write to the ring buffer
        // 2. Atomic update of audioLevel
        // 3. Atomic update of duration
        // DO NOT call DispatchQueue.main.async
        // DO NOT access @MainActor-isolated properties
    }
}
```

### Alternative for engine state check

The current code checks `self.engine?.isRunning` inside the tap callback (line 182). With `@MainActor` isolation this is impossible from a `nonisolated` context. Solution: an atomic `_isRecording: ManagedAtomic<Bool>` flag.

```swift
private let _isRecording = ManagedAtomic<Bool>(false)

// In startRecording (@MainActor):
_isRecording.store(true, ordering: .releasing)

// In the nonisolated tap callback:
guard _isRecording.load(ordering: .acquiring) else { return }
```

---

## R-008: Strategy for detecting a "dead" device (zero buffers)

### Decision

An atomic counter of consecutive zero-buffers in the audio tap callback, checked by a Timer on the main thread.

### Rationale

FR-013 requires: if all samples == 0 for 10 seconds — auto-stop the recording. Counting must happen in the audio callback (real-time thread), while the decision to stop must happen on the main thread.

### Technical implementation

```swift
private let _consecutiveZeroBuffers = ManagedAtomic<Int>(0)

// In the nonisolated tap callback:
let isZero = channelData.allSatisfy { abs($0) < Float.ulpOfOne }
if isZero {
    _consecutiveZeroBuffers.wrappingIncrementThenLoad(ordering: .relaxed)
} else {
    _consecutiveZeroBuffers.store(0, ordering: .relaxed)
}

// In the Timer callback (main thread):
let zeroCount = _consecutiveZeroBuffers.load(ordering: .relaxed)
let silenceDuration = Double(zeroCount) * bufferDuration
if silenceDuration >= 10.0 {
    triggerAutoStop(reason: .silentDevice)
}
```

---

## R-009: @MainActor isolation for ViewModels

### Decision

Add `@MainActor` annotation to RecordingViewModel and OnboardingViewModel.

### Rationale

Both ViewModels are `@Observable final class` and update UI properties. Without an explicit `@MainActor` annotation, the compiler cannot guarantee that all property mutations happen on the main thread, which leads to non-Sendable capture warnings.

### Impact

- All properties and methods are automatically isolated to MainActor
- Callbacks with `@Sendable @MainActor` annotation become safe
- Timer callbacks from a MainActor-isolated class automatically get the correct isolation
- `nonisolated` methods are used only where MainActor isolation is not required

---

## R-010: Timer lifecycle management

### Decision

Invalidate all timers when the window closes via `deinit` and a `cleanup()` method.

### Rationale

FR-020 requires: when the floating recording window closes, all timers must be invalidated, and recording must be stopped. The current code (RecordingViewModel) calls `stopTimers()` in several places but does not guarantee a call upon ViewModel deallocation.

### Technical implementation

```swift
@MainActor
@Observable
final class RecordingViewModel {
    deinit {
        // Timer invalidation must happen on main thread
        // deinit of @MainActor class is guaranteed on main thread in Swift 5.10+
        durationTimer?.invalidate()
        levelTimer?.invalidate()
        inputDurationTimer?.invalidate()
        inputLevelTimer?.invalidate()
    }
}
```

**Important**: In Swift 5.9 the `deinit` of an actor-isolated class can be invoked on an arbitrary thread. In Swift 5.10+ the `deinit` of a `@MainActor` class is guaranteed to run on the main thread. For Swift 5.9 it is safer to use an explicit `cleanup()` method called before window closing.

---

## Summary table of decisions

| ID | Topic | Decision | Dependency |
|----|-------|----------|------------|
| R-001 | Actor vs @MainActor | @MainActor @Observable class | — |
| R-002 | Audio buffers | SPSC Ring Buffer | swift-atomics |
| R-003 | audioLevel | Atomic UInt32 + bitcast | swift-atomics |
| R-004 | CFString safety | Unmanaged<CFString>? | — |
| R-005 | Callbacks | @Sendable @MainActor closures | — |
| R-006 | Timer wrapping | Remove Task/DispatchQueue from Timer | — |
| R-007 | nonisolated tap | nonisolated func + atomic flags | swift-atomics |
| R-008 | Silent device | Atomic counter + Timer check | swift-atomics |
| R-009 | ViewModel isolation | @MainActor on ViewModel | — |
| R-010 | Timer lifecycle | deinit + cleanup() | — |
