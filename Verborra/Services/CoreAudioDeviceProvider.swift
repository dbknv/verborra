import CoreAudio
import Foundation

// MARK: - CoreAudioDeviceProvider

final class CoreAudioDeviceProvider: AudioDeviceProviding, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.verborra.coreAudioProvider")

    // Store listener blocks as properties for correct removal
    private var deviceListListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultInputListenerBlock: AudioObjectPropertyListenerBlock?
    private var sampleRateListenerBlock: AudioObjectPropertyListenerBlock?
    private var sampleRateListenerDeviceID: AudioDeviceID?
    private var streamConfigListenerBlock: AudioObjectPropertyListenerBlock?
    private var streamConfigListenerDeviceID: AudioDeviceID?

    // MARK: - AudioDeviceProviding

    func enumerateInputDevices() -> [AudioDevice] {
        let deviceIDs = allDeviceIDs()
        let defaultUID = defaultInputDeviceUID()

        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            guard hasInputStreams(deviceID: deviceID) else { return nil }
            guard let uid = deviceUID(for: deviceID) else { return nil }
            guard let name = deviceName(for: deviceID) else { return nil }
            // FR-003: Hide macOS internal aggregate device
            if name.hasPrefix("CADefaultDeviceAggregate") { return nil }
            let transport = transportTypeRaw(for: deviceID)

            return AudioDevice(
                uid: uid,
                name: name,
                audioDeviceID: deviceID,
                transportType: AudioDeviceTransportType(coreAudioTransportType: transport),
                isSystemDefault: uid == defaultUID
            )
        }
    }

    func defaultInputDeviceUID() -> String? {
        var deviceID: AudioDeviceID = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr else {
            return nil
        }
        return deviceUID(for: deviceID)
    }

    func nominalSampleRate(for deviceUID: String) -> Float64? {
        guard let deviceID = resolveDeviceID(for: deviceUID) else { return nil }
        var sampleRate: Float64 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate) == noErr else {
            return nil
        }
        return sampleRate
    }

    func transportType(for deviceUID: String) -> AudioDeviceTransportType {
        guard let deviceID = resolveDeviceID(for: deviceUID) else { return .unknown }
        return AudioDeviceTransportType(coreAudioTransportType: transportTypeRaw(for: deviceID))
    }

    func addDeviceListChangeListener(_ handler: @escaping @Sendable () -> Void) {
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { handler() }
        }
        deviceListListenerBlock = block

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, nil, block
        )
    }

    func addDefaultInputChangeListener(_ handler: @escaping @Sendable () -> Void) {
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { handler() }
        }
        defaultInputListenerBlock = block

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, nil, block
        )
    }

    func addSampleRateChangeListener(
        for deviceUID: String,
        handler: @escaping @Sendable (Float64) -> Void
    ) {
        // Remove previous sample rate listener if any
        removeSampleRateListener()

        guard let deviceID = resolveDeviceID(for: deviceUID) else { return }
        sampleRateListenerDeviceID = deviceID

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let rate = self.nominalSampleRate(for: deviceUID) ?? 0
            DispatchQueue.main.async { handler(rate) }
        }
        sampleRateListenerBlock = block

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, block)
    }

    // MARK: - Bluetooth Profile Analysis (FR-035/037)

    func bluetoothProfileState(for deviceUID: String) -> BluetoothProfileState {
        let transport = transportType(for: deviceUID)
        guard transport.isBluetooth else { return .unknown }

        let sampleRate = nominalSampleRate(for: deviceUID) ?? 0

        // FR-035: HFP = low sample rate (≤24kHz); high rate = A2DP
        if sampleRate <= 24000 {
            return .hfp(sampleRate: sampleRate)
        }
        if sampleRate >= 44100 {
            return .a2dp(sampleRate: sampleRate)
        }
        return .unknown
    }

    func streamChannelCount(for deviceUID: String, scope: UInt32) -> UInt32 {
        guard let deviceID = resolveDeviceID(for: deviceUID) else { return 0 }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else {
            return 0
        }
        let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPtr.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPtr) == noErr else {
            return 0
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
        return UInt32(bufferList.reduce(0) { $0 + Int($1.mNumberChannels) })
    }

    func addStreamConfigChangeListener(
        for deviceUID: String,
        handler: @escaping @Sendable () -> Void
    ) {
        removeStreamConfigListener()

        guard let deviceID = resolveDeviceID(for: deviceUID) else { return }
        streamConfigListenerDeviceID = deviceID

        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { handler() }
        }
        streamConfigListenerBlock = block

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, block)
    }

    func removeAllListeners() {
        // Device list listener
        if let block = deviceListListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, nil, block
            )
            deviceListListenerBlock = nil
        }

        // Default input listener
        if let block = defaultInputListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, nil, block
            )
            defaultInputListenerBlock = nil
        }

        // Sample rate listener
        removeSampleRateListener()

        // Stream config listener
        removeStreamConfigListener()
    }

    // MARK: - Private Helpers

    private func removeStreamConfigListener() {
        guard let deviceID = streamConfigListenerDeviceID, let block = streamConfigListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, nil, block)
        streamConfigListenerBlock = nil
        streamConfigListenerDeviceID = nil
    }

    private func removeSampleRateListener() {
        guard let deviceID = sampleRateListenerDeviceID, let block = sampleRateListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, nil, block)
        sampleRateListenerBlock = nil
        sampleRateListenerDeviceID = nil
    }

    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids
        ) == noErr else {
            return []
        }
        return ids
    }

    private func hasInputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else {
            return false
        }
        let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPtr.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPtr) == noErr else {
            return false
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var uid: Unmanaged<CFString>?
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid) == noErr,
              let cfString = uid?.takeRetainedValue() else {
            return nil
        }
        return cfString as String
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr,
              let cfString = name?.takeRetainedValue() else {
            return nil
        }
        return cfString as String
    }

    private func transportTypeRaw(for deviceID: AudioDeviceID) -> UInt32 {
        var transport: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport) == noErr else {
            return 0
        }
        return transport
    }

    /// Resolve a stable UID to the current (possibly unstable) AudioDeviceID.
    func resolveDeviceID(for uid: String) -> AudioDeviceID? {
        let ids = allDeviceIDs()
        return ids.first { deviceUID(for: $0) == uid }
    }

    deinit {
        removeAllListeners()
    }
}
