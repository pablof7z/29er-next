import SwiftUI
#if os(iOS)
import UIKit
#endif

extension ChatComposer {
    /// Wire the coordinator's publish bridge to the canonical send path exactly once, then
    /// restore any durable draft for this room into the voice-specific review card.
    func configureVoice() {
        guard !didConfigureVoice else { return }
        didConfigureVoice = true
        // Publishing is driven from `body`'s onChange with *live* recipient/reply state
        // (see runVoicePublish); the coordinator's own publisher stays nil so it no-ops
        // the `.publish` effect and waits for the canonical result event.
        voice.restoreDraftIfNeeded()
    }

    /// Run the canonical send for a finalized draft the coordinator moved to `.publishing`,
    /// then feed the outcome back as the terminal event.
    func runVoicePublish(_ draft: VoiceDraft) {
        Task {
            let error = await publishVoice(draft)
            voice.dispatch(error == nil ? .sendSucceeded : .publishFailed(error ?? "Send failed"))
        }
    }

    /// Convert a finalized local draft into an audio attachment and send it through the
    /// same Blossom upload + NMP publication path as every other message. No second
    /// send implementation; composer context (recipients, reply) is preserved.
    func publishVoice(_ draft: VoiceDraft) async -> String? {
        do {
            let attachment = try voice.store.attachment(from: draft.url)
            let request = ComposerRequest(
                content: "",
                recipients: ChatComposerState.recipients(
                    selectedRecipients: selectedRecipients,
                    reply: reply
                ),
                reply: reply,
                attachments: [attachment]
            )
            let error = await send(request)
            if error == nil, reply != nil { reply = nil }
            return error
        } catch {
            return error.localizedDescription
        }
    }
}

#if os(iOS)
extension ChatComposer {
    /// Voice-aware composer layout. The trailing action button is kept as a stable sibling
    /// so the press-and-hold gesture survives the idle → held-recording content swap.
    @ViewBuilder
    var voiceAwareControls: some View {
        leadingVoiceContent
        if showsTrailingActionButton {
            actionButton
        }
    }

    @ViewBuilder
    private var leadingVoiceContent: some View {
        switch voice.state.capture {
        case .review(let draft):
            VoiceDraftReviewCard(
                draft: draft,
                isBusy: false,
                failureMessage: nil,
                onDelete: voice.discard,
                onPrimary: voice.send
            )
        case .publishing(let draft):
            VoiceDraftReviewCard(
                draft: draft,
                isBusy: true,
                failureMessage: nil,
                onDelete: {},
                onPrimary: {}
            )
        case .failed(.publish(let draft, let message)):
            VoiceDraftReviewCard(
                draft: draft,
                isBusy: false,
                failureMessage: message,
                onDelete: voice.discard,
                onPrimary: voice.send
            )
        case .failed(.permissionDenied):
            VoicePermissionDeniedRow(onOpenSettings: openAppSettings)
        case _ where voice.state.isLockedActive:
            VoiceLockedToolbar(
                elapsed: voice.state.elapsed,
                samples: voice.state.waveform,
                isPaused: voice.state.isPaused,
                isBusy: voice.state.isFinalizingOrPublishing,
                onDelete: voice.discard,
                onPauseResume: voice.togglePause,
                onSend: voice.send
            )
        case _ where voice.state.isHeldRecording:
            VoiceHeldRecordingRow(
                elapsed: voice.state.elapsed,
                samples: voice.state.waveform,
                gesture: voice.state.gesture
            )
        default:
            standardLeadingControls
        }
    }

    /// The mic/send button is shown for idle, requesting-permission, held-recording, and
    /// recoverable recorder failures. Locked/review/publishing/denied surfaces own their
    /// own actions, so the trailing button is withdrawn to avoid a duplicate.
    private var showsTrailingActionButton: Bool {
        switch voice.state.capture {
        case .idle, .requestingPermission:
            return true
        case .recording:
            return voice.state.mode == .held
        case .failed(.recorder):
            return true
        default:
            return false
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif
