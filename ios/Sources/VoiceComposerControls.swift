import SwiftUI

#if os(iOS)
struct VoiceComposerActionButton: View {
    @ObservedObject var recorder: VoiceMessageRecorder
    let showsMic: Bool
    let canSubmit: Bool
    let isSending: Bool
    let submit: () -> Void

    @State private var isTracking = false
    @State private var isCancelArmed = false

    var body: some View {
        Group {
            if showsMic || recorder.isActive {
                micButton
            } else {
                sendButton
            }
        }
        .frame(width: 36, height: 36)
        .contentShape(Rectangle())
    }

    private var micButton: some View {
        Image(systemName: recorder.isLocked ? "lock.fill" : "mic.fill")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(isCancelArmed ? Color.red : Color.accentColor, in: .circle)
            .scaleEffect(isTracking && !recorder.isLocked ? 1.12 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isTracking)
            .gesture(recordingGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(recorder.isActive ? "Recording voice message" : "Record voice message")
            .accessibilityHint("Press and hold to record. Slide up to lock or left to cancel.")
            .accessibilityAction(named: "Start recording") { recorder.begin() }
            .accessibilityAction(named: "Lock recording") { recorder.lock() }
            .accessibilityAction(named: "Send recording") { recorder.finishAndSend() }
            .accessibilityAction(named: "Cancel recording") { recorder.cancel() }
            .accessibilityIdentifier("room-message-mic")
    }

    private var sendButton: some View {
        Button(action: submit) {
            Group {
                if isSending {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(canSubmit ? .white : .secondary)
                }
            }
            .frame(width: 36, height: 36)
            .background(Color.accentColor.opacity(canSubmit ? 1 : 0.12), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isSending)
        .accessibilityLabel("Send message")
        .accessibilityIdentifier("room-message-send")
    }

    private var recordingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isTracking {
                    isTracking = true
                    recorder.begin()
                }
                if value.translation.height < -64 {
                    recorder.lock()
                }
                isCancelArmed = value.translation.width < -86 && !recorder.isLocked
            }
            .onEnded { _ in
                defer {
                    isTracking = false
                    isCancelArmed = false
                }
                if isCancelArmed {
                    recorder.cancel()
                } else if !recorder.isLocked {
                    recorder.finishAndSend()
                }
            }
    }
}

struct VoiceRecordingPanel: View {
    @ObservedObject var recorder: VoiceMessageRecorder

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text(Self.timeLabel(recorder.duration))
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 42, alignment: .leading)
            waveform
            if recorder.isLocked {
                Button("Cancel", role: .destructive) { recorder.cancel() }
                    .font(.caption.weight(.semibold))
                Button { recorder.finishAndSend() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Send voice message")
            } else {
                Label("Slide up to lock", systemImage: "chevron.up")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-recording-panel")
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(recorder.samples.enumerated()), id: \.offset) { _, sample in
                Capsule()
                    .fill(Color.accentColor.opacity(0.55 + Double(sample) * 0.45))
                    .frame(width: 2, height: 4 + CGFloat(sample) * 20)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 26)
        .animation(.linear(duration: 0.08), value: recorder.samples)
        .accessibilityHidden(true)
    }

    static func timeLabel(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
#endif
