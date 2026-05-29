import SwiftUI

// MARK: - AudioWaveformView (014)
//
// Container-relative voice level indicator. The component reads its container's
// vertical budget via GeometryReader and scales bar heights as a fraction of
// that height (90% slack at the top so saturated bursts do not visually clip).
// Amplitude is shaped by a square-root curve (`pow(level, 0.5)`) applied at the
// view layer so conversational input visibly fills the available space without
// touching the underlying audio pipeline. The 0.1 s easeOut animation is
// preserved — it provides interpolation between consecutive ~20 Hz publish
// frames without introducing perceptible lag.

struct AudioWaveformView: View {
    let audioLevel: Float
    private let barCount = 30
    /// Vertical headroom factor inside the container. Bars never exceed this
    /// fraction of the available height, keeping a small visual slack at the
    /// top so loud bursts saturate without clipping the container edge.
    private static let containerFillFactor: CGFloat = 0.9
    /// Intrinsic fallback height used when the parent does not assign one
    /// (geometry returns 0). Keeps the component renderable in degenerate
    /// layouts and matches the indicator's previous default footprint.
    private static let intrinsicFallbackHeight: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            let resolvedHeight = max(geometry.size.height, Self.intrinsicFallbackHeight)
            let maxBarHeight = resolvedHeight * Self.containerFillFactor
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: 0x9A9A9A))
                        .frame(height: barHeight(for: index, maxBarHeight: maxBarHeight))
                        .animation(.easeOut(duration: 0.1), value: audioLevel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(minHeight: Self.intrinsicFallbackHeight)
    }

    private func barHeight(for index: Int, maxBarHeight: CGFloat) -> CGFloat {
        let center = Double(barCount) / 2.0
        let distance = abs(Double(index) - center) / center
        // Square-root curve expands low-end amplitudes so conversational
        // speech reaches ≥50% of available height while preserving silence
        // (level == 0 → display == 0) and saturation (level == 1 → display == 1).
        let displayLevel = Self.mapAmplitude(audioLevel)
        let variation = sin(Double(index) * 0.8 + displayLevel * 10) * 0.3 + 0.7
        // Baseline keeps a small minimum so the indicator has visible identity
        // even at zero input — bounded at 10% of `maxBarHeight` per contract.
        let baseline = maxBarHeight * 0.1
        return baseline + (maxBarHeight - baseline) * displayLevel * (1.0 - distance * 0.5) * variation
    }

    /// Pure amplitude-mapping curve. Exposed as `static` so it can be unit
    /// tested directly (see `AudioAmplitudeMappingTests`).
    /// - Parameter level: linear audio level in `[0.0, 1.0]`. Out-of-range
    ///   values are clamped to the unit interval.
    /// - Returns: display amplitude in `[0.0, 1.0]` after applying the
    ///   `pow(level, 0.5)` curve.
    static func mapAmplitude(_ level: Float) -> Double {
        let clamped = max(0.0, min(1.0, Double(level)))
        return pow(clamped, 0.5)
    }
}
