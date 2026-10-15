import XCTest
@testable import Verborra

final class TargetAppTrackerTests: XCTestCase {
    var tracker: TargetAppTracker!

    override func setUp() {
        super.setUp()
        tracker = TargetAppTracker()
    }

    override func tearDown() {
        tracker.stopTracking()
        tracker = nil
        super.tearDown()
    }

    func testInitialPIDIsZero() {
        XCTAssertEqual(tracker.targetPID, 0)
    }

    func testStartTrackingCapturesFrontmostApp() {
        tracker.startTracking()
        // If there's a frontmost app that isn't us, PID should be set
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier > 0,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            XCTAssertGreaterThan(tracker.targetPID, 0)
        }
    }

    func testStopTrackingResetsPID() {
        tracker.startTracking()
        tracker.stopTracking()
        XCTAssertEqual(tracker.targetPID, 0)
    }

    func testExcludesOwnBundleIdentifier() {
        tracker.startTracking()
        // After starting, targetPID should NOT be our own process
        if tracker.targetPID > 0 {
            let ownPID = ProcessInfo.processInfo.processIdentifier
            XCTAssertNotEqual(tracker.targetPID, ownPID)
        }
    }
}
