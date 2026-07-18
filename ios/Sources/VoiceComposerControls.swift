import SwiftUI

#if os(iOS)
/// The trailing composer button. Shows the send arrow when there is substantive text/an
/// attachment, otherwise a microphone that is the persistent anchor for the press-and-hold
/// gesture. Keeping this one view mounted across idle → held recording is what preserves
/// the continuous touch as the surrounding composer content swaps.
struct VoiceComposerActionButton: View {
    @ObservedObject var coordinator: VoiceComposerCoordinator
    let showsMic: Bool
    let canSubmit: Bool
    let isSending: Bool
    let submit: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var isTracking = false

    var body: some View {
        Group {
            if showsMic || coordinator.state.isHeldRecording {
                micButton
            } else {
                sendButton
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    private var micButton: some View {
        Image(systemName: "mic.fill")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Color.accentColor, in: .circle)
            .scaleEffect(coordinator.state.isHeldRecording ? 1.14 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.7), value: coordinator.state.isHeldRecording)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            // VoiceOver cannot hold: the gesture is suppressed and a tap records hands-free.
            .gesture(recordingGesture, including: voiceOverEnabled ? .none : .all)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Record voice message")
            .accessibilityHint("Starts a hands-free recording you can pause, review, or send.")
            .accessibilityAddTraits(.startsMediaSession)
            .accessibilityAction { coordinator.beginHandsFree() }
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
            .frame(width: 40, height: 40)
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
                    coordinator.pressBegan()
                }
                let reading = coordinator.state.metrics.reading(
                    translation: value.translation,
                    layoutDirection: layoutDirection
                )
                coordinator.dragChanged(reading)
            }
            .onEnded { _ in
                isTracking = false
                coordinator.pressEnded()
            }
    }
}

/// Inline, recoverable microphone-denied state. Never destroys typed text or drafts; the
/// composer keeps that state and simply offers a way to grant access.
struct VoicePermissionDeniedRow: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.slash.fill")
                .foregroundStyle(.secondary)
            Text("Microphone access is off.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Open Settings", action: onOpenSettings)
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: 44)
                .accessibilityIdentifier("voice-open-settings")
        }
        .padding(.leading, 6)
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-permission-denied")
    }
}
#endif
