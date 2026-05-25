import Foundation
import Testing
@testable import Verborra

// MARK: - BluetoothLogThrottleTests (T066)

struct BluetoothLogThrottleTests {

    @Test func firstEvent_alwaysAllowed() {
        let throttle = BluetoothLogThrottle.shared
        throttle.reset()
        #expect(throttle.shouldLog(deviceID: "device-1") == true)
    }

    @Test func rapidEvents_throttled() {
        let throttle = BluetoothLogThrottle.shared
        throttle.reset()
        #expect(throttle.shouldLog(deviceID: "device-2") == true)
        // Immediate second call should be throttled
        #expect(throttle.shouldLog(deviceID: "device-2") == false)
    }

    @Test func differentDevices_independentThrottling() {
        let throttle = BluetoothLogThrottle.shared
        throttle.reset()
        #expect(throttle.shouldLog(deviceID: "device-A") == true)
        #expect(throttle.shouldLog(deviceID: "device-B") == true)
        // Both should be throttled for rapid repeat
        #expect(throttle.shouldLog(deviceID: "device-A") == false)
        #expect(throttle.shouldLog(deviceID: "device-B") == false)
    }

    @Test func eventAfterInterval_allowed() async throws {
        let throttle = BluetoothLogThrottle.shared
        throttle.reset()
        #expect(throttle.shouldLog(deviceID: "device-3") == true)
        // Wait > 100ms
        try await Task.sleep(nanoseconds: 120_000_000) // 120ms
        #expect(throttle.shouldLog(deviceID: "device-3") == true)
    }
}
