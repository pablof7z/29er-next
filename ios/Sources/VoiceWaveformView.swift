import SwiftUI

/// Shared waveform bars for live capture and the review card. `progress` (0…1) tints the
/// played portion when previewing; pass 1 for the always-active recording meter.
struct VoiceWaveformView: View {
    let samples: [Float]
    var progress: Double = 1
    var tint: Color = .accentColor
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2
    var minHeight: CGFloat = 3
    var maxHeight: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let bars = max(1, Int((geo.size.width + spacing) / (barWidth + spacing)))
            let values = Self.resampled(samples, to: bars)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(values.indices, id: \.self) { index in
                    let played = Double(index) / Double(max(1, values.count - 1)) <= progress
                    Capsule()
                        .fill(tint.opacity(played ? 0.95 : 0.28))
                        .frame(
                            width: barWidth,
                            height: minHeight + CGFloat(values[index]) * (maxHeight - minHeight)
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: maxHeight)
        .accessibilityHidden(true)
    }

    /// Fit an arbitrary sample count into `count` bars without index-out-of-range on empty
    /// input; empty capture renders a flat idle baseline rather than nothing.
    static func resampled(_ samples: [Float], to count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !samples.isEmpty else { return Array(repeating: 0.08, count: count) }
        if samples.count == count { return samples.map { max(0, min(1, $0)) } }
        return (0..<count).map { index in
            let position = Double(index) / Double(count) * Double(samples.count)
            let clamped = min(samples.count - 1, max(0, Int(position)))
            return max(0, min(1, samples[clamped]))
        }
    }
}
