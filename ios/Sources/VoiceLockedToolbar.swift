#if os(iOS)
import SwiftUI

/// The deliberate locked control surface that replaces the held interaction once lock
/// commits: persistent delete, live indicator + elapsed + waveform, pause/resume, and
/// send. Every actionable control is at least 44×44 points, and conflicting actions are
/// disabled while finalizing/publishing so repeated taps cannot duplicate a send.
struct VoiceLockedToolbar: View {
    let elapsed: TimeInterval
    let samples: [Float]
    let isPaused: Bool
    let isBusy: Bool
    let onDelete: () -> Void
    let onPauseResume: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            deleteButton
            statusColumn
            pauseResumeButton
            sendButton
        }
        .padding(.leading, 4)
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-locked-toolbar")
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
        .accessibilityLabel("Delete recording")
        .accessibilityIdentifier("voice-delete")
    }

    private var statusColumn: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isPaused ? Color.secondary : Color.red)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            Text(VoiceDurationText.clock(elapsed))
                .font(.callout.monospacedDigit().weight(.semibold))
                .frame(minWidth: 44, alignment: .leading)
            VoiceWaveformView(samples: samples, tint: isPaused ? .secondary : .accentColor)
                .frame(maxWidth: .infinity)
                .opacity(isPaused ? 0.5 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPaused ? "Paused" : "Recording")
        .accessibilityValue(VoiceDurationText.spoken(elapsed))
    }

    private var pauseResumeButton: some View {
        Button(action: onPauseResume) {
            Image(systemName: isPaused ? "record.circle" : "pause.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isPaused ? Color.red : Color.accentColor)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(isPaused ? "Resume recording" : "Pause recording")
        .accessibilityIdentifier("voice-pause-resume")
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
            .frame(width: 44, height: 44)
            .background(Color.accentColor, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Send voice message")
        .accessibilityIdentifier("voice-send")
    }
}
#endif
