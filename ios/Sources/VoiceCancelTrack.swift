#if os(iOS)
import SwiftUI

/// The finger-held cancel destination on the leading edge. A trash target and directional
/// chevrons sit where the user can see them (never hidden under the recording finger).
/// `fraction` slides the trash toward its destination and fades the hint; at `armed` the
/// glyph changes shape and the whole target turns destructive with a single haptic upstream.
struct VoiceCancelTrack: View {
    let fraction: Double
    let armed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: armed ? "trash.fill" : "trash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(armed ? Color.red : Color.secondary)
                .scaleEffect(armed ? 1.15 : 1)
                .offset(x: slideOffset)

            if !armed {
                chevrons
                Text("slide to cancel")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .opacity(1 - fraction)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("Release to delete")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.85), value: fraction)
        .animation(reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.7), value: armed)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("voice-cancel-track")
        .accessibilityLabel("Cancel recording")
        .accessibilityValue("\(Int((armed ? 1 : fraction) * 100)) percent")
        .accessibilityAddTraits(armed ? .isSelected : [])
    }

    private var chevrons: some View {
        HStack(spacing: -2) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "chevron.compact.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary.opacity(0.35 + 0.2 * Double(3 - index)))
            }
        }
    }

    /// Trash drifts toward the leading edge as fraction grows (mirrored for RTL).
    private var slideOffset: CGFloat {
        let magnitude = CGFloat(min(1, max(0, fraction))) * 10
        return layoutDirection == .rightToLeft ? magnitude : -magnitude
    }
}
#endif
