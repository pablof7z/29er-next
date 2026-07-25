#if os(iOS)
import SwiftUI

/// The locked recording bar a single mic tap lands in, styled after the reference:
/// cancel (✕) · live waveform + elapsed · stop (◼) · send (↑). Every actionable control
/// is at least 44×44 points, and conflicting actions are disabled while finalizing or
/// publishing so repeated taps cannot duplicate a send. "Stop" finalizes into the review
/// card (playback before sending); "send" publishes immediately.
struct VoiceLockedToolbar: View {
    let elapsed: TimeInterval
    let samples: [Float]
    let isBusy: Bool
    let onCancel: () -> Void
    let onStop: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            cancelButton
            statusColumn
            stopButton
            sendButton
        }
        .padding(.leading, 2)
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-locked-toolbar")
    }

    /// Neutral ✕ that discards the recording — matches the reference's cancel affordance.
    private var cancelButton: some View {
        Button(role: .destructive, action: onCancel) {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.14), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Cancel recording")
        .accessibilityIdentifier("voice-delete")
    }

    private var statusColumn: some View {
        HStack(spacing: 8) {
            Text(VoiceDurationText.clock(elapsed))
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .leading)
            VoiceWaveformView(samples: samples, tint: .accentColor)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording")
        .accessibilityValue(VoiceDurationText.spoken(elapsed))
    }

    /// Filled ◼ that stops recording into the review card before sending.
    private var stopButton: some View {
        Button(action: onStop) {
            Image(systemName: "stop.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.14), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Stop and review recording")
        .accessibilityIdentifier("voice-stop")
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Group {
                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 40, height: 40)
            .background(Color.accentColor, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Send voice message")
        .accessibilityIdentifier("voice-send")
    }
}
#endif
