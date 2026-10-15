import CoreGraphics
import Testing
@testable import Verborra

// MARK: - FnTrackingTests (spec 015, T068)

struct FnTrackingTests {

    @Test func fnHeldThenSpace() {
        var tracker = FnTracker()
        tracker.handleFlagsChanged(keyCode: 63, flags: .maskSecondaryFn)
        #expect(tracker.effectiveModifiers(for: []) == [.fn])
    }

    @Test(arguments: [UInt16(126), 96, 115])
    func secondaryFnBitAloneIsNotFn(keyCode: UInt16) {
        // ↑, F5 and Home report .maskSecondaryFn without Fn being pressed
        let tracker = FnTracker()
        #expect(tracker.effectiveModifiers(for: .maskSecondaryFn) == [])
    }

    @Test func fnReleased() {
        var tracker = FnTracker()
        tracker.handleFlagsChanged(keyCode: 63, flags: .maskSecondaryFn)
        tracker.handleFlagsChanged(keyCode: 63, flags: [])
        #expect(tracker.effectiveModifiers(for: []) == [])
    }

    @Test func fnWithControlAndOption() {
        var tracker = FnTracker()
        tracker.handleFlagsChanged(keyCode: 63, flags: .maskSecondaryFn)
        #expect(tracker.effectiveModifiers(for: [.maskControl, .maskAlternate, .maskSecondaryFn]) == [.fn, .control, .option])
    }

    @Test func globeKeyCodeBehavesLikeFn() {
        var tracker = FnTracker()
        tracker.handleFlagsChanged(keyCode: 179, flags: .maskSecondaryFn)
        #expect(tracker.fnHeld)
        tracker.handleFlagsChanged(keyCode: 179, flags: [])
        #expect(!tracker.fnHeld)
    }

    @Test func otherModifierKeysDontChangeFn() {
        var tracker = FnTracker()
        tracker.handleFlagsChanged(keyCode: 58, flags: [.maskAlternate, .maskSecondaryFn])
        #expect(!tracker.fnHeld)
    }
}
