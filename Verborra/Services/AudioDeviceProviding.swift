import Foundation

// MARK: - AudioDeviceProviding

protocol AudioDeviceProviding: Sendable {
    /// Enumerate all available input audio devices.
    func enumerateInputDevices() -> [AudioDevice]

    /// Get the UID of the current system default input device.
    func defaultInputDeviceUID() -> String?

    /// Get the nominal sample rate for a device identified by UID.
    func nominalSampleRate(for deviceUID: String) -> Float64?

    /// Get the transport type for a device identified by UID.
    func transportType(for deviceUID: String) -> AudioDeviceTransportType

    /// Add a listener for device list changes (connect/disconnect).
    func addDeviceListChangeListener(_ handler: @escaping @Sendable () -> Void)

    /// Add a listener for default input device changes.
    func addDefaultInputChangeListener(_ handler: @escaping @Sendable () -> Void)

    /// Add a listener for sample rate changes on a specific device.
    func addSampleRateChangeListener(
        for deviceUID: String,
        handler: @escaping @Sendable (Float64) -> Void
    )

    /// Remove all installed listeners.
    func removeAllListeners()

    // MARK: - Bluetooth Profile Analysis (FR-035/037)

    /// Determine the current Bluetooth profile via composite analysis of three properties:
    /// sample rate + input stream channels + output stream channels.
    /// Returns `.unknown` for non-Bluetooth devices. (FR-035)
    func bluetoothProfileState(for deviceUID: String) -> BluetoothProfileState

    /// Get the number of channels in stream configuration for a given scope.
    /// - Parameters:
    ///   - deviceUID: Stable device UID
    ///   - scope: `kAudioObjectPropertyScopeInput` or `kAudioObjectPropertyScopeOutput`
    /// - Returns: Channel count (0 if no streams in this scope)
    func streamChannelCount(for deviceUID: String, scope: UInt32) -> UInt32

    /// Add a listener for stream configuration changes on a specific device (FR-037).
    /// Fires when input or output stream topology changes (e.g., A2DP→HFP transition).
    func addStreamConfigChangeListener(
        for deviceUID: String,
        handler: @escaping @Sendable () -> Void
    )
}
