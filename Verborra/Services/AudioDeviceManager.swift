import Foundation

// MARK: - AudioDeviceManager

@MainActor
@Observable
final class AudioDeviceManager {
    /// Sorted list: System Default first, then alphabetical.
    private(set) var devices: [AudioDevice] = []

    /// Currently selected device (nil if none selected yet).
    private(set) var selectedDevice: AudioDevice?

    /// UUID that changes on every device list update — use as `.id()` to force SwiftUI refresh.
    private(set) var deviceListVersion: UUID = UUID()

    /// Bluetooth A2DP→HFP switching in progress.
    private(set) var isBluetoothSwitching: Bool = false

    /// Timestamp when BT switching started (for timeout calculation).
    private(set) var bluetoothSwitchingStartTime: Date?

    // MARK: - Callbacks

    /// Called when the selected device is physically disconnected.
    var onDeviceDisconnected: (() -> Void)?

    /// Called when Bluetooth A2DP→HFP switching completes with the final sample rate.
    var onBluetoothSwitchComplete: ((Float64) -> Void)?

    /// Called when Bluetooth switching fails (timeout or error).
    var onBluetoothSwitchError: ((String) -> Void)?

    /// Called when the system default input device changes while "System Default" is selected.
    var onDefaultDeviceChanged: (() -> Void)?

    // MARK: - Private

    private let provider: AudioDeviceProviding
    private let settings: AppSettings
    private let log = DiagnosticLogger.logger(for: .audio)

    /// Unified Bluetooth profile manager (FR-031)
    let bluetoothProfileManager: BluetoothProfileManager

    /// 200ms delay before showing spinner (FR-018)
    private var btSpinnerDelayWork: DispatchWorkItem?

    // MARK: - Init

    init(provider: AudioDeviceProviding, settings: AppSettings) {
        self.provider = provider
        self.settings = settings
        self.bluetoothProfileManager = BluetoothProfileManager(provider: provider)

        // Run migration from old numeric ID to stable UID
        let initialDevices = provider.enumerateInputDevices()
        settings.migrateAudioDeviceIDToUID(devices: initialDevices)

        // Build initial device list
        refreshDeviceList()

        // Restore selection from settings
        restoreSelection()

        // Install hot-plug listener (T007)
        provider.addDeviceListChangeListener { [weak self] in
            MainActor.assumeIsolated {
                self?.handleDeviceListChanged()
            }
        }

        // Install default input device change listener (T018/FR-028)
        provider.addDefaultInputChangeListener { [weak self] in
            MainActor.assumeIsolated {
                self?.handleDefaultInputChanged()
            }
        }
    }

    // MARK: - Public API

    /// Select a device by UID — persistent. Saves to settings. Used from Settings picker.
    /// Empty string = System Default.
    func selectDevice(uid: String) {
        let oldDevice = selectedDevice
        let target = devices.first(where: { $0.uid == uid })

        guard let target else {
            log.info("selectDevice: UID not found, ignoring", metadata: ["uid": uid])
            return
        }

        selectedDevice = target
        settings.selectedAudioDeviceUID = uid

        log.info("selectDevice", metadata: [
            "oldDeviceID": oldDevice?.uid ?? "none",
            "oldDeviceName": oldDevice?.name ?? "none",
            "newDeviceID": target.uid.isEmpty ? "system-default" : target.uid,
            "newDeviceName": target.name,
        ])

        // Cancel any in-progress BT preparation
        bluetoothProfileManager.cancelPreparation()
        cancelSpinnerDelay()

        // If new device is Bluetooth, start unified profile preparation (FR-031)
        if target.transportType.isBluetooth && !target.isSystemDefaultEntry {
            startBluetoothPreparation(for: target, context: .deviceSwitch)
        }
    }

    /// Select a device for the current session only — does NOT write to settings.
    /// Used from floating window dropdown. Empty string = System Default.
    func selectDeviceForSession(uid: String) {
        let target = devices.first(where: { $0.uid == uid })
            ?? devices.first // fallback to System Default

        guard let target else { return }

        let oldDevice = selectedDevice
        selectedDevice = target

        log.info("selectDeviceForSession", metadata: [
            "oldDeviceID": oldDevice?.uid ?? "none",
            "oldDeviceName": oldDevice?.name ?? "none",
            "newDeviceID": target.uid.isEmpty ? "system-default" : target.uid,
            "newDeviceName": target.name,
        ])

        // Cancel any in-progress BT preparation
        bluetoothProfileManager.cancelPreparation()
        cancelSpinnerDelay()

        if target.transportType.isBluetooth && !target.isSystemDefaultEntry {
            startBluetoothPreparation(for: target, context: .deviceSwitch)
        }
    }

