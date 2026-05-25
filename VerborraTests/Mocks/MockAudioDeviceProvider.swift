import CoreAudio
import Foundation
@testable import Verborra

// MARK: - MockAudioDeviceProvider

final class MockAudioDeviceProvider: AudioDeviceProviding, @unchecked Sendable {
    // Configurable data
    var mockDevices: [AudioDevice] = []
    var mockDefaultUID: String? = nil
    var mockSampleRates: [String: Float64] = [:]
    var mockTransportTypes: [String: AudioDeviceTransportType] = [:]
    var mockBluetoothProfileStates: [String: BluetoothProfileState] = [:]
    var mockStreamChannelCounts: [String: [UInt32: UInt32]] = [:]  // UID → [scope → channels]

    // Captured handlers
    private(set) var deviceListChangeHandler: (@Sendable () -> Void)?
    private(set) var defaultInputChangeHandler: (@Sendable () -> Void)?
    private(set) var sampleRateChangeHandler: (@Sendable (Float64) -> Void)?
    private(set) var sampleRateListenerUID: String?
    private(set) var streamConfigChangeHandler: (@Sendable () -> Void)?
    private(set) var streamConfigListenerUID: String?

    // Track calls
    private(set) var removeAllListenersCalled = false

    // MARK: - AudioDeviceProviding

    func enumerateInputDevices() -> [AudioDevice] {
        mockDevices
    }

    func defaultInputDeviceUID() -> String? {
        mockDefaultUID
    }

    func nominalSampleRate(for deviceUID: String) -> Float64? {
        mockSampleRates[deviceUID]
    }

    func transportType(for deviceUID: String) -> AudioDeviceTransportType {
        mockTransportTypes[deviceUID] ?? .unknown
    }

    func addDeviceListChangeListener(_ handler: @escaping @Sendable () -> Void) {
        deviceListChangeHandler = handler
    }

    func addDefaultInputChangeListener(_ handler: @escaping @Sendable () -> Void) {
        defaultInputChangeHandler = handler
    }

    func addSampleRateChangeListener(
        for deviceUID: String,
        handler: @escaping @Sendable (Float64) -> Void
    ) {
        sampleRateListenerUID = deviceUID
        sampleRateChangeHandler = handler
    }

    func bluetoothProfileState(for deviceUID: String) -> BluetoothProfileState {
        mockBluetoothProfileStates[deviceUID] ?? .unknown
    }

    func streamChannelCount(for deviceUID: String, scope: UInt32) -> UInt32 {
        mockStreamChannelCounts[deviceUID]?[scope] ?? 0
    }

    func addStreamConfigChangeListener(
        for deviceUID: String,
        handler: @escaping @Sendable () -> Void
    ) {
        streamConfigListenerUID = deviceUID
        streamConfigChangeHandler = handler
    }

    func removeAllListeners() {
        removeAllListenersCalled = true
        deviceListChangeHandler = nil
        defaultInputChangeHandler = nil
        sampleRateChangeHandler = nil
        sampleRateListenerUID = nil
        streamConfigChangeHandler = nil
        streamConfigListenerUID = nil
    }

    // MARK: - Test Helpers

    /// Simulate a device list change event.
    func simulateDeviceListChange() {
        deviceListChangeHandler?()
    }

    /// Simulate a default input device change event.
    func simulateDefaultInputChange() {
        defaultInputChangeHandler?()
    }

    /// Simulate a sample rate change event.
    func simulateSampleRateChange(newRate: Float64) {
        sampleRateChangeHandler?(newRate)
    }

    /// Simulate a stream configuration change event (FR-037).
    func simulateStreamConfigChange() {
        streamConfigChangeHandler?()
    }

    /// Simulate a full Bluetooth profile transition (sample rate + stream config).
    func simulateBluetoothProfileChange(to profile: BluetoothProfileState, for deviceUID: String) {
        mockBluetoothProfileStates[deviceUID] = profile
        if let rate = profile.sampleRate {
            mockSampleRates[deviceUID] = rate
        }
        sampleRateChangeHandler?(profile.sampleRate ?? 0)
        streamConfigChangeHandler?()
    }
}
