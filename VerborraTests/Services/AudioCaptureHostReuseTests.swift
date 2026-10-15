import AVFoundation
import XCTest
@testable import Verborra

// MARK: - FakeEngineHost

/// Records teardown calls; start paths are never reached by these tests.
private final class FakeEngineHost: AudioEngineHosting, @unchecked Sendable {
    private(set) var teardownCalls = 0
    var currentStep: AudioSetupStep { .idle }
    var isEngineRunning: Bool { false }

    func start(
        deviceID: AudioDeviceID?,
        generation: UInt64,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) async throws -> AudioHostStartResult {
        throw AudioSetupError.cancelled
    }

    func startBluetoothTrigger(deviceID: AudioDeviceID?, generation: UInt64) async throws -> AudioDeviceID {
        throw AudioSetupError.cancelled
    }

    func teardown(generation: UInt64?) {
        teardownCalls += 1
    }

    func stop() async {}
}

// MARK: - AudioCaptureHostReuseTests (spec 015, US9, T101)

/// The audio host is reused while healthy, so a queued teardown runs before the next start on the
/// same serial queue (FR-050). It is replaced only after one of its calls timed out (research R31).
@MainActor
final class AudioCaptureHostReuseTests: XCTestCase {
    private var hosts: [FakeEngineHost] = []
    private var service: AudioCaptureService!

    override func setUp() {
        super.setUp()
        hosts = []
        service = AudioCaptureService(hostFactory: { [unowned self] in
            let host = FakeEngineHost()
            self.hosts.append(host)
            return host
        })
    }

    func testHealthyHostIsReusedAndTornDownInOrder() {
        XCTAssertEqual(hosts.count, 1)

        service.prepareHostForStart()
        service.prepareHostForStart()

        XCTAssertEqual(hosts.count, 1, "a queued teardown is not a stuck host")
        XCTAssertEqual(hosts[0].teardownCalls, 2)
    }

    func testHostIsReplacedOnlyAfterATimeout() {
        service.noteHostTimedOut()
        service.prepareHostForStart()

        XCTAssertEqual(hosts.count, 2)
        XCTAssertEqual(hosts[0].teardownCalls, 0, "the stuck host is abandoned, not queued behind")

        service.prepareHostForStart()
        XCTAssertEqual(hosts.count, 2, "the flag is cleared once a new host exists")
    }

    func testDeviceDisplayNameIsUsedInsteadOfNumericID() {
        XCTAssertEqual(AudioCaptureService.displayName(forDeviceID: "200", resolver: { _ in "USB Mic" }), "USB Mic")
        XCTAssertEqual(AudioCaptureService.displayName(forDeviceID: nil, resolver: { _ in "x" }), "System Default")
        XCTAssertEqual(AudioCaptureService.displayName(forDeviceID: "200", resolver: { _ in nil }), "200")
    }
}
