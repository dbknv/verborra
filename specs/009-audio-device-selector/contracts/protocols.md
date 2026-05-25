# Internal contracts (protocols): Audio device selection

**Feature**: 009-audio-device-selector
**Date**: 2026-03-20

> The native macOS application does not use REST/GraphQL APIs. Contracts are formalized as Swift protocols to ensure testability and separation of concerns.

## AudioDeviceProviding

Protocol for abstracting access to CoreAudio (testability).

```swift
protocol AudioDeviceProviding: Sendable {
    /// Enumerate all input audio devices
    func enumerateInputDevices() -> [AudioDevice]

    /// Get the current system default device
    func defaultInputDeviceUID() -> String?

    /// Get the sample rate of a device
    func nominalSampleRate(for deviceUID: String) -> Float64?

    /// Get the transport type of a device
    func transportType(for deviceUID: String) -> AudioDeviceTransportType

    /// Set a listener for changes in the device list
    func addDeviceListChangeListener(_ handler: @escaping () -> Void)

    /// Set a listener for changes in the default input device
    func addDefaultInputChangeListener(_ handler: @escaping () -> Void)

    /// Set a listener for changes in the sample rate of a specific device
    func addSampleRateChangeListener(
        for deviceUID: String,
        handler: @escaping (Float64) -> Void
    )

    /// Remove all listeners
    func removeAllListeners()

    /// Determine current Bluetooth profile via composite analysis (FR-035)
    /// Analyzes sample rate + input channels + output channels
    /// Returns .unknown for non-Bluetooth devices
    func bluetoothProfileState(for deviceUID: String) -> BluetoothProfileState

    /// Number of channels in stream configuration (FR-035)
    /// - scope: kAudioObjectPropertyScopeInput or kAudioObjectPropertyScopeOutput
    /// - Returns: number of channels (0 if no streams in this scope)
    func streamChannelCount(for deviceUID: String, scope: UInt32) -> UInt32

    /// Subscribe to changes in stream configuration of a specific device (FR-037)
    func addStreamConfigChangeListener(
        for deviceUID: String,
        handler: @escaping @Sendable () -> Void
    )
}
```

## BluetoothProfileManaging (new, FR-031/032)

Protocol for unified Bluetooth profile management.

```swift
@MainActor
protocol BluetoothProfileManaging {
    /// Prepare a Bluetooth device for recording (FR-031/032)
    /// Single method for all scenarios: first start, device change, reconnect
    /// - Parameters:
    ///   - device: Bluetooth device to prepare
    ///   - context: Call context (for logging per FR-034)
    /// - Returns: Preparation result
    func prepareForRecording(
        device: AudioDevice,
        context: BluetoothPreparationContext
    ) async -> BluetoothPreparationResult

    /// Initiate return to A2DP after stopping recording (FR-033)
    /// Errors are logged but do not affect the user
    func restoreA2DP(device: AudioDevice)

    /// Cancel current preparation (rapid device switching)
    func cancelPreparation()

    /// Whether preparation is in progress
    var isPreparing: Bool { get }
}
```

## AudioDeviceManaging

Protocol for device management (used by ViewModel).

```swift
@MainActor
protocol AudioDeviceManaging: Observable {
    /// Sorted device list (System Default first, separator, alphabetical)
    var devices: [AudioDevice] { get }

    /// Currently selected device
    var selectedDevice: AudioDevice? { get }

    /// List version (for closing dropdown on hot-plug)
    var deviceListVersion: UUID { get }

    /// Bluetooth switching state
    var isBluetoothSwitching: Bool { get }

    /// Select device by UID (empty string = System Default)
    func selectDevice(uid: String)

    /// Callback when selected device is disconnected
    var onDeviceDisconnected: (() -> Void)? { get set }

    /// Callback on completion of Bluetooth A2DP->HFP switch (passes final sample rate)
    var onBluetoothSwitchComplete: ((Float64) -> Void)? { get set }

    /// Callback on Bluetooth switch error
    var onBluetoothSwitchError: ((String) -> Void)? { get set }

    /// Callback on system default device change (FR-028)
    var onDefaultDeviceChanged: (() -> Void)? { get set }
}
```

## AudioFileWriting

Protocol for writing audio to disk.

```swift
protocol AudioFileWriting {
    /// Start writing to a new WAV file
    /// - Parameters:
    ///   - deviceName: Device name for the file name
    ///   - sampleRate: Sample rate
    ///   - format: Audio format (channels, bit depth)
    ///   - folder: Folder URL for saving
    /// - Returns: URL of the created file
    func startWriting(
        deviceName: String,
        sampleRate: Float64,
        format: AVAudioFormat,
        folder: URL
    ) throws -> URL

    /// Write an audio buffer to the file
    func write(buffer: AVAudioPCMBuffer) throws

    /// Finish and close the current file
    func stopWriting()

    /// Whether file writing is active
    var isWriting: Bool { get }
}
```

## Protocol interaction

```
RecordingViewModel
    │
    ├── uses AudioDeviceManaging  (AudioDeviceManager)
    │       │
    │       ├── uses AudioDeviceProviding  (CoreAudioDeviceProvider / MockDeviceProvider)
    │       │
    │       └── uses BluetoothProfileManaging  (BluetoothProfileManager)
    │               │
    │               └── uses AudioDeviceProviding  (for profile detection and event subscription)
    │
    └── uses AudioCaptureService
            │
            └── uses AudioFileWriting  (AudioFileWriter / disabled)
```
