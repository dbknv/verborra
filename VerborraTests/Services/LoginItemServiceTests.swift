import ServiceManagement
import XCTest
@testable import Verborra

// MARK: - Fakes

private final class FakeLoginItemBackend: LoginItemBackend {
    var status: SMAppService.Status
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var openSettingsCalls = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openSettingsCalls += 1
    }
}

@MainActor
private final class FakeIntentStore: LoginItemIntentStore {
    var launchAtLoginIntent: Bool?
    init(_ intent: Bool?) { launchAtLoginIntent = intent }
}

// MARK: - LoginItemServiceTests (spec 015, T033)

@MainActor
final class LoginItemServiceTests: XCTestCase {
    private let applicationsURL = URL(fileURLWithPath: "/Applications/Verborra.app")
    private let home = URL(fileURLWithPath: "/Users/tester")

    private func makeService(
        intent: Bool?,
        status: SMAppService.Status
    ) -> (LoginItemService, FakeLoginItemBackend, FakeIntentStore) {
        let backend = FakeLoginItemBackend(status: status)
        let store = FakeIntentStore(intent)
        let service = LoginItemService(intentStore: store, backend: backend, bundleURL: applicationsURL, homeDirectory: home)
        return (service, backend, store)
    }

    // MARK: Reconcile table

    func testOnboardingNotCompletedDoesNothing() {
        let (service, backend, store) = makeService(intent: nil, status: .notRegistered)
        service.reconcileAtLaunch(onboardingCompleted: false)
        XCTAssertEqual(backend.registerCalls, 0)
        XCTAssertEqual(backend.unregisterCalls, 0)
        XCTAssertNil(store.launchAtLoginIntent)
    }

    func testUnsetIntentAndNotRegisteredRegisters() {
        let (service, backend, _) = makeService(intent: nil, status: .notRegistered)
        service.reconcileAtLaunch(onboardingCompleted: true)
        XCTAssertEqual(backend.registerCalls, 1)
        XCTAssertEqual(service.status, .enabled)
    }

    func testIntentOnAndEnabledDoesNothing() {
        let (service, backend, _) = makeService(intent: true, status: .enabled)
        service.reconcileAtLaunch(onboardingCompleted: true)
        XCTAssertEqual(backend.registerCalls, 0)
        XCTAssertEqual(backend.unregisterCalls, 0)
    }

    func testIntentOnAndRequiresApprovalDoesNothing() {
        let (service, backend, _) = makeService(intent: true, status: .requiresApproval)
        service.reconcileAtLaunch(onboardingCompleted: true)
        XCTAssertEqual(backend.registerCalls, 0)
        XCTAssertEqual(service.status, .requiresApproval)
    }

    func testIntentOffButEnabledAdoptsSystemState() {
        let (service, backend, store) = makeService(intent: false, status: .enabled)
        service.reconcileAtLaunch(onboardingCompleted: true)
        XCTAssertEqual(store.launchAtLoginIntent, true)
        XCTAssertEqual(backend.registerCalls, 0)
        XCTAssertEqual(backend.unregisterCalls, 0)
    }

    func testIntentOffAndNotRegisteredDoesNothing() {
        let (service, backend, store) = makeService(intent: false, status: .notRegistered)
        service.reconcileAtLaunch(onboardingCompleted: true)
        XCTAssertEqual(store.launchAtLoginIntent, false)
        XCTAssertEqual(backend.registerCalls, 0)
    }

    // MARK: setEnabled

    func testSetEnabledFailureKeepsRealStatus() {
        let (service, backend, store) = makeService(intent: false, status: .notRegistered)
        backend.registerError = NSError(domain: "SMAppServiceErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])

        service.setEnabled(true)

        XCTAssertEqual(service.lastError, "Operation not permitted")
        XCTAssertEqual(service.status, .notRegistered, "UI must show the real status, not the request")
        XCTAssertEqual(store.launchAtLoginIntent, true)
    }

    func testSetEnabledSuccessClearsError() {
        let (service, backend, _) = makeService(intent: false, status: .notRegistered)
        backend.registerError = NSError(domain: "x", code: 1)
        service.setEnabled(true)
        XCTAssertNotNil(service.lastError)

        backend.registerError = nil
        service.setEnabled(true)
        XCTAssertNil(service.lastError)
        XCTAssertEqual(service.status, .enabled)
    }

    func testSetDisabledUnregisters() {
        let (service, backend, store) = makeService(intent: true, status: .enabled)
        service.setEnabled(false)
        XCTAssertEqual(backend.unregisterCalls, 1)
        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertEqual(store.launchAtLoginIntent, false)
    }

    func testRefreshReadsSystemStatus() {
        let (service, backend, _) = makeService(intent: true, status: .enabled)
        backend.status = .requiresApproval
        service.refresh()
        XCTAssertEqual(service.status, .requiresApproval)
    }

    func testOpenSystemSettings() {
        let (service, backend, _) = makeService(intent: nil, status: .notFound)
        service.openSystemSettings()
        XCTAssertEqual(backend.openSettingsCalls, 1)
    }

    // MARK: isRunningFromApplications

    func testIsRunningFromApplications() {
        func check(_ path: String) -> Bool {
            LoginItemService.isInApplications(bundleURL: URL(fileURLWithPath: path), homeDirectory: home)
        }
        XCTAssertTrue(check("/Applications/Verborra.app"))
        XCTAssertTrue(check("/Users/tester/Applications/Verborra.app"))
        XCTAssertFalse(check("/Users/tester/Downloads/Verborra.app"))
        XCTAssertFalse(check("/Users/tester/Library/Developer/Xcode/DerivedData/Verborra-abc/Build/Products/Debug/Verborra.app"))
        XCTAssertFalse(check("/ApplicationsBackup/Verborra.app"))
    }
}
