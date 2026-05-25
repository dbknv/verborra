import Foundation
@testable import Verborra

// MARK: - MockPermissionManager (T030)

final class MockPermissionManager: PermissionChecking {
    var microphoneStatus: PermissionStatus = .notDetermined
    var accessibilityStatus: PermissionStatus = .notDetermined

    // Call tracking
    var requestMicrophoneAccessCallCount = 0
    var requestAccessibilityAccessCallCount = 0
    var startMonitoringCallCount = 0
    var stopMonitoringCallCount = 0

    func requestMicrophoneAccess() {
        requestMicrophoneAccessCallCount += 1
    }

    func requestAccessibilityAccess() {
        requestAccessibilityAccessCallCount += 1
    }

    func startMonitoring() {
        startMonitoringCallCount += 1
    }

    func stopMonitoring() {
        stopMonitoringCallCount += 1
    }
}
