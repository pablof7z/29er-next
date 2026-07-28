#if os(iOS)
import SwiftUI

struct VoiceTranscriptionProgressCard: View {
    let draft: VoiceDraft
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(message)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    VoiceWaveformView(samples: draft.waveform, tint: .accentColor)
                        .frame(maxWidth: .infinity)
                    Text(VoiceDurationText.clock(draft.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(draft.accessibleTitle)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 52)
        .accessibilityIdentifier("voice-transcribing")
    }
}
#endif
