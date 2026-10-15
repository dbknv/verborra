import ApplicationServices
import Foundation
import KeyboardShortcuts
import Observation

// MARK: - KeyboardShortcuts Name Extension

extension KeyboardShortcuts.Name {
    static let toggleOverlay = Self("toggleOverlay", default: .init(.space, modifiers: .option))
}

// MARK: - HotkeyRegistrationStatus (spec 015, T073)

enum HotkeyRegistrationStatus: Equatable {
    enum Mechanism: String {
        case carbon
        case eventTap
    }

    case active(Mechanism)
    case needsAccessibility
    case failed(String)
    case paused
}

// MARK: - GlobalHotkeyServiceProtocol (contracts/global-shortcut.md)

@MainActor
protocol GlobalHotkeyServiceProtocol: AnyObject {
    var shortcut: GlobalShortcut { get }
    var status: HotkeyRegistrationStatus { get }
    var isPaused: Bool { get set }
    func start(onToggle: @escaping @MainActor () -> Void)
    func validate(_ candidate: GlobalShortcut) -> ShortcutValidationResult
    func apply(_ candidate: GlobalShortcut) -> ShortcutValidationResult
    func resetToDefault()
    func stop()
}

// MARK: - GlobalHotkeyService

/// The global shortcut that opens the floating window. Shortcuts without Fn use Carbon
/// (via KeyboardShortcuts, no permission needed); shortcuts with Fn use `FnEventTap`
/// (needs Accessibility). Only one mechanism is ever active.
@MainActor
@Observable
final class GlobalHotkeyService: GlobalHotkeyServiceProtocol {
    private(set) var status: HotkeyRegistrationStatus = .paused
    /// The last rejection, shown under the recorder field.
    private(set) var lastRejection: ShortcutRejection?

    var shortcut: GlobalShortcut { store.current }

    var isPaused: Bool = false {
        didSet {
            guard isPaused != oldValue else { return }
            applyPause()
        }
    }

    @ObservationIgnored private let store: GlobalShortcutStore
    @ObservationIgnored private let validator: ShortcutValidator
    @ObservationIgnored private var fnTap: FnEventTap?
    @ObservationIgnored private var onToggle: (@MainActor () -> Void)?
    @ObservationIgnored private var didInstallCarbonHandler = false
    @ObservationIgnored private var mechanism: HotkeyRegistrationStatus.Mechanism = .carbon
    @ObservationIgnored private let log = DiagnosticLogger.logger(for: .hotkey)
    @ObservationIgnored private let logUserAction = DiagnosticLogger.logger(for: .userAction)

    init(store: GlobalShortcutStore? = nil, validator: ShortcutValidator = ShortcutValidator()) {
        self.store = store ?? .shared
        self.validator = validator
    }

    func start(onToggle: @escaping @MainActor () -> Void) {
        self.onToggle = onToggle
        register()
        observeAccessibility()
    }

    func stop() {
        KeyboardShortcuts.disable(.toggleOverlay)
        fnTap?.stop()
        fnTap = nil
    }

    func validate(_ candidate: GlobalShortcut) -> ShortcutValidationResult {
        validator.validate(candidate, current: store.current)
    }

    @discardableResult
    func apply(_ candidate: GlobalShortcut) -> ShortcutValidationResult {
        let result = validate(candidate)
        switch result {
        case .rejected(let rejection):
            lastRejection = rejection
            log.info("Global shortcut rejected", metadata: [
                "candidate": ShortcutFormatter.string(candidate),
                "reason": rejection.rawValue
            ])
        case .ok:
            lastRejection = nil
            let old = store.current
            store.save(candidate)
            register()
            log.info("Global shortcut changed", metadata: [
                "old": ShortcutFormatter.string(old),
                "new": ShortcutFormatter.string(candidate),
                "mechanism": mechanism.rawValue
            ])
        }
        return result
    }

    func resetToDefault() {
        apply(.default)
    }

    // MARK: - Registration

    /// Tears down both mechanisms, then sets up the one the current shortcut needs.
    func register() {
        fnTap?.stop()
        fnTap = nil
        let current = store.current

        if current.requiresEventTap {
            mechanism = .eventTap
            KeyboardShortcuts.setShortcut(nil, for: .toggleOverlay)
            let tap = FnEventTap(shortcut: current) { [weak self] in
                Task { @MainActor in self?.fire() }
            }
            tap.isPaused = isPaused
            if tap.start() {
                fnTap = tap
                status = isPaused ? .paused : .active(.eventTap)
            } else if !AXIsProcessTrusted() {
                status = .needsAccessibility
                logRegistrationFailure(current, error: "accessibility not granted")
            } else {
                status = .failed("CGEvent.tapCreate returned nil")
                logRegistrationFailure(current, error: "tapCreate returned nil")
            }
        } else {
            mechanism = .carbon
            KeyboardShortcuts.setShortcut(
                .init(carbonKeyCode: Int(current.keyCode), carbonModifiers: current.modifiers.carbonFlags),
                for: .toggleOverlay
            )
            if !didInstallCarbonHandler {
                didInstallCarbonHandler = true
                KeyboardShortcuts.onKeyDown(for: .toggleOverlay) { [weak self] in
                    Task { @MainActor in self?.fire() }
                }
            }
            if isPaused {
                KeyboardShortcuts.disable(.toggleOverlay)
                status = .paused
            } else {
                KeyboardShortcuts.enable(.toggleOverlay)
                status = .active(.carbon)
            }
        }
    }

    // MARK: - Private

    private func fire() {
        guard !isPaused else { return }
        logUserAction.info("Hotkey triggered", metadata: ["mechanism": mechanism.rawValue])
        onToggle?()
    }

    private func applyPause() {
        switch mechanism {
        case .carbon:
            if isPaused {
                KeyboardShortcuts.disable(.toggleOverlay)
            } else {
                KeyboardShortcuts.enable(.toggleOverlay)
            }
        case .eventTap:
            fnTap?.isPaused = isPaused
        }
        if isPaused {
            status = .paused
        } else if case .paused = status {
            status = mechanism == .eventTap && fnTap == nil ? .needsAccessibility : .active(mechanism)
        }
    }

    private func logRegistrationFailure(_ shortcut: GlobalShortcut, error: String) {
        log.error(
            "Global shortcut registration failed",
            parameters: [
                "shortcut": ShortcutFormatter.string(shortcut),
                "mechanism": mechanism.rawValue,
                "error": error
            ],
            errorCode: "hotkeyRegistrationFailed"
        )
    }

    /// Re-registers the Fn tap once Accessibility is granted.
    private func observeAccessibility() {
        withObservationTracking {
            _ = PermissionManager.shared.accessibilityStatus
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if PermissionManager.shared.accessibilityStatus == .granted, self.status == .needsAccessibility {
                    self.register()
                }
                self.observeAccessibility()
            }
        }
    }
}
