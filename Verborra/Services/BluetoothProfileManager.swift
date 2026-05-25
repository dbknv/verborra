import Foundation

// MARK: - BluetoothProfileManaging Protocol (FR-031/032)

@MainActor
protocol BluetoothProfileManaging {
    func prepareForRecording(
        device: AudioDevice,
        context: BluetoothPreparationContext
    ) async -> BluetoothPreparationResult

    func restoreA2DP(device: AudioDevice)
    func cancelPreparation()
    var isPreparing: Bool { get }
}

// MARK: - BluetoothProfileManager (FR-031/032/033/034/035/036/037)

@MainActor
@Observable
final class BluetoothProfileManager: BluetoothProfileManaging {

    private(set) var isPreparing = false

    private let provider: AudioDeviceProviding
    private let logger = DiagnosticLogger.logger(for: .bluetooth)
    private var preparingDeviceUID: String?
    private var prepareStartTime: Date?

    init(provider: AudioDeviceProviding) {
        self.provider = provider
    }

    // MARK: - prepareForRecording (FR-031/032)

    func prepareForRecording(
        device: AudioDevice,
        context: BluetoothPreparationContext
    ) async -> BluetoothPreparationResult {
        cancelPreparation()

        preparingDeviceUID = device.uid
        prepareStartTime = Date()

        let currentProfile = provider.bluetoothProfileState(for: device.uid)

        // T009: bt_prepare_start
        logger.info("bt_prepare_start", metadata: [
            "context": context.rawValue,
            "deviceName": device.name,
            "deviceID": device.uid,
            "currentProfile": currentProfile.profileName,
            "currentSampleRate": currentProfile.sampleRate.map { String(format: "%.0f", $0) } ?? "nil"
        ])

        // Check if already HFP — no switch needed
        if currentProfile.isHFP, let rate = currentProfile.sampleRate {
            logger.info("bt_profile_check", metadata: [
                "decision": "skip",
                "currentSampleRate": String(format: "%.0f", rate),
                "inputChannels": String(provider.streamChannelCount(for: device.uid, scope: 0x696E7074)),
                "outputChannels": String(provider.streamChannelCount(for: device.uid, scope: 0x6F757470))
            ])

            let duration = Date().timeIntervalSince(prepareStartTime ?? Date()) * 1000
            logger.info("bt_prepare_complete", metadata: [
                "result": "already_hfp",
                "finalSampleRate": String(format: "%.0f", rate),
                "totalDuration_ms": String(format: "%.0f", duration)
            ])

            preparingDeviceUID = nil
            return .alreadyHFP(sampleRate: rate)
        }

        // A2DP detected — switch needed. Engine start will trigger A2DP→HFP,
        // AudioCaptureService handles stabilization before installing tap.
        logger.info("bt_profile_check", metadata: [
            "decision": "required",
            "currentSampleRate": currentProfile.sampleRate.map { String(format: "%.0f", $0) } ?? "nil",
            "inputChannels": String(provider.streamChannelCount(for: device.uid, scope: 0x696E7074)),
            "outputChannels": String(provider.streamChannelCount(for: device.uid, scope: 0x6F757470))
        ])

        preparingDeviceUID = nil
        return .needsSwitch(currentSampleRate: currentProfile.sampleRate ?? 0)
    }

    // MARK: - restoreA2DP (FR-033)

    func restoreA2DP(device: AudioDevice) {
        // T009: bt_a2dp_restore_start
        logger.debug("bt_a2dp_restore_start", metadata: [
            "deviceID": device.uid,
            "deviceName": device.name
        ])

        // macOS returns to A2DP automatically when AudioUnit is released.
        // We just log the intent. Errors are silent per FR-033.

        // T009: bt_a2dp_restore_complete
        logger.info("bt_a2dp_restore_complete", metadata: [
            "deviceID": device.uid,
            "deviceName": device.name,
            "result": "success"
        ])
    }

    // MARK: - cancelPreparation

    func cancelPreparation() {
        preparingDeviceUID = nil
    }
}
