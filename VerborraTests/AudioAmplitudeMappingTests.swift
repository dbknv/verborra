import XCTest
@testable import Verborra

// MARK: - AudioWaveformView amplitude curve tests (014, T011)
//
// Pure-function tests for `AudioWaveformView.mapAmplitude(_:)`. The curve is
// `pow(level, 0.5)` (square root) over a clamped `[0, 1]` input. The view's
// visual behavior is verified manually (T013) — these tests pin down the
// numeric contract.

final class AudioAmplitudeMappingTests: XCTestCase {

    func testSilenceMapsToZero() {
        XCTAssertEqual(AudioWaveformView.mapAmplitude(0.0), 0.0, accuracy: 1e-9)
    }

    func testSaturationMapsToOne() {
        XCTAssertEqual(AudioWaveformView.mapAmplitude(1.0), 1.0, accuracy: 1e-9)
    }

    func testConversationalLevelReachesAtLeast30Percent() {
        // FR-003 / SC-001: at typical conversational input (~level=0.10 from
        // the existing RMS pipeline) the curve should produce a clearly
        // visible deflection — pow(0.10, 0.5) ≈ 0.3162.
        let result = AudioWaveformView.mapAmplitude(0.10)
        XCTAssertGreaterThanOrEqual(result, 0.30,
                                    "Conversational level should map to ≥30% display amplitude")
        XCTAssertLessThanOrEqual(result, 0.34,
                                 "Conversational level should not over-saturate")
    }

    func testQuarterInputMapsToHalfDisplay() {
        // pow(0.25, 0.5) == 0.5 exactly. A useful pinned point for catching
        // accidental curve changes.
        XCTAssertEqual(AudioWaveformView.mapAmplitude(0.25), 0.5, accuracy: 1e-9)
    }

    func testCurveIsMonotonicNonDecreasing() {
        // Sweep the unit interval and assert each step is ≥ the previous.
        var previous: Double = -.infinity
        for raw in stride(from: 0.0, through: 1.0, by: 0.05) {
            let current = AudioWaveformView.mapAmplitude(Float(raw))
            XCTAssertGreaterThanOrEqual(current, previous,
                                        "Curve must be monotonic non-decreasing (raw=\(raw))")
            previous = current
        }
    }

    func testNegativeInputIsClampedToZero() {
        // Defensive: out-of-range inputs must not crash and must not produce
        // negative display amplitudes (would NaN under pow).
        XCTAssertEqual(AudioWaveformView.mapAmplitude(-0.5), 0.0, accuracy: 1e-9)
    }

    func testAboveOneInputIsClampedToOne() {
        XCTAssertEqual(AudioWaveformView.mapAmplitude(2.0), 1.0, accuracy: 1e-9)
    }
}
