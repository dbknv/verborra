import AVFoundation
import Foundation
@testable import Verborra

@MainActor
final class MockAudioCaptureService: AudioCaptureServiceProtocol {
    var audioLevel: Float = 0.0
    var currentDuration: TimeInterval = 0.0
    var onAutoStop: (@Sendable @MainActor () -> Void)?
    var onDeviceError: (@Sendable @MainActor (_ deviceName: String?, _ reason: DeviceErrorReason) -> Void)?
    var onDeviceFallback: (@Sendable @MainActor (_ fallbackDeviceName: String) -> Void)?
    var audioSaveSettings: (enabled: Bool, folderBookmark: Data?)?

    var startRecordingCalled = false
    var stopRecordingCalled = false
    var resetRecordingCalled = false
    var updateLevelsCalled = false
    var lastDeviceID: String?
    var mockAudioData = Data()
    var shouldThrowOnStart = false
    var shouldThrowOnStop = false

    func startRecording(deviceID: String?, maxDuration: MaxRecordingDuration, awaitBluetoothSwitch: Bool = false) async throws {
        startRecordingCalled = true
        lastDeviceID = deviceID
        if shouldThrowOnStart {
            throw RecordingError.microphoneNotAvailable
        }
    }

    func stopRecording() async throws -> Data {
        stopRecordingCalled = true
        if shouldThrowOnStop {
            throw RecordingError.notRecording
        }
        return mockAudioData
    }

    func resetRecording() {
        resetRecordingCalled = true
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
