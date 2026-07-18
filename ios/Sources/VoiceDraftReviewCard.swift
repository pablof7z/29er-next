#if os(iOS)
import SwiftUI

/// The voice-specific finalized-draft surface. Replaces the generic filename + byte-count
/// attachment card: play/pause preview, duration, progress-tinted waveform, delete, and a
/// send-or-retry primary action. Never exposes the generated UUID filename.
struct VoiceDraftReviewCard: View {
    let draft: VoiceDraft
    let isBusy: Bool
    let failureMessage: String?
    let onDelete: () -> Void
    let onPrimary: () -> Void

    @StateObject private var player = VoiceDraftPlayer()

    private var isRetry: Bool { failureMessage != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                playButton
                waveform
                Text(remainingLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .trailing)
                deleteButton
                primaryButton
            }
            if let failureMessage {
                Text(failureMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .accessibilityIdentifier("voice-draft-error")
            }
        }
        .padding(.leading, 6)
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-draft-card")
        .onDisappear { player.stop() }
        .onChange(of: draft.url) { _, _ in player.stop() }
    }

    private var playButton: some View {
        Button {
            player.toggle(url: draft.url, duration: draft.duration)
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.14), in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.isPlaying ? "Pause preview" : "Play preview")
        .accessibilityValue("\(Int(player.progress * 100)) percent")
        .accessibilityIdentifier("voice-preview-toggle")
    }

    private var waveform: some View {
        VoiceWaveformView(
            samples: draft.waveform,
            progress: player.isPlaying || player.progress > 0 ? player.progress : 0,
            tint: .accentColor
        )
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: onDelete) {
            Image(systemName: "trash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Delete voice message")
        .accessibilityIdentifier("voice-delete")
    }

    private var primaryButton: some View {
        Button(action: onPrimary) {
            Group {
                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: isRetry ? "arrow.clockwise" : "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color.accentColor, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(isRetry ? "Retry sending voice message" : "Send voice message")
        .accessibilityIdentifier(isRetry ? "voice-retry" : "voice-send")
    }

    /// Counts down remaining preview time while playing, otherwise shows total length.
    private var remainingLabel: String {
        let played = player.progress * draft.duration
        let value = player.isPlaying ? max(0, draft.duration - played) : draft.duration
        return VoiceDurationText.clock(value)
    }
}
#endif
