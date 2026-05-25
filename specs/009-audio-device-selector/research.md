# Research: Audio Device Selection

**Date**: 2026-03-20
**Feature**: 009-audio-device-selector

## Decision 1: Device identification — AudioDeviceID vs DeviceUID

**Decision**: Use `kAudioDevicePropertyDeviceUID` (CFString string) to identify and save devices.

**Rationale**:
- `AudioDeviceID` (UInt32) is unstable across reboots and reconnects. The current implementation stores it as a string in `@AppStorage("selectedAudioDeviceID")`, which can lead to selecting the wrong device after a reboot.
- `kAudioDevicePropertyDeviceUID` returns a stable string (for example, `AppleHDAEngineInput:1B,0,1,0:1`) that is preserved across reboots for the same physical device.
- The specification explicitly requires `kAudioDevicePropertyDeviceUID` (FR-009).

**Getting DeviceUID**:
```swift
var uid: Unmanaged<CFString>?
var address = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDeviceUID,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
let uidString = uid?.takeRetainedValue() as String?
```

**Mapping UID → AudioDeviceID**: On every device enumeration, build a dictionary `[String: AudioDeviceID]`. When a CoreAudio API call is needed, convert the UID back to AudioDeviceID.

**Alternatives considered**:
- Keep `AudioDeviceID` (UInt32) — rejected: unstable, violates FR-009.
- Use `kAudioDevicePropertyModelUID` — rejected: identifies the model, not a specific instance.

## Decision 2: Hot-plug listener for detecting connection/disconnection

**Decision**: Use `AudioObjectAddPropertyListenerBlock` on `kAudioHardwarePropertyDevices` (system object).

**Rationale**:
- CoreAudio notifies about changes in the device list via a property listener on `kAudioObjectSystemObject`.
- This is the standard pattern for macOS applications working with audio.
- The project already uses `AudioObjectAddPropertyListenerBlock` to monitor sample rate (`installDeviceFormatListener` in `AudioCaptureService.swift:547`).

**Implementation**:
```swift
var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
AudioObjectAddPropertyListenerBlock(
    AudioObjectID(kAudioObjectSystemObject),
    &address,
    DispatchQueue.main,  // callback on main queue
    listenerBlock
)
```

**A listener for System Default is also needed**:
```swift
var defaultAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
```

**Alternatives considered**:
- Polling (timer-based polling) — rejected: inefficient, detection delay.
- `AVAudioSession` notifications — rejected: iOS-only API, unavailable on macOS.

## Decision 3: System Default Input Device

**Decision**: Obtain via `kAudioHardwarePropertyDefaultInputDevice` and display as "System Default" without the name of a specific device.

**Rationale**:
- The specification (FR-002) requires a single item "System Default" without specifying a name.
- `kAudioHardwarePropertyDefaultInputDevice` returns the `AudioDeviceID` of the current system default device.
- When passing `nil` as deviceID to `AudioCaptureService.startRecording()` — AVAudioEngine automatically uses the system default device.

**Internal representation**: In the `AudioDevice` model, a value of `uid = nil` denotes System Default. In UserDefaults it is stored as an empty string `""`. For the `Identifiable` protocol, `id = uid ?? "system-default"` is used.

**Alternatives considered**:
- Show the name of the system device — rejected: contradicts the specification.

## Decision 4: Extracting AudioDeviceManager from AudioCaptureService

**Decision**: Create a separate `@Observable` class `AudioDeviceManager` to manage the device list.

**Rationale**:
- `AudioCaptureService` (771 lines) is already overloaded: audio capture, buffering, conversion, format monitoring.
- Managing the device list (hot-plug, sorting, System Default, fallback, saving) is a separate responsibility.
- Allows testing the device logic without dependency on AVAudioEngine.
- `ControlBarView` currently creates `AudioCaptureService()` every time for the device list — this is wrong.

**AudioDeviceManager responsibilities**:
- Device enumeration with DeviceUID
- Hot-plug listener (connection/disconnection)
- Default input device listener
- "System Default" as the first element
- Alphabetical sorting
- Saving/restoring the selection from UserDefaults
- Fallback to System Default on disconnect
- Checking the availability of the saved device at startup

**AudioCaptureService responsibilities** (unchanged):
- AVAudioEngine lifecycle
- Audio capture and buffering
- Sample rate monitoring
- Conversion to WAV

