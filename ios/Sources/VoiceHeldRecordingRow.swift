#if os(iOS)
import SwiftUI

/// The inline surface shown while the finger is held down recording: a live recording
/// indicator, active elapsed time, a leading cancel destination that is visible at rest,
/// and a live waveform. The lock rail floats separately, above the microphone anchor.
struct VoiceHeldRecordingRow: View {
    let elapsed: TimeInterval
    let samples: [Float]
    let gesture: VoiceGesturePhase

    var body: some View {
        HStack(spacing: 10) {
            RecordingIndicatorDot()
            Text(VoiceDurationText.clock(elapsed))
                .font(.callout.monospacedDigit().weight(.semibold))
                .frame(minWidth: 44, alignment: .leading)
                .accessibilityLabel("Recording, \(VoiceDurationText.spoken(elapsed))")

            VoiceCancelTrack(fraction: gesture.cancelFraction, armed: gesture.isCancelArmed)

            Spacer(minLength: 4)

            VoiceWaveformView(samples: samples, tint: .accentColor)
                .frame(width: 80)
        }
        .padding(.leading, 6)
        .frame(minHeight: 40)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-recording-panel")
    }
}

/// Live red dot; pulses unless Reduce Motion is on.
struct RecordingIndicatorDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 9, height: 9)
            .opacity(reduceMotion ? 1 : (dim ? 0.35 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
            .accessibilityHidden(true)
    }
}
#endif
