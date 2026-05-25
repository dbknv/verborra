import SwiftUI

// MARK: - AudioWaveformView

struct AudioWaveformView: View {
    let audioLevel: Float
    private let barCount = 30

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: 0x9A9A9A))
                    .frame(height: barHeight(for: index))
                    .animation(.easeOut(duration: 0.1), value: audioLevel)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let center = Double(barCount) / 2.0
        let distance = abs(Double(index) - center) / center
        let base = 4.0
        let maxHeight = 36.0
        let level = Double(audioLevel)
        let variation = sin(Double(index) * 0.8 + level * 10) * 0.3 + 0.7
        return base + (maxHeight - base) * level * (1.0 - distance * 0.5) * variation
    }
}