**Alternatives considered**:
- Extend AudioCaptureService — rejected: the class is already 771 lines, violates SRP.
- Use an extension — rejected: does not solve the testability problem.

## Decision 5: Bluetooth A2DP→HFP UI indication

**Decision**: Add the `.bluetoothSwitching` state to the UI logic of `RecordingViewModel` with a 200ms timer.

**Rationale**:
- FR-018: spinner + "Switching…" when >200ms; Start/Stop button disabled.
- Use `DispatchWorkItem` with a 200ms delay: if switching completes before it fires — show nothing; if not — show the spinner.
- Profile switching is detected via the existing `installDeviceFormatListener` (sample rate change callback).

**Logic**:
1. User selects a Bluetooth device → start a delayed 200ms timer.
2. If sample rate stabilizes before 200ms → cancel the timer, continue normally.
3. If 200ms has passed — show the spinner, disable Start/Stop.
4. On stabilization or 5s timeout — hide the spinner.

**Alternatives considered**:
- Always show the spinner — rejected: FR-018 requires showing only at >200ms.
- Detect Bluetooth via IOBluetooth — rejected: excessive dependency; detect by transport type (`kAudioDevicePropertyTransportType`).

## Decision 8: Saving audio to disk (WAV Writer)

**Decision**: Implement `AudioFileWriter` — a service for streaming audio recording to a WAV file using `AVAudioFile`.

**Rationale**:
- `AVAudioFile` provides a simple API for writing `AVAudioPCMBuffer` to a file
- WAV (PCM) is the format per the specification, compatible with any audio editor
- The recording must be streaming (not buffered in memory) so as not to duplicate the in-memory buffer
- Disk write errors must not affect the main flow (graceful degradation)

**Integration into the audio flow**:
1. `AudioCaptureService` on tap installation calls `AudioFileWriter.write(buffer:)` for each buffer
2. `AudioFileWriter` opens the file at the start of recording, closes at stop
3. On device/sample rate change: close the current file, open a new one
4. Write errors are logged but do not interrupt the main recording

