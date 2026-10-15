import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - ShortcutRecorderNSView (spec 015, T075)

/// Records a global shortcut: shows held modifiers live (FR-014), saves on the first regular key
/// (FR-016), cancels on Esc (FR-018) and supports Fn via `FnTracker`.
final class ShortcutRecorderNSView: NSView {
    var shortcut: GlobalShortcut = .default {
        didSet { if !isRecording { refresh() } }
    }
    var onCapture: (GlobalShortcut) -> ShortcutValidationResult = { _ in .ok }
    var onRecordingChanged: (Bool) -> Void = { _ in }

    private var tracker = FnTracker()
    private var heldModifiers: ShortcutModifiers = []
    private var hint: String?
    private var isRecording = false

    private let label = NSTextField(labelWithString: "")
    private let l10n = LocalizationManager.shared

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            heightAnchor.constraint(equalToConstant: 26)
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        tracker.reset()
        heldModifiers = []
        hint = nil
        onRecordingChanged(true)
        refresh()
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        tracker.reset()
        heldModifiers = []
        onRecordingChanged(false)
        refresh()
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        tracker.handleFlagsChanged(keyCode: event.keyCode, fnFlag: event.modifierFlags.contains(.function))
        heldModifiers = currentModifiers(event)
        hint = nil
        refresh()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        if event.keyCode == UInt16(kVK_Escape) && currentModifiers(event).isEmpty {
            window?.makeFirstResponder(nil)
            return
        }
        guard !event.isARepeat else { return }

        let modifiers = currentModifiers(event)
        guard !modifiers.isEmpty else {
            hint = ShortcutRejection.modifierRequired.message
            refresh()
            return
        }

        let candidate = GlobalShortcut(keyCode: event.keyCode, modifiers: modifiers)
        _ = onCapture(candidate)
        window?.makeFirstResponder(nil)
    }

    /// While recording, ⌘-combos must reach `keyDown` instead of triggering menu items.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    // MARK: - Private

    /// Modifiers from the event, with Fn only when Fn itself is held (not the secondaryFn bit of arrows/F-keys).
    private func currentModifiers(_ event: NSEvent) -> ShortcutModifiers {
        var modifiers = ShortcutModifiers(nsFlags: event.modifierFlags)
        modifiers.remove(.fn)
        if tracker.fnHeld { modifiers.insert(.fn) }
        return modifiers
    }

    private func refresh() {
        let text: String
        if isRecording {
            if let hint {
                text = hint
            } else if heldModifiers.isEmpty {
                text = l10n.string("shortcut.recorder.placeholder")
            } else {
                text = ShortcutFormatter.symbols(heldModifiers).joined(separator: " ")
            }
        } else {
            text = ShortcutFormatter.string(shortcut)
        }
        label.stringValue = text
        label.textColor = isRecording && heldModifiers.isEmpty ? .secondaryLabelColor : .labelColor
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }
}

// MARK: - ShortcutRecorderField

struct ShortcutRecorderField: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let onCapture: (GlobalShortcut) -> ShortcutValidationResult
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        update(nsView)
    }

    private func update(_ view: ShortcutRecorderNSView) {
        view.shortcut = shortcut
        view.onCapture = onCapture
        view.onRecordingChanged = onRecordingChanged
    }
}
