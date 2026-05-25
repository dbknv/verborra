# Implementation Plan: Swift Concurrency, race condition fixes and Bluetooth support

**Branch**: `008-fix-async-concurrency` | **Date**: 2026-03-19 | **Updated**: 2026-03-19 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/008-fix-async-concurrency/spec.md`

## Summary

Fix all Swift Concurrency warnings and eliminate race conditions in the Verborra audio subsystem. The main technical approach: `@MainActor @Observable` isolation for services and ViewModels + a lock-free SPSC ring buffer for transferring data from the real-time audio callback to the main thread + atomic variables for cross-thread exchange of scalar values (audioLevel, duration, isRecording). Diagnostic logging integration through the existing DiagnosticLogger infrastructure (007).

## Technical context

**Language/Version**: Swift 5.9+ (Xcode 15+)
**Primary Dependencies**: AVFoundation (AVAudioEngine), CoreAudio (AudioObjectPropertyListenerBlock), swift-atomics (NEW — apple/swift-atomics 1.2.0+), swift-markdown (0.4.0+), KeyboardShortcuts (2.0.0+)
**Storage**: N/A (in-memory audio buffers, UserDefaults for settings)
**Testing**: XCTest / Swift Testing (VerborraTests target)
**Target Platform**: macOS 15+ (Sequoia)
**Project Type**: single (macOS desktop app)
**Performance Goals**: <300ms hotkey-to-record, <10ms hotkey press latency, 50-100ms UI update interval for audioLevel/timer
**Constraints**: Real-time audio callback — locks, allocations, and actor hops are forbidden. Maximum recording 5 minutes. Bluetooth device init timeout 5 seconds
**Scale/Scope**: Single desktop application, ~68 Swift files

## Constitution check

*GATE: Must pass before Phase 0. Re-check after Phase 1.*

| Principle | Status | Comment |
|-----------|--------|---------|
| 1. Native macOS experience | ✅ Pass | SwiftUI + NSPanel (OverlayPanel) preserved. All UI updates via @MainActor |
| 2. Swift-first development | ✅ Pass | All code in Swift 5.9+. The new swift-atomics dependency is justified in research.md R-002 (lock-free audio). SPM |
| 3. Minimalism and simplicity | ✅ Pass | We are not adding new functionality. We fix existing concurrency issues. SPSCRingBuffer — a minimal abstraction for one task |
| 4. Security and privacy | ✅ Pass | Audio stays in-memory. API key in Keychain. No changes to networking code |
| 5. Code quality and testing | ✅ Pass | SPSCRingBuffer covered by unit tests. Compilation without warnings (SC-001). Protocols preserve mocking ability |
| 6. Logging and observability | ✅ Pass | The existing DiagnosticLogger infrastructure is used. New async paths are covered by logging (FR-022–FR-028). Logging from the audio callback — only through atomic counters, does not break real-time |

**Pre-Phase 0 gate result**: ✅ All principles satisfied. No violations.

## Project structure

### Documentation (this feature)

```text
specs/008-fix-async-concurrency/
├── spec.md              # Specification (8 US, 28 FR, 13 SC)
├── plan.md              # This file
├── research.md          # 10 research decisions (R-001–R-010)
├── data-model.md        # Concurrency primitives and data flows
├── quickstart.md        # Quick-start instructions
├── contracts/
│   └── protocols.md     # Final protocols with @Sendable @MainActor
└── tasks.md             # → /speckit.tasks
```

### Source code (repository root)

```text
Verborra/
├── Models/
│   ├── ProcessingError.swift       # CHANGE: add RecordingError.notRecording, DeviceErrorReason
│   ├── RecordingState.swift        # No changes
│   └── LogCategory.swift           # No changes (categories from 007)
├── Services/
│   ├── SPSCRingBuffer.swift        # NEW: lock-free ring buffer (R-002)
│   ├── AudioCaptureService.swift   # CHANGE: @MainActor, nonisolated tap, atomics, ring buffer, format listener (R-011–R-013), device name logging
│   ├── AudioDeviceManager.swift    # CHANGE: CFString fix (R-004), @Sendable callbacks, debounce
│   ├── Protocols.swift             # CHANGE: @MainActor protocols, @Sendable closures
│   └── Logging/                    # No changes (007 infrastructure)
│       ├── DiagnosticLogger.swift
│       ├── FlowTracker.swift
│       └── ...
├── ViewModels/
│   ├── RecordingViewModel.swift    # CHANGE: @MainActor, remove Task wrapping, updateLevelsFromAtomic, switchAudioDevice(to:) (R-014)
│   └── OnboardingViewModel.swift   # CHANGE: @MainActor, remove DispatchQueue nesting, onDeviceError
└── Views/                          # Minimal changes (only if the protocol API changed)

