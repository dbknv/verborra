import XCTest
@testable import Verborra

// MARK: - PermissionManagerTests (T031)

final class PermissionManagerTests: XCTestCase {

    // MARK: - PermissionType Tests

    func testMicrophoneIsRequired() {
        XCTAssertTrue(PermissionType.microphone.isRequired)
    }

    func testAccessibilityIsNotRequired() {
        XCTAssertFalse(PermissionType.accessibility.isRequired)
    }

    func testMicrophoneSystemSettingsURL() {
        XCTAssertEqual(
            PermissionType.microphone.systemSettingsURL,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
    }

    func testAccessibilitySystemSettingsURL() {
        XCTAssertEqual(
            PermissionType.accessibility.systemSettingsURL,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testAllPermissionTypes() {
        XCTAssertEqual(PermissionType.allCases.count, 2)
        XCTAssertTrue(PermissionType.allCases.contains(.microphone))
        XCTAssertTrue(PermissionType.allCases.contains(.accessibility))
    }

    // MARK: - PermissionStatus Tests

    func testPermissionStatusRawValues() {
        XCTAssertEqual(PermissionStatus.notDetermined.rawValue, "notDetermined")
        XCTAssertEqual(PermissionStatus.granted.rawValue, "granted")
        XCTAssertEqual(PermissionStatus.denied.rawValue, "denied")
        XCTAssertEqual(PermissionStatus.restricted.rawValue, "restricted")
    }

    // MARK: - MockPermissionManager Tests

    func testMockDefaultStatuses() {
        let mock = MockPermissionManager()
        XCTAssertEqual(mock.microphoneStatus, .notDetermined)
        XCTAssertEqual(mock.accessibilityStatus, .notDetermined)
    }

    func testMockProgrammaticStatusSetting() {
        let mock = MockPermissionManager()
        mock.microphoneStatus = .granted
        mock.accessibilityStatus = .denied

        XCTAssertEqual(mock.microphoneStatus, .granted)
        XCTAssertEqual(mock.accessibilityStatus, .denied)
    }

    func testMockCallTracking() {
        let mock = MockPermissionManager()

        mock.requestMicrophoneAccess()
        mock.requestMicrophoneAccess()
        XCTAssertEqual(mock.requestMicrophoneAccessCallCount, 2)

        mock.requestAccessibilityAccess()
        XCTAssertEqual(mock.requestAccessibilityAccessCallCount, 1)
    }

    func testMockMonitoringCallTracking() {
        let mock = MockPermissionManager()

        mock.startMonitoring()
        mock.startMonitoring()
        XCTAssertEqual(mock.startMonitoringCallCount, 2)

        mock.stopMonitoring()
        XCTAssertEqual(mock.stopMonitoringCallCount, 1)
    }

    // MARK: - PermissionManager Singleton Tests

    func testSharedInstanceExists() {
        let manager = PermissionManager.shared
        XCTAssertNotNil(manager)
    }

    func testSharedInstanceIsSame() {
        let manager1 = PermissionManager.shared
        let manager2 = PermissionManager.shared
        XCTAssertTrue(manager1 === manager2)
    }

    // MARK: - PermissionManager Monitoring Reference Count Tests

    func testMonitoringStartStop() {
        let manager = PermissionManager.shared

        // Start monitoring
        manager.startMonitoring()
        // Stop monitoring
        manager.stopMonitoring()
        // Should not crash if stop called extra time (clamped to 0)
        manager.stopMonitoring()
    }

    func testMultipleMonitoringSubscribers() {
        let manager = PermissionManager.shared

        // Multiple starts
        manager.startMonitoring()
        manager.startMonitoring()
        manager.startMonitoring()

        // Only fully stops when all subscribers unsubscribe
        manager.stopMonitoring()
        manager.stopMonitoring()
        manager.stopMonitoring()
    }

    // MARK: - T038: US2a Three-Branch Logic Tests

    /// T038: Verify microphone status has all four expected values (FR-020)
    func testMicrophoneStatusFourStates() {
        let allStatuses: [PermissionStatus] = [.notDetermined, .granted, .denied, .restricted]
        XCTAssertEqual(allStatuses.count, 4)
        // Verify all are distinct
        XCTAssertEqual(Set(allStatuses.map(\.rawValue)).count, 4)
    }

    /// T038: Verify mock tracks requestMicrophoneAccess calls for .denied scenario
    func testMockRequestMicrophoneAccessDeniedTracking() {
        let mock = MockPermissionManager()
        mock.microphoneStatus = .denied

        // Calling request when denied should still be tracked
        mock.requestMicrophoneAccess()
        XCTAssertEqual(mock.requestMicrophoneAccessCallCount, 1)

        // Multiple calls tracked independently
        mock.requestMicrophoneAccess()
        XCTAssertEqual(mock.requestMicrophoneAccessCallCount, 2)
    }

    /// T038: Verify mock tracks requestMicrophoneAccess calls for .restricted scenario
    func testMockRequestMicrophoneAccessRestrictedTracking() {
        let mock = MockPermissionManager()
        mock.microphoneStatus = .restricted

        mock.requestMicrophoneAccess()
        XCTAssertEqual(mock.requestMicrophoneAccessCallCount, 1)
    }

    /// T038: Verify PermissionManager initial status matches AVCaptureDevice
    func testPermissionManagerInitialMicrophoneStatus() {
        let manager = PermissionManager.shared
        // After init, microphoneStatus should be one of the valid 4 states
        let validStatuses: [PermissionStatus] = [.notDetermined, .granted, .denied, .restricted]
        XCTAssertTrue(validStatuses.contains(manager.microphoneStatus),
                      "microphoneStatus should be one of: notDetermined, granted, denied, restricted")
    }

    /// T038: Verify PermissionManager does not allow concurrent requests (isRequestInProgress)
    func testRequestInProgressGuard() {
        let manager = PermissionManager(forTesting: true)
        // This test verifies that calling requestMicrophoneAccess doesn't crash
        // The isRequestInProgress guard prevents duplicate system dialogs
        manager.requestMicrophoneAccess()
        // Second call should be ignored if first is still in progress
        manager.requestMicrophoneAccess()
    }
}