**File name**: `YYYY-MM-DD_HH-mm-ss_<Device name>.wav`
- Characters `/`, `:`, `\` are replaced with `_`
- For System Default, "System Default" is used in the name

**Alternatives considered**:
- **ExtAudioFile** (CoreAudio C API) — more low-level, but `AVAudioFile` is sufficient
- **Buffering + write on stop** — requires additional memory, not a streaming approach

## Decision 9: Security-Scoped Bookmarks for the save folder

**Decision**: Use Security-Scoped Bookmarks to preserve access to the folder between sessions in App Sandbox.

**Rationale**:
- App Sandbox is enabled (Constitution Principle 4)
- Without bookmarks, access to a folder selected via NSOpenPanel is lost on restart
- Bookmark data is saved in UserDefaults (a compact `Data` blob)

**Required entitlement**:
```xml
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
```

**Bookmark lifecycle**:
1. User selects a folder via `NSOpenPanel` → create a bookmark: `url.bookmarkData(options: .withSecurityScope)`
2. Save `Data` to UserDefaults
3. At startup: resolve the bookmark → `URL(resolvingBookmarkData:options:bookmarkDataIsStale:)`
4. If `bookmarkDataIsStale` → recreate the bookmark
5. Before writing: `url.startAccessingSecurityScopedResource()`
6. After writing: `url.stopAccessingSecurityScopedResource()`

**Important**: Calls to `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` are not nested — calling stop immediately revokes access.

**Known macOS 15.0 issue**: A bug with Security-Scoped Bookmarks, fixed in macOS 15.1. The minimum target is macOS 15, but it can be handled gracefully.

**Alternatives considered**:
- **Store the path as a string** — rejected: without a bookmark, the sandbox will not grant access on restart
- **Fixed directory in Application Support** — rejected: the specification requires the user to select

## Decision 10: Reaction to System Default change during recording

**Decision**: A listener on `kAudioHardwarePropertyDefaultInputDevice` restarts the recording if "System Default" is selected and recording is active (FR-028).

**Rationale**:
- When the system device is changed in System Settings, CoreAudio notifies via a property listener
- If the user has selected "System Default" (rather than a specific device), the recording must follow the system selection
- The restart is similar to a manual device change (FR-016)
- When saving to disk: close the current file, open a new one with a timestamp and the name "System Default"

**Alternatives considered**:
- **Continue on the old device** — rejected by the user in the clarify session
- **Stop recording with a notification** — rejected: less convenient than automatic restart

## Decision 11: Tension with Constitution Principle 4

**Decision**: Document the controlled deviation from Principle 4 in the Complexity Tracking of the plan.

**Rationale**:
- Principle 4: "Audio recording MUST NOT be saved to disk (only in-memory buffer)"
- Feature 009 adds optional WAV saving to disk (FR-020 — FR-027)
- This is a controlled deviation:
  - The feature is **disabled by default**
  - Enabled only via **Advanced Settings** (explicit opt-in)
  - Files are written **only to the folder selected by the user**
  - The purpose is **diagnostics and archiving**
  - The main recording (in-memory → API) works independently
- The user request explicitly requires this functionality

## Decision 6: Device type detection (Bluetooth)

**Decision**: Use `kAudioDevicePropertyTransportType` to detect Bluetooth devices.

**Rationale**:
- Necessary for the decision when to apply A2DP→HFP logic.
- CoreAudio provides `kAudioDevicePropertyTransportType` that returns a `UInt32`:
  - `kAudioDeviceTransportTypeBluetooth` (= 'blue')
  - `kAudioDeviceTransportTypeBluetoothLE` (= 'blea')
  - `kAudioDeviceTransportTypeBuiltIn` (= 'bltn')
  - `kAudioDeviceTransportTypeUSB` (= 'usb ')
  - `kAudioDeviceTransportTypeVirtual` (= 'virt')

**Usage**: Only for the Bluetooth switching logic (spinner) and logging. The device type is not displayed in the UI (clarify session decision).

**Alternatives considered**:
- Detect by name (contains "Bluetooth") — rejected: unreliable.
- Use the IOBluetooth framework — rejected: excessive dependency.

## Decision 12: Unified Bluetooth device preparation method (BluetoothProfileManager)

**Decision**: Create a dedicated class `BluetoothProfileManager` with a single entry point `prepareForRecording(device:context:) async -> BluetoothPreparationResult`, encapsulating all the logic for checking and switching Bluetooth profiles (A2DP→HFP).

**Rationale**:
- FR-031: single method for all three scenarios (first start, device change, reconnect)
- FR-032: a clear sequence of steps with subscription to OS events
- The current implementation scatters BT logic between `AudioDeviceManager` (timer/spinner/timeout) and `AudioCaptureService` (handleDeviceFormatChange) — this is duplication and complexity for testing
- Extraction into a separate class allows:
  - Testing the BT logic in isolation via MockAudioDeviceProvider
  - Logging each stage per FR-034 in one place
  - Avoiding the bloating of AudioDeviceManager (265 lines)

**Architecture**:
```
AudioDeviceManager
    └── BluetoothProfileManager (owns BT preparation lifecycle)
            └── AudioDeviceProviding (CoreAudio abstraction)
