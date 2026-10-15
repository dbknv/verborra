import Atomics
import CoreGraphics
import Foundation
import os

// MARK: - FnTracker (spec 015, T070)

/// Tracks whether Fn/Globe is physically held. macOS also sets `.maskSecondaryFn` on arrow,
/// F-key and Home/End events, so that flag alone can't tell an Fn shortcut apart (research R6).
struct FnTracker {
    private(set) var fnHeld = false

    /// Fn (63) and Globe (179) key codes.
    static let fnKeyCodes: Set<UInt16> = [63, 179]

    mutating func handleFlagsChanged(keyCode: UInt16, flags: CGEventFlags) {
        guard Self.fnKeyCodes.contains(keyCode) else { return }
        fnHeld = flags.contains(.maskSecondaryFn)
    }

    /// Same as above, for AppKit events in the recorder field.
    mutating func handleFlagsChanged(keyCode: UInt16, fnFlag: Bool) {
        guard Self.fnKeyCodes.contains(keyCode) else { return }
        fnHeld = fnFlag
    }

    func effectiveModifiers(for flags: CGEventFlags) -> ShortcutModifiers {
        var modifiers = ShortcutModifiers(cgFlags: flags)
        if fnHeld { modifiers.insert(.fn) }
        return modifiers
    }

    mutating func reset() {
        fnHeld = false
    }
}

// MARK: - FnEventTap (spec 015, T072)

/// Global listener for shortcuts that include Fn (Carbon hotkeys can't express Fn).
/// Runs a `CGEventTap` on its own thread and run loop, so a busy main thread can't make macOS
/// disable the tap. Needs Accessibility. Never logs or stores keys of non-matching events.
final class FnEventTap: @unchecked Sendable {
    private let target: OSAllocatedUnfairLock<GlobalShortcut>
    private let paused = ManagedAtomic<Bool>(false)
    private let onMatch: @Sendable () -> Void
    private let log = DiagnosticLogger.logger(for: .hotkey)

    // Touched only on the tap thread (after start)
    private var tracker = FnTracker()
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    init(shortcut: GlobalShortcut, onMatch: @escaping @Sendable () -> Void) {
        self.target = OSAllocatedUnfairLock(initialState: shortcut)
        self.onMatch = onMatch
    }

    var isPaused: Bool {
        get { paused.load(ordering: .relaxed) }
        set { paused.store(newValue, ordering: .relaxed) }
    }

    func update(shortcut: GlobalShortcut) {
        target.withLock { $0 = shortcut }
    }

    /// Creates the tap and starts its thread. Returns `false` if macOS refused (no Accessibility).
    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<FnEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            return false
        }
        machPort = port
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)

        let started = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { started.signal(); return }
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            started.signal()
            CFRunLoopRun()
        }
        thread.name = "dev.apeek.verborra.fn-tap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        started.wait()
        return true
    }

    func stop() {
        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let runLoop {
            if let source = runLoopSource {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            CFRunLoopStop(runLoop)
        }
        machPort = nil
        runLoopSource = nil
        runLoop = nil
        thread = nil
    }

    // MARK: - Tap thread

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port = machPort {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            log.info("Event tap re-enabled", metadata: [
                "reason": type == .tapDisabledByTimeout ? "timeout" : "userInput"
            ])
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            tracker.handleFlagsChanged(keyCode: keyCode, flags: event.flags)
            return Unmanaged.passUnretained(event)

        case .keyDown:
            guard !paused.load(ordering: .relaxed),
                  event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
                return Unmanaged.passUnretained(event)
            }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let shortcut = target.withLock { $0 }
            guard keyCode == shortcut.keyCode,
                  tracker.effectiveModifiers(for: event.flags) == shortcut.modifiers else {
                return Unmanaged.passUnretained(event)
            }
            let onMatch = self.onMatch
            DispatchQueue.main.async { onMatch() }
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
