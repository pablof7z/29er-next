import SwiftUI

#if os(iOS)
/// The trailing composer button. Shows the send arrow when there is substantive text/an
/// attachment, otherwise a microphone. A single tap starts a hands-free recording — no
/// press-and-hold, no release-to-send — so the interaction is one deliberate tap and the
/// locked recording bar (pause, delete, send) takes over from there.
struct VoiceComposerActionButton: View {
    @ObservedObject var coordinator: VoiceComposerCoordinator
    let showsMic: Bool
    let canSubmit: Bool
    let isSending: Bool
    let submit: () -> Void

    var body: some View {
        Group {
            if showsMic {
                micButton
            } else {
                sendButton
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    private var micButton: some View {
        Button { coordinator.beginHandsFree() } label: {
            Image(systemName: "mic.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.accentColor, in: .circle)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .accessibilityLabel("Record voice message")
        .accessibilityHint("Starts a hands-free recording you can pause, review, or send.")
        .accessibilityAddTraits(.startsMediaSession)
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