```

**Key methods**:
- `prepareForRecording(device: AudioDevice, context: BluetoothPreparationContext) async -> BluetoothPreparationResult`
- `restoreA2DP(device: AudioDevice)` — silent return after stopping recording

**Determining the current profile** (macOS does not provide a direct API, FR-035):
Criterion: `kAudioDevicePropertyNominalSampleRate` — ≤24 kHz = HFP, ≥44.1 kHz = A2DP.
Filter: `kAudioDevicePropertyTransportType` == bluetooth/bluetoothLE (so as not to confuse USB microphones with a low sample rate).

**Clarification (2026-03-21)**: Input channels (`kAudioDevicePropertyStreamConfiguration` input scope) MUST NOT be used as a profile criterion. For input-only BT devices (Loopback aggregate, virtual devices with a BT source) `inputChannels > 0` is always true, regardless of A2DP/HFP. The condition `inputChannels > 0 || sampleRate <= 24000` led to false HFP detection at 48kHz. Sample rate is the only reliable indicator.

**Debounce stabilization** (FR-036):
During A2DP→HFP switching, the device may briefly report an intermediate incorrect sample rate. Algorithm:
1. On receiving notification about a change of any of the three properties — wait 300 ms
2. Re-read all three properties, perform composite analysis
3. If the result has changed compared to the previous reading — wait another 300 ms, repeat
4. The profile is stabilized when two consecutive readings (300 ms) produce the same result
5. The total timeout (including all cycles) is 5 seconds (FR-014)

**Subscribing to all three properties simultaneously** (FR-037):
When ANY listener fires → re-read ALL three properties and recompute the profile. Ensures robustness when one property has updated and the others have not yet.

**Initiating A2DP→HFP switching**:
- macOS automatically switches the BT profile when the device is set as input via `kAudioOutputUnitProperty_CurrentDevice`
- An explicit command is not needed — we subscribe to three properties (FR-037) and wait for stabilization (FR-036)

**Return to A2DP after stopping recording**:
- Stop and deallocate AVAudioEngine → macOS will return the profile automatically (1-5s)
- We DO NOT change the system default input (invasive for other applications)
- The return error is logged but does not affect the user (FR-033)

**Alternatives considered**:
- Embed the logic into AudioCaptureService — rejected: violates SRP
- Keep in AudioDeviceManager without a separate class — rejected: bloats the class, complicates testing
- IOBluetooth framework — rejected: deprecated, unstable
- AVAudioSession (iOS) — rejected: unavailable on macOS

**Sources**:
- [supermegaultragroovy.com — AVAudioEngine + AirPods](https://supermegaultragroovy.com/2021/01/28/more-on-avaudioengine-airpods/)
- [Hammerspoon BT audio fix](https://ssrubin.com/posts/fixing-macos-bluetooth-headphone-audio-quality-issues-with-hammerspoon.html)
- Apple Developer: AudioHardwareBase.h — transport type constants

## Decision 13: Extending AudioDeviceProviding for composite BT profile analysis

**Decision**: Add two methods to the `AudioDeviceProviding` protocol:
- `bluetoothProfileState(for deviceUID: String) -> BluetoothProfileState` — composite analysis of three properties (FR-035)
- `streamConfiguration(for deviceUID: String, scope: AudioObjectPropertyScope) -> UInt32` — channel count (input/output scope)

**Rationale**:
- BluetoothProfileManager must determine the current profile via sample rate analysis (FR-035)
- Implementation in CoreAudioDeviceProvider:
  1. Check transportType → if not bluetooth → .unknown
  2. Request nominalSampleRate
  3. Return .hfp if sampleRate ≤ 24000, .a2dp if ≥ 44100, otherwise .unknown
- MockAudioDeviceProvider can return the needed configurations for tests of transitional states

**Change of approach (2026-03-21)**: Originally, "majority" analysis of 3 properties (sample rate + input channels + output channels) was intended to be used. In practice, input channels turned out to be unreliable — for input-only BT devices (Loopback) `inputChannels > 0` is always true, which gave a false HFP at 48kHz. Sample rate is the only reliable indicator.

**Alternatives considered**:
- Sample rate + input channels + output channels (composite analysis) — **initially chosen, then rejected**: input channels is unreliable for input-only BT devices
- Direct access to CoreAudio from BluetoothProfileManager — rejected: violates the abstraction, complicates tests

## Decision 14: BluetoothProfileManager logging (FR-034)

**Decision**: Use DiagnosticLogger with the `.bluetooth` category. Each stage of the unified method is logged with a separate call.

**Logged events**:

| Event | Level | Metadata |
|-------|-------|----------|
| `bt_prepare_start` | INFO | context, deviceID, deviceName, currentProfile |
| `bt_profile_check` | INFO | decision (skip/required), currentSampleRate |
| `bt_switch_initiated` | INFO | deviceID, listenerInstalled |
| `bt_os_event_received` | INFO | newSampleRate, waitDuration_ms |
| `bt_prepare_complete` | INFO | result, finalSampleRate, totalDuration_ms |
| `bt_a2dp_restore_start` | DEBUG | deviceID, deviceName |
| `bt_a2dp_restore_complete` | INFO | result (success/error) |

**Rationale**: Conforms to the constitution (Principle 6) and FR-034. The dual sink system (os.Logger + JSONL) provides real-time and retrospective diagnostics.

## Decision 7: Closing the dropdown on hot-plug

**Decision**: Use a `@State` flag for forced refresh of `Menu`.

**Rationale**:
- FR-010: the dropdown must close when the device list changes.
- SwiftUI `Menu` does not have a programmatic API to close.
- Solution: change the `id` modifier on `Menu` when receiving a hot-plug notification — SwiftUI will recreate the view, closing the menu.

**Implementation**:
```swift
Menu { ... }
    .id(viewModel.deviceListVersion)  // UUID, updated on hot-plug
