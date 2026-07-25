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
    /// Voice-aware composer layout. When a live recording, review card, or a recoverable
    /// voice failure is on screen, that surface takes over the whole bar; otherwise the
    /// text composer (with its focus-driven reflow and tap-once mic) is shown.
    @ViewBuilder
    var voiceAwareControls: some View {
        if showsVoiceSurface {
            voiceSurface
        } else {
            textComposer
        }
    }

    /// True when a dedicated voice surface should replace the text composer entirely:
    /// the locked recording bar, the draft review card, or a publish/permission failure.
    /// Idle, requesting-permission, and recoverable recorder failures stay on the text
    /// composer so the mic can retry inline.
    var showsVoiceSurface: Bool {
        switch voice.state.capture {
        case .review, .publishing:
            return true
        case .failed(.publish):
            return true
        case .failed(.permissionDenied):
            return voice.state.permission == .denied
        default:
            return voice.state.isLockedActive || voice.state.isHeldRecording
        }
    }

    @ViewBuilder
    private var voiceSurface: some View {
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
        default:
            // Any live capture (tap-once lands here immediately as a locked recording).
            VoiceLockedToolbar(
                elapsed: voice.state.elapsed,
                samples: voice.state.waveform,
                isBusy: voice.state.isFinalizingOrPublishing,
                onCancel: voice.discard,
                onStop: voice.stopForReview,
                onSend: voice.send
            )
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif
