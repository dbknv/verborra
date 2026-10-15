import AppKit
import SwiftUI

// MARK: - OverlayPanel

final class OverlayPanel: NSPanel {
    private var hostingView: NSHostingView<AnyView>?

    /// Fixed pre-recording size (spec 015, FR-065): 200 pt fits the recording layout and the tallest
    /// pre-recording view ("no microphone access", 154 pt) above the 45 pt bottom bar.
    static let initialSize = NSSize(width: 800, height: 200)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.initialSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        level = .floating
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
    }

    func show(with view: some View) {
        let hostingView = NSHostingView(rootView: AnyView(view))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        contentView = hostingView
        self.hostingView = hostingView

        setContentSize(Self.initialSize)
        positionOnScreen()
        orderFrontRegardless()
        makeKey()
    }

    func dismiss() {
        orderOut(nil)
        hostingView = nil
        contentView = nil
    }

    func positionOnScreen() {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let panelSize = frame.size

        // Center horizontally
        var x = visibleFrame.origin.x + (visibleFrame.width - panelSize.width) / 2
        // 2% from bottom of visible area
        var y = visibleFrame.origin.y + visibleFrame.height * 0.02

        // Clamp to visible frame
        x = max(visibleFrame.origin.x, min(x, visibleFrame.maxX - panelSize.width))
        y = max(visibleFrame.origin.y, min(y, visibleFrame.maxY - panelSize.height))

        setFrame(NSRect(origin: NSPoint(x: x, y: y), size: panelSize), display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - OverlayManager

@Observable
final class OverlayManager {
    private var panel: OverlayPanel?
    private var keyMonitor: Any?
    private(set) var currentHeight: CGFloat = OverlayPanel.initialSize.height
    private var debounceTask: Task<Void, Never>?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    var maxAllowedHeight: CGFloat {
        guard let screen = panel?.screen ?? NSScreen.main else {
            return OverlayPanel.initialSize.height
        }
        return screen.visibleFrame.height * 0.5
    }

    func show(with view: some View) {
        if panel == nil {
            panel = OverlayPanel()
        }
        currentHeight = OverlayPanel.initialSize.height
        panel?.show(with: view)
    }

    func dismiss() {
        debounceTask?.cancel()
        removeKeyMonitor()
        panel?.dismiss()
    }

    /// Overlay keys (1-2-3, ⌥C, Esc…) apply only to events aimed at the overlay panel, so they
    /// never intercept typing in Settings or other windows (spec 015, FR-020).
    func installKeyMonitor(_ handler: @escaping (NSEvent) -> Bool) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let panel = self?.panel, event.window === panel else { return event }
            return handler(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    func updateHeight(_ newHeight: CGFloat) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self.performHeightUpdate(newHeight)
        }
    }

    func resetToInitialSize() {
        performHeightUpdate(OverlayPanel.initialSize.height)
    }

    private func performHeightUpdate(_ newHeight: CGFloat) {
        guard let panel else { return }

        let clampedHeight = min(max(newHeight, OverlayPanel.initialSize.height), maxAllowedHeight)
        guard abs(clampedHeight - currentHeight) > 1 else { return }

        var newFrame = panel.frame
        // origin.y stays the same — window grows upward (macOS coords)
        newFrame.size.height = clampedHeight

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true, animate: true)
        }

        currentHeight = clampedHeight
    }
}