```

**Alternatives considered**:
- `NSMenu` via AppKit — rejected: violates Principle 1 (SwiftUI-only for UI).
- Ignore closing — rejected: violates FR-010.

## Decision 15: Protection against false format listener triggers (FR-038)

**Date**: 2026-03-21
**Decision**: Store `lastKnownSampleRate` in AudioCaptureService and compare on each format listener notification.

**Rationale**:
- The CoreAudio `kAudioDevicePropertyNominalSampleRate` listener fires not only on an actual rate change but also on changes to other audio properties (engine setup, tap installation).
- `handleDeviceFormatChange()` → `prepareAndStartEngine()` → `installDeviceFormatListener()` created an infinite loop: installing a new engine provoked the listener → restart → listener → restart...
- On the Hijack Mic device the cycle repeated every ~380ms, generating 462 log lines in seconds.

**Implementation**:
- `lastKnownSampleRate` is set in `prepareAndStartEngine()` before `installDeviceFormatListener()`
- In `handleDeviceFormatChange()` — if `newRate == lastKnownSampleRate` → ignore, log as debug
- Reset on `resetRecording()` (nil)

**Alternatives considered**:
- Delay (debounce) before processing the listener — rejected: does not solve the root problem, only masks it
- Remove the listener before engine setup — rejected: a window for missing actual changes

## Decision 16: onDeviceFallback callback for updating the UI on fallback (FR-039)

**Date**: 2026-03-21
**Decision**: Add the `onDeviceFallback` callback to `AudioCaptureServiceProtocol`. On fallback — call `switchAudioDevice(to: "")` via the standard flow.

**Rationale**:
- On an engine error (code `-10868`) on AntennaPods, `prepareAndStartEngine` silently switched to the default device
- `currentDeviceName`, `selectedDevice` in AudioDeviceManager, the file name — everything remained from the old device
- The UI (floating window) showed "AntennaPods" although the recording was actually from the MacBook Microphone

**Implementation**:
1. `AudioCaptureService.prepareAndStartEngine` fallback path updates `currentDeviceName`/`currentDeviceIDForRecording`
2. Calls `onDeviceFallback?(defaultName)`
3. `RecordingViewModel` → `switchAudioDevice(to: "")` — standard flow: selectDevice + reset + restart

**Alternatives considered**:
- Only update `selectedDevice` without restart (notifyFallbackToSystemDefault) — rejected by the user: a full standard flow with recording restart is needed
- Do not notify the UI, only update internal state — rejected: the user sees the wrong device

## Decision 17: Two-phase BT startup with stabilization in AudioCaptureService (FR-032/036/040)

**Date**: 2026-03-21
**Decision**: Move BT rate stabilization from `BluetoothProfileManager` to `AudioCaptureService`. Two-phase startup: engine without tap → stabilization → fresh engine with tap.

**Rationale**:
- macOS switches A2DP→HFP only when the engine actually uses the device as input
- `BluetoothProfileManager` did not have access to the engine → subscribed to listeners, but switching was not triggered → 5s timeout
- `deviceNominalSampleRate` may return a stale value after A2DP restore → `already_hfp` is unreliable

**Architecture**:
```
BluetoothProfileManager.prepareForRecording()  → instant profile detection
AudioCaptureService.startRecording(awaitBluetoothSwitch: true):
  Phase 1: startEngineForBTSwitch()  → engine.start() without tap, triggers A2DP→HFP
  Phase 2: awaitBluetoothStabilization()  → listener on NominalSampleRate
           → initial check 300ms (for already-HFP)
           → accepts only rate ≤24kHz (ignores false 48kHz from engine setup)
           → debounce 300ms + confirm
           → 5s timeout
  Phase 3: stop trigger engine → fresh AVAudioEngine()
  Phase 4: prepareAndStartEngine()  → tap + file writing at the stabilized rate
```

**Key decision**: `awaitBluetoothSwitch: true` for ALL BT devices, even `already_hfp`. Reason: between profile detection and engine start, time passes during which macOS may return to A2DP. Stabilization via the engine is the only reliable way.

**Alternatives considered**:
- Stabilization in BluetoothProfileManager with an engine — rejected: the BT manager must not know about the engine (SRP)
- `awaitBluetoothSwitch` only for A2DP — rejected: `already_hfp` is unreliable, format mismatch crash
- Accept any rate during stabilization — rejected: engine setup causes false 48kHz notifications