VerborraTests/
└── SPSCRingBufferTests.swift       # NEW: ring buffer tests
```

**Structure Decision**: Single project (macOS desktop). The changes affect 7 existing files + 2 new files. All changes are within the `Verborra/` target.

## Architectural overview

### Data flows after the fixes

```
┌─────────────────────────────────────────────────────────┐
│                Audio Thread (real-time)                   │
│  installTap callback (nonisolated)                       │
│    ├─ RMS → _atomicAudioLevel.store(.relaxed)            │
│    ├─ buffer → ringBuffer.write()                        │
│    ├─ zero check → _consecutiveZeroBuffers.store()       │
│    ├─ overflow → _droppedBuffers.increment()             │
│    └─ _isRecording.load(.acquiring) → early exit if false│
└────────────────────────┬────────────────────────────────┘
                         │ (lock-free, no allocations)
                         ▼
┌─────────────────────────────────────────────────────────┐
│              Main Thread (@MainActor)                     │
│                                                           │
│  Timer (50ms) → AudioCaptureService.updateLevelsFromAtomic()
│    ├─ audioLevel = Float(bitPattern: _atomicAudioLevel.load())
│    ├─ accumulatedBuffers += ringBuffer.readAll()          │
│    ├─ check zeroBuffers → autoStop if >10s               │
│    └─ log ring buffer stats (DEBUG, category: tap)       │
│                                                           │
│  RecordingViewModel (@MainActor @Observable)              │
│    ├─ Timer callbacks → direct update (without Task wrap) │
│    ├─ onDeviceError → UI error + stopTimers              │
│    └─ onAutoStop → UI update                              │
│                                                           │
│  AudioCaptureService: Device Format Monitoring (R-011–R-013)│
│    ├─ deviceNominalSampleRate(for:) → CoreAudio API        │
│    ├─ installDeviceFormatListener → kAudioDevicePropertyNominalSampleRate
│    ├─ handleDeviceFormatChange → reset buffers + restart   │
│    └─ removeDeviceFormatListener (on stop/reset/switch)    │
│                                                           │
│  RecordingViewModel: Device Switching (R-014)              │
│    └─ switchAudioDevice(to:) → resetRecording + startRecording
│                                                           │
│  AudioDeviceManager (@MainActor @Observable)              │
│    ├─ CoreAudio listeners → DispatchQueue.main.async      │
│    ├─ debounce: onDeviceLost (1s), onDefaultInputChanged (500ms)
│    └─ CFString → Unmanaged<CFString>? (R-004)             │
└─────────────────────────────────────────────────────────┘
```

### Key architectural decisions

| ID | Decision | Rationale | Reference |
|----|----------|-----------|-----------|
| R-001 | @MainActor instead of Actor | Actor is incompatible with @Observable and SwiftUI | research.md |
| R-002 | SPSC Ring Buffer (swift-atomics) | Lock-free for the real-time audio thread | research.md |
| R-003 | Atomic Float via UInt32 bitcast | No ManagedAtomic\<Float\> | research.md |
| R-004 | Unmanaged\<CFString\>? | Correct interaction with the CoreAudio API | research.md |
| R-005 | @Sendable @MainActor closures | Minimal changes to the callback API | research.md |
| R-006 | Remove Task { @MainActor in } from Timer | Timer is already on the main thread | research.md |
| R-007 | nonisolated for tap callback | Escape from @MainActor isolation | research.md |
| R-008 | Atomic counter for zero-buffers | Silent device detection (10s) | research.md |
| R-009 | @MainActor on ViewModels | Main-thread guarantee for the UI | research.md |
| R-010 | deinit + cleanup() for timers | Leak prevention | research.md |
| R-011 | CoreAudio `kAudioDevicePropertyNominalSampleRate` instead of `inputNode.outputFormat` | `outputFormat` returns a stale sample rate after `setInputDevice` (44100 vs 48000) | plan.md |
| R-012 | `AudioObjectPropertyListenerBlock` on the device's sample rate | Detect Bluetooth-profile changes (A2DP→HFP) for auto-restart | plan.md |
| R-013 | Auto-restart of recording on format change instead of an error | Improves UX — the user does not need to restart manually | plan.md |
| R-014 | `switchAudioDevice(to:)` in RecordingViewModel | Switching the device in the UI effectively restarts the recording | plan.md |
| R-015 | Throttling of drain logs (every 50th cycle) | Prevents a stream of ~10 entries/sec into JSONL | plan.md |

### Implementation order (phases)

1. **Infrastructure** (no risk to existing code):
   - Package.swift → swift-atomics
   - SPSCRingBuffer.swift + tests
   - DeviceErrorReason enum
   - RecordingError.notRecording

2. **Protocols** (contract for the remaining changes):
   - AudioCaptureServiceProtocol → @MainActor + @Sendable closures + updateLevelsFromAtomic()
   - AudioDeviceManagerProtocol → @MainActor + @Sendable closures

3. **Audio core** (highest risk, highest FR coverage):
   - AudioCaptureService → @MainActor + nonisolated tap + ring buffer + atomics + debounce + logging + format monitoring (R-011–R-013): `deviceNominalSampleRate`, `installDeviceFormatListener`, `handleDeviceFormatChange`
   - AudioDeviceManager → CFString fix + @Sendable callbacks + debounce + logging

4. **ViewModels** (depend on the updated protocols):
   - RecordingViewModel → @MainActor + remove Task wrapping + updateLevelsFromAtomic() + onDeviceError + cleanup() + switchAudioDevice(to:) (R-014)
   - ControlBarView → call switchAudioDevice(to:) instead of direct assignment to selectedAudioDeviceID
   - OnboardingViewModel → @MainActor + remove DispatchQueue nesting + onDeviceError + cleanup()

5. **Finalization**:
   - Update mocks (if any) for the new protocols
   - Full build without warnings (SC-001)
   - Manual Bluetooth testing (SC-002)

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| nonisolated tap callback accesses a @MainActor property | Medium | Critical (crash/compile error) | Code review: handleAudioBuffer contains only atomic/ringBuffer operations |
| Ring buffer overflow on long recording | Low | Medium (buffer loss) | capacity=256, drain every 50ms, _droppedBuffers counter + logging |
| Swift 5.9 deinit on an arbitrary thread | Medium | Medium (Timer invalidation from another thread) | cleanup() is called explicitly before window close; deinit as backup |
| Debounce timer is not cancelled on fast reconnect | Low | Low (false notification) | Test with fast Bluetooth on/off |
| @MainActor on protocols breaks existing conformances | High | Medium (compile errors) | Incremental migration: protocols → services → ViewModels |
| Format listener not removed on device switch → stale callbacks | Medium | Medium (crash/incorrect behavior) | `removeDeviceFormatListener()` is called in stop/reset/handleDeviceFormatChange before installing a new one |
| Recursive restart on oscillating sample rate | Low | Medium (infinite loop) | `handleDeviceFormatChange` checks `_isRecording` — a repeated call with inactive recording is ignored |

## Constitution check (post-Phase 1)

| Principle | Status | Comment |
|-----------|--------|---------|
| 1. Native macOS experience | ✅ Pass | Unchanged from pre-check |
| 2. Swift-first development | ✅ Pass | swift-atomics — the only new dependency, justified in R-002 |
| 3. Minimalism and simplicity | ✅ Pass | SPSCRingBuffer — one file, one task. No extra abstractions |
| 4. Security and privacy | ✅ Pass | Unchanged |
| 5. Code quality and testing | ✅ Pass | SPSCRingBuffer covered by tests. 0 warnings after SC-001 |
| 6. Logging and observability | ✅ Pass | FR-022–FR-028 integrate logging through DiagnosticLogger. No calls from the audio callback (atomic counters) |

**Post-Phase 1 gate result**: ✅ All principles satisfied. No violations.

## Complexity tracking

> No constitution violations detected. Table empty.

| Violation | Why needed | Simpler alternative rejected because |
|-----------|------------|--------------------------------------|
| — | — | — |
