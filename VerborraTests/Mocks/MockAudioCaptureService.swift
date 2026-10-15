import AVFoundation
import Foundation
@testable import Verborra

@MainActor
final class MockAudioCaptureService: AudioCaptureServiceProtocol {
    /// Scripted outcome of one `startRecording` call (spec 015, T046).
    enum StartResult {
        case success
        case failure(AudioSetupError)
        /// Never returns on its own; ends only when the calling task is cancelled.
        case hang
    }

    var audioLevel: Float = 0.0
    var currentDuration: TimeInterval = 0.0
    var onAutoStop: (@Sendable @MainActor () -> Void)?
    var onDeviceError: (@Sendable @MainActor (_ deviceName: String?, _ reason: DeviceErrorReason) -> Void)?
    var audioSaveSettings: (enabled: Bool, folderBookmark: Data?)?
    var lastBluetoothSwitchMs: Double = 0

    var startRecordingCalled = false
    var stopRecordingCalled = false
    var resetRecordingCalled = false
    var updateLevelsCalled = false
    var lastDeviceID: String?
    var lastMaxDuration: MaxRecordingDuration?
    var isRecording = false
    var mockAudioData = Data()
    var shouldThrowOnStart = false
    var shouldThrowOnStop = false

    /// Results for successive start calls; when empty, a call succeeds.
    var startResults: [StartResult] = []
    /// Delay before each scripted result is applied.
    var startDelay: Duration = .zero
    private(set) var startDeviceIDs: [String?] = []
    private(set) var startAttempts: [Int] = []
    private(set) var startTimeouts: [(setup: Duration, firstBuffer: Duration)] = []
    private(set) var cancelStartCalls = 0
    /// `bluetoothTimeout` of each start call (spec 015, T099).
    private(set) var bluetoothTimeouts: [Duration] = []
    /// Call order: "reset", "start", "cancel" — lets tests check that capture stops before a switch starts.
    private(set) var calls: [String] = []

    func startRecording(
        deviceID: String?,
        maxDuration: MaxRecordingDuration,
        awaitBluetoothSwitch: Bool,
        attempt: Int,
        timeouts: StartTimeouts
    ) async throws {
        calls.append("start")
        bluetoothTimeouts.append(timeouts.bluetooth)
        startRecordingCalled = true
        startDeviceIDs.append(deviceID)
        startAttempts.append(attempt)
        startTimeouts.append((timeouts.setup, timeouts.firstBuffer))
        if shouldThrowOnStart {
            throw RecordingError.microphoneNotAvailable
        }

        let result = startResults.isEmpty ? .success : startResults.removeFirst()
        if startDelay > .zero {
            try await Task.sleep(for: startDelay)
        }
        switch result {
        case .success:
            lastDeviceID = deviceID
            lastMaxDuration = maxDuration
            isRecording = true
        case .failure(let error):
            throw error
        case .hang:
            // Like a stuck host: the real facade gives up after `setupTimeout`.
            try await Task.sleep(for: timeouts.setup)
            throw AudioSetupError.timeout(step: "start")
        }
    }

    func cancelStart() {
        calls.append("cancel")
        cancelStartCalls += 1
        isRecording = false
    }

    func stopRecording() async throws -> Data {
        stopRecordingCalled = true
        isRecording = false
        if shouldThrowOnStop {
            throw RecordingError.notRecording
        }
        return mockAudioData
    }

    func resetRecording() {
        calls.append("reset")
        resetRecordingCalled = true
        isRecording = false
        audioLevel = 0
        currentDuration = 0
    }

    func updateLevelsFromAtomic() {
        updateLevelsCalled = true
    }

    func availableInputDevices() -> [(id: String, name: String)] {
        [("1", "Built-in Microphone"), ("2", "AirPods")]
    }
}
