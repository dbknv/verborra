import CoreAudio
import Testing
@testable import Verborra

// MARK: - AudioDeviceManagerTests

@MainActor
struct AudioDeviceManagerTests {
    // MARK: - Helpers

    private func makeProvider(
        devices: [AudioDevice] = [],
        defaultUID: String? = nil
    ) -> MockAudioDeviceProvider {
        let provider = MockAudioDeviceProvider()
        provider.mockDevices = devices
        provider.mockDefaultUID = defaultUID
        return provider
    }

    private func makeSettings() -> AppSettings {
        AppSettings(keychainService: MockKeychainService())
    }

    private static let builtInMic = AudioDevice(
        uid: "BuiltInMicUID",
        name: "MacBook Pro Microphone",
        audioDeviceID: 100,
        transportType: .builtIn,
        isSystemDefault: true
    )

    private static let usbMic = AudioDevice(
        uid: "USBMicUID",
        name: "Blue Yeti",
        audioDeviceID: 200,
        transportType: .usb,
        isSystemDefault: false
    )

    private static let btMic = AudioDevice(
        uid: "BTMicUID",
        name: "AirPods Pro",
        audioDeviceID: 300,
        transportType: .bluetooth,
        isSystemDefault: false
    )

    // MARK: - Enumeration Tests

    @Test("Devices list has System Default first, then alphabetical")
    func testDeviceListOrder() {
        let provider = makeProvider(
            devices: [Self.usbMic, Self.builtInMic, Self.btMic],
            defaultUID: Self.builtInMic.uid
        )
        let settings = makeSettings()
        let manager = AudioDeviceManager(provider: provider, settings: settings)

        #expect(manager.devices.count == 4) // System Default + 3 real
        #expect(manager.devices[0].isSystemDefaultEntry)
        #expect(manager.devices[0].name == "System Default")
        // Alphabetical: AirPods Pro, Blue Yeti, MacBook Pro Microphone
        #expect(manager.devices[1].name == "AirPods Pro")
        #expect(manager.devices[2].name == "Blue Yeti")
        #expect(manager.devices[3].name == "MacBook Pro Microphone")
    }

    // MARK: - Selection Tests

    @Test("selectDevice saves UID to settings")
    func testSelectDevice() {
        let provider = makeProvider(
            devices: [Self.builtInMic, Self.usbMic],
            defaultUID: Self.builtInMic.uid
        )
        let settings = makeSettings()
        let manager = AudioDeviceManager(provider: provider, settings: settings)

        manager.selectDevice(uid: Self.usbMic.uid)

        #expect(manager.selectedDevice?.uid == Self.usbMic.uid)
        #expect(settings.selectedAudioDeviceUID == Self.usbMic.uid)
    }

    @Test("selectDevice with empty UID selects System Default")
    func testSelectSystemDefault() {
        let provider = makeProvider(
            devices: [Self.builtInMic],
            defaultUID: Self.builtInMic.uid
        )
        let settings = makeSettings()
        let manager = AudioDeviceManager(provider: provider, settings: settings)

        manager.selectDevice(uid: "")

        #expect(manager.selectedDevice?.isSystemDefaultEntry == true)
        #expect(settings.selectedAudioDeviceUID == "")
    }

    // MARK: - Restore on Launch

    @Test("Restores saved device on launch when found")
    func testRestoreSavedDevice() {
        let provider = makeProvider(
            devices: [Self.builtInMic, Self.usbMic],
            defaultUID: Self.builtInMic.uid
        )
        let settings = makeSettings()
        settings.selectedAudioDeviceUID = Self.usbMic.uid

        let manager = AudioDeviceManager(provider: provider, settings: settings)

        #expect(manager.selectedDevice?.uid == Self.usbMic.uid)
    }

    @Test("Falls back to System Default when saved device not found")
    func testRestoreFallback() {
        let provider = makeProvider(
            devices: [Self.builtInMic],
            defaultUID: Self.builtInMic.uid
        )
        let settings = makeSettings()
        settings.selectedAudioDeviceUID = "NonExistentUID"

        let manager = AudioDeviceManager(provider: provider, settings: settings)

        #expect(manager.selectedDevice?.isSystemDefaultEntry == true)
        #expect(settings.selectedAudioDeviceUID == "")
    }

    // MARK: - Hot-plug / Fallback Tests

    @Test("Device disconnected triggers fallback to System Default")
    func testDeviceDisconnectedFallback() {
        let provider = makeProvider(
            devices: [Self.builtInMic, Self.usbMic],
            defaultUID: Self.builtInMic.uid
        )
        let settings = makeSettings()
        let manager = AudioDeviceManager(provider: provider, settings: settings)
        manager.selectDevice(uid: Self.usbMic.uid)

        var disconnectedCalled = false
        manager.onDeviceDisconnected = { disconnectedCalled = true }

        // Simulate USB mic disconnection
        provider.mockDevices = [Self.builtInMic]
        provider.simulateDeviceListChange()

        #expect(manager.selectedDevice?.isSystemDefaultEntry == true)
        #expect(disconnectedCalled)
    }

    @Test("Other device disconnected does not change selection")
    func testOtherDeviceDisconnectedKeepsSelection() {
        let provider = makeProvider(
            devices: [Self.builtInMic, Self.usbMic, Self.btMic],
            defaultUID: Self.builtInMic.uid
        )
        let settings = makeSettings()
        let manager = AudioDeviceManager(provider: provider, settings: settings)
        manager.selectDevice(uid: Self.usbMic.uid)

        var disconnectedCalled = false
        manager.onDeviceDisconnected = { disconnectedCalled = true }

        // Simulate BT mic disconnection (not the selected one)
        provider.mockDevices = [Self.builtInMic, Self.usbMic]
        provider.simulateDeviceListChange()

        #expect(manager.selectedDevice?.uid == Self.usbMic.uid)
        #expect(!disconnectedCalled)
    }

    @Test("System default change triggers callback when System Default selected")
    func testDefaultDeviceChangedCallback() {
        let provider = makeProvider(
            devices: [Self.builtInMic],
            defaultUID: Self.builtInMic.uid
        )
        let settings = makeSettings()
        let manager = AudioDeviceManager(provider: provider, settings: settings)
        // System Default is selected by default (empty UID)

        var defaultChangedCalled = false
        manager.onDefaultDeviceChanged = { defaultChangedCalled = true }

        provider.simulateDefaultInputChange()

        #expect(defaultChangedCalled)
    }
}
