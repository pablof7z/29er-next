#if os(iOS)
import SwiftUI

/// A physical-feeling vertical lock destination floating above the microphone. The rail
/// stays visible while the finger is neutral; the lock glyph rises continuously with
/// `fraction` and snaps to a closed padlock once `armed`. Progress is communicated by
/// position, fill, and open/closed state — never color alone — and honors Reduce Motion.
struct VoiceLockRail: View {
    let fraction: Double
    let armed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let railHeight: CGFloat = 92
    private let knobSize: CGFloat = 40

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    Capsule().strokeBorder(
                        (armed ? Color.accentColor : Color.primary.opacity(0.18)),
                        lineWidth: armed ? 2 : 1
                    )
                )
                .frame(width: knobSize + 8, height: railHeight)

            Image(systemName: "chevron.up")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
                .opacity(armed ? 0 : 1 - fraction)
                .frame(width: knobSize + 8, height: railHeight, alignment: .top)
                .padding(.top, 8)

            knob
                .offset(y: -knobTravel)
        }
        .frame(width: knobSize + 8, height: railHeight)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.25, dampingFraction: 0.8), value: fraction)
        .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.7), value: armed)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("voice-lock-rail")
        .accessibilityLabel("Lock hands-free recording")
        .accessibilityValue("\(Int((armed ? 1 : fraction) * 100)) percent")
        .accessibilityAddTraits(armed ? .isSelected : [])
    }

    private var knob: some View {
        Image(systemName: armed ? "lock.fill" : "lock.open.fill")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(armed ? Color.white : Color.accentColor)
            .frame(width: knobSize, height: knobSize)
            .background(
                Circle().fill(armed ? Color.accentColor : Color(.secondarySystemBackground))
            )
            .overlay(Circle().strokeBorder(Color.accentColor.opacity(armed ? 0 : 0.4), lineWidth: 1))
            .scaleEffect(armed ? 1.08 : 1)
    }

    /// The knob climbs from the bottom of the rail toward the top as fraction grows.
    private var knobTravel: CGFloat {
        let available = railHeight - knobSize - 6
        return available * CGFloat(armed ? 1 : min(1, max(0, fraction)))
    }
}
#endif