    /// Start async BT profile preparation via unified method (FR-031).
    /// Maps result to legacy callbacks for ViewModel compatibility.
    func startBluetoothPreparation(for device: AudioDevice, context: BluetoothPreparationContext) {
        bluetoothSwitchingStartTime = Date()

        // FR-018: Show spinner after 200ms delay
        let spinnerWork = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.isBluetoothSwitching = true
            }
        }
        btSpinnerDelayWork = spinnerWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: spinnerWork)

        Task { [weak self] in
            guard let self else { return }
            let result = await self.bluetoothProfileManager.prepareForRecording(
                device: device,
                context: context
            )

            self.cancelSpinnerDelay()
            self.isBluetoothSwitching = false
            self.bluetoothSwitchingStartTime = nil

            switch result {
            case .ready(let sampleRate):
                self.onBluetoothSwitchComplete?(sampleRate)
            case .alreadyHFP(let sampleRate):
                self.onBluetoothSwitchComplete?(sampleRate)
            case .needsSwitch(let sampleRate):
                // A2DP detected — switch will happen when engine starts recording
                self.onBluetoothSwitchComplete?(sampleRate)
            case .timeout:
                self.onBluetoothSwitchError?("Bluetooth switch timeout")
            case .error(let error):
                self.onBluetoothSwitchError?(error.localizedDescription)
            case .deviceDisconnected:
                self.onBluetoothSwitchError?("Device disconnected during switch")
            }
        }
    }

    private func cancelSpinnerDelay() {
        btSpinnerDelayWork?.cancel()
        btSpinnerDelayWork = nil
    }

    // MARK: - Device List Management

    private func refreshDeviceList() {
        let rawDevices = provider.enumerateInputDevices()

        // Build list: System Default first, then alphabetical
        let systemDefault = AudioDevice(
            uid: "",
            name: "System Default",
            audioDeviceID: 0,
            transportType: .unknown,
            isSystemDefault: true
        )

        let sorted = rawDevices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        devices = [systemDefault] + sorted
        deviceListVersion = UUID()
    }

    private func restoreSelection() {
        let savedUID = settings.selectedAudioDeviceUID

        if savedUID.isEmpty {
            // System Default
            selectedDevice = devices.first
        } else if let device = devices.first(where: { $0.uid == savedUID }) {
            selectedDevice = device
        } else {
            // Saved device not found — silent fallback to System Default
            log.info("Saved device not found, falling back to System Default", metadata: ["savedUID": savedUID])
            selectedDevice = devices.first
            settings.selectedAudioDeviceUID = ""
        }
    }

    // MARK: - Hot-plug (T007)

    private func handleDeviceListChanged() {
        let previousSelectedUID = selectedDevice?.uid

        refreshDeviceList()

        // FR-008: Check if persistent default device disappeared from device list
        let persistentUID = settings.selectedAudioDeviceUID
        if !persistentUID.isEmpty && devices.first(where: { $0.uid == persistentUID }) == nil {
            log.info("Persistent default device disconnected, resetting to System Default", metadata: [
                "persistentUID": persistentUID
            ])
            settings.selectedAudioDeviceUID = ""
        }

        // Check if session-selected device is still present
        if let uid = previousSelectedUID, !uid.isEmpty {
            if devices.first(where: { $0.uid == uid }) == nil {
                let oldName = selectedDevice?.name ?? "unknown"
                log.info("Session device disconnected, fallback to System Default", metadata: [
                    "reason": "device_disconnected",
                    "oldDeviceID": uid,
                    "oldDeviceName": oldName,
                    "newDeviceID": "system-default",
                    "newDeviceName": "System Default",
                ])
                selectedDevice = devices.first
                onDeviceDisconnected?()
            } else {
                selectedDevice = devices.first(where: { $0.uid == uid })
            }
        } else {
            selectedDevice = devices.first
        }
    }

    // MARK: - Default Input Changed (FR-028)

    private func handleDefaultInputChanged() {
        refreshDeviceList()

        // Only act if "System Default" is selected
        guard let selected = selectedDevice, selected.isSystemDefaultEntry else { return }

        log.info("System default input device changed")
        onDefaultDeviceChanged?()
    }

    // MARK: - Cleanup

    deinit {
        provider.removeAllListeners()
    }
}
