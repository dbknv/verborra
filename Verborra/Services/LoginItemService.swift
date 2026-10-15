import Foundation
import Observation
import ServiceManagement

// MARK: - LoginItemStatus (spec 015, T036)

/// Реальное состояние login item в системе (зеркало `SMAppService.Status`).
enum LoginItemStatus: String {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound

    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        case .notRegistered: self = .notRegistered
        @unknown default: self = .notRegistered
        }
    }
}

// MARK: - LoginItemBackend

/// Тонкая обёртка над `SMAppService.mainApp`, чтобы тесты могли подставить фейк.
protocol LoginItemBackend {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

struct SMAppServiceLoginItemBackend: LoginItemBackend {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettingsLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}

// MARK: - LoginItemIntentStore

/// Где хранится намерение пользователя (`nil` — ещё не выбирал). В приложении — `AppSettings`.
@MainActor
protocol LoginItemIntentStore: AnyObject {
    var launchAtLoginIntent: Bool? { get set }
}

extension AppSettings: LoginItemIntentStore {}

// MARK: - LoginItemServiceProtocol (contracts/login-item.md)

@MainActor
protocol LoginItemServiceProtocol: AnyObject {
    var status: LoginItemStatus { get }
    var lastError: String? { get }
    var isRunningFromApplications: Bool { get }
    var appFolderPath: String { get }
    func refresh()
    func setEnabled(_ enabled: Bool)
    func reconcileAtLaunch(onboardingCompleted: Bool)
    func openSystemSettings()
}

// MARK: - LoginItemService

/// Единственное место, где приложение обращается к `SMAppService` (FR-001…FR-006).
/// Источник правды — система: UI показывает `status`, а не сохранённое намерение.
@MainActor
@Observable
final class LoginItemService: LoginItemServiceProtocol {
    private(set) var status: LoginItemStatus
    private(set) var lastError: String?
    let isRunningFromApplications: Bool
    /// Папка, из которой запущена эта копия приложения (для подсказки в настройках).
    let appFolderPath: String

    @ObservationIgnored private let backend: LoginItemBackend
    @ObservationIgnored private let intentStore: LoginItemIntentStore
    @ObservationIgnored private let appPath: String
    @ObservationIgnored private let log = DiagnosticLogger.logger(for: .loginItem)

    init(
        intentStore: LoginItemIntentStore,
        backend: LoginItemBackend = SMAppServiceLoginItemBackend(),
        bundleURL: URL = Bundle.main.bundleURL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.intentStore = intentStore
        self.backend = backend
        self.appPath = bundleURL.path
        self.appFolderPath = bundleURL.deletingLastPathComponent().path
        self.isRunningFromApplications = Self.isInApplications(bundleURL: bundleURL, homeDirectory: homeDirectory)
        self.status = LoginItemStatus(backend.status)
    }

    func refresh() {
        status = LoginItemStatus(backend.status)
    }

    func setEnabled(_ enabled: Bool) {
        let old = intentStore.launchAtLoginIntent
        let statusBefore = LoginItemStatus(backend.status)
        intentStore.launchAtLoginIntent = enabled
        do {
            if enabled {
                try backend.register()
            } else {
                try backend.unregister()
            }
            lastError = nil
            refresh()
            log.info("Launch at login changed", metadata: [
                "old": old.map { "\($0)" } ?? "unset",
                "new": "\(enabled)",
                "statusBefore": statusBefore.rawValue,
                "statusAfter": status.rawValue
            ])
        } catch {
            refresh()
            lastError = error.localizedDescription
            log.error(
                "Launch at login change failed",
                parameters: [
                    "enabled": "\(enabled)",
                    "status": status.rawValue,
                    "error": error.localizedDescription
                ],
                errorCode: (error as NSError).code.description
            )
        }
    }

    func reconcileAtLaunch(onboardingCompleted: Bool) {
        refresh()
        let intent = intentStore.launchAtLoginIntent
        let intentDescription = intent.map { $0 ? "on" : "off" } ?? "unset"
        var action = "none"
        defer {
            log.info("Login item reconcile", metadata: [
                "appPath": appPath,
                "status": status.rawValue,
                "intent": intentDescription,
                "action": action
            ])
        }

        guard onboardingCompleted else {
            log.debug("Login item reconcile skipped: onboarding not completed")
            return
        }

        if intent ?? true {
            switch status {
            case .enabled:
                log.info("Login item OK")
            case .notRegistered, .notFound:
                action = "register"
                do {
                    try backend.register()
                    refresh()
                    log.info("Login item registered at launch", metadata: ["status": status.rawValue])
                } catch {
                    refresh()
                    lastError = error.localizedDescription
                    log.error(
                        "Login item register failed",
                        parameters: ["status": status.rawValue, "error": error.localizedDescription],
                        errorCode: (error as NSError).code.description
                    )
                }
            case .requiresApproval:
                log.info("Login item requires approval")
            }
        } else if status == .enabled {
            // Пользователь включил в System Settings — система важнее сохранённого намерения.
            action = "adoptSystemState"
            intentStore.launchAtLoginIntent = true
            log.info("Login item enabled externally")
        } else {
            log.debug("Login item off by user choice", metadata: ["status": status.rawValue])
        }
    }

    func openSystemSettings() {
        backend.openSystemSettingsLoginItems()
    }

    // MARK: - Private

    static func isInApplications(bundleURL: URL, homeDirectory: URL) -> Bool {
        let path = bundleURL.standardizedFileURL.path
        let userApplications = homeDirectory.standardizedFileURL.appendingPathComponent("Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }
}
