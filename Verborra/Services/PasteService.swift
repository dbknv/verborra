import AppKit
import Foundation

// MARK: - PasteServiceProtocol

protocol PasteServiceProtocol {
    func pasteText(_ text: String) async throws
    func copyToClipboard(_ text: String)
    func copyPlainTextToClipboard(_ markdownText: String)
    func pastePlainText(_ markdownText: String) async throws
}

// MARK: - PasteService

final class PasteService: PasteServiceProtocol {
    private let targetPIDProvider: () -> pid_t
    private let log = DiagnosticLogger.logger(for: .system)

    init(targetPIDProvider: @escaping () -> pid_t) {
        self.targetPIDProvider = targetPIDProvider
    }

    // MARK: - Markdown Operations

    func pasteText(_ text: String) async throws {
        // FR-054: Copy to clipboard as fallback before attempting paste
        copyToClipboard(text)
        try await performPaste(text)
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Plain Text Operations

    func copyPlainTextToClipboard(_ markdownText: String) {
        let plainText = MarkdownStripper.stripMarkdown(markdownText)
        copyToClipboard(plainText)
    }

    func pastePlainText(_ markdownText: String) async throws {
        let plainText = MarkdownStripper.stripMarkdown(markdownText)
        // FR-054: Copy to clipboard as fallback before attempting paste
        copyToClipboard(plainText)
        try await performPaste(plainText)
    }

    // MARK: - Private

    private func performPaste(_ text: String) async throws {
        log.info("Paste attempted", metadata: ["method": "Cmd+V", "textLength": "\(text.count) chars"])

        guard PermissionManager.shared.accessibilityStatus == .granted else {
            log.error("Paste failed: accessibility not granted", errorCode: "accessibilityNotGranted")
            throw PasteError.accessibilityNotGranted
        }

        let pasteboard = NSPasteboard.general

        // Snapshot previous items
        let previousItems = snapshotPasteboardItems(pasteboard)
        let previousChangeCount = pasteboard.changeCount

        // Write text to pasteboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // FR-060—FR-062: Use targetPID from TargetAppTracker
        let targetPID = targetPIDProvider()

        guard targetPID > 0, NSRunningApplication(processIdentifier: targetPID) != nil else {
            throw PasteError.targetAppUnavailable
        }

        // Simulate Cmd+V
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw PasteError.eventSourceUnavailable
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)  // V key
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.postToPid(targetPID)
        keyUp?.postToPid(targetPID)

        // Restore pasteboard after delay
        try? await Task.sleep(for: .milliseconds(200))

        if pasteboard.changeCount == previousChangeCount + 1,
           !previousItems.isEmpty {
            pasteboard.clearContents()
            pasteboard.writeObjects(previousItems)
        }
    }

    private func snapshotPasteboardItems(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }
}

// MARK: - PasteError

enum PasteError: LocalizedError {
    case eventSourceUnavailable
    case accessibilityNotGranted
    case targetAppUnavailable

    var errorDescription: String? {
        let l10n = LocalizationManager.shared
        switch self {
        case .eventSourceUnavailable:
            return l10n.string("error.paste.eventSourceUnavailable")
        case .accessibilityNotGranted:
            return l10n.string("error.paste.accessibilityNotGranted")
        case .targetAppUnavailable:
            return l10n.string("error.paste.targetAppUnavailable")
        }
    }
}
