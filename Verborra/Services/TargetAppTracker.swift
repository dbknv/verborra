import AppKit
import Foundation

// MARK: - TargetAppTracker

@Observable
final class TargetAppTracker {
    private(set) var targetPID: pid_t = 0
    private var observation: (any NSObjectProtocol)?
    private let log = DiagnosticLogger.logger(for: .system)

    func startTracking() {
        // Capture current frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetPID = frontmost.processIdentifier
            log.info("Target app captured", metadata: [
                "name": frontmost.localizedName ?? "unknown",
                "bundleId": frontmost.bundleIdentifier ?? "unknown"
            ])
        }

        observation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            self.targetPID = app.processIdentifier
        }
    }

    func stopTracking() {
        if let observation {
            NSWorkspace.shared.notificationCenter.removeObserver(observation)
        }
        observation = nil
        targetPID = 0
    }
}
