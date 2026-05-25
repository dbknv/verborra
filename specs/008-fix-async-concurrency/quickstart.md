# Quick Start: Swift Concurrency Fixes

**Branch**: `008-fix-async-concurrency`

## Prerequisites

- Xcode 15+ (Swift 5.9)
- macOS 15+ (Sequoia)
- Bluetooth headset for testing (AirPods, Jabra, Plantronics)

## Setup

```bash
git checkout 008-fix-async-concurrency
open Verborra.xcodeproj
```

SPM will automatically download the new `swift-atomics` dependency when the project opens.

## Key files to change

| File | What to change |
|------|----------------|
| `Package.swift` | Add swift-atomics |
| `Verborra/Services/SPSCRingBuffer.swift` | NEW — lock-free ring buffer |
| `Verborra/Services/AudioCaptureService.swift` | @MainActor, nonisolated tap, ring buffer, atomics |
| `Verborra/Services/AudioDeviceManager.swift` | CFString fix (Unmanaged), @Sendable callbacks |
| `Verborra/Services/Protocols.swift` | @Sendable @MainActor closures |
| `Verborra/ViewModels/RecordingViewModel.swift` | @MainActor, remove Task wrapping from Timer |
| `Verborra/ViewModels/OnboardingViewModel.swift` | @MainActor, remove DispatchQueue.main.async from Timer |

## Implementation order

1. **Infrastructure**: Package.swift → SPSCRingBuffer.swift → ring buffer tests
2. **Core**: AudioCaptureService (@MainActor + nonisolated tap + atomics)
3. **Protocols**: @Sendable @MainActor callbacks
4. **ViewModels**: @MainActor + remove redundant wrapping
5. **Tests**: update mocks, final build

## Verification

```bash
# Build without warnings
xcodebuild build -project Verborra.xcodeproj -scheme Verborra 2>&1 | grep -c "warning:"
# Expected result: 0

# Tests
xcodebuild test -project Verborra.xcodeproj -scheme VerborraTests
```

## Manual testing

1. **Bluetooth recording**: connect AirPods → record 30 sec → stop → verify WAV
2. **Fast start/stop**: press record/stop 10 times with interval <500ms
3. **Device disconnect**: start recording over Bluetooth → turn off the headset → verify error in UI
4. **Floating window**: record via overlay → verify timer and level indicator
5. **Onboarding**: microphone test → disconnect device → verify error

## Architectural decisions

- **@MainActor instead of Actor** — Actor is incompatible with @Observable (research.md R-001)
- **SPSC Ring Buffer** — lock-free for real-time audio thread (research.md R-002)
- **Atomic Float via UInt32 bitcast** — no ManagedAtomic<Float> (research.md R-003)
- **Unmanaged\<CFString\>?** — safe interaction with CoreAudio API (research.md R-004)
