import SwiftUI
#if os(iOS)
import UIKit
#endif

extension ChatComposer {
    func configureVoice() {
        guard !didConfigureVoice else { return }
        didConfigureVoice = true
        #if os(iOS)
        voice.providerSnapshot = { try voiceProviders.snapshot() }
        #endif
        voice.restoreDraftIfNeeded()
    }

    func handleTranscriptReady(_ voiceDraft: VoiceDraft) {
        if voiceDraft.intent == .send {
            voice.dispatch(.publishStarted(voiceDraft))
        } else {
            integrateVoiceTranscript(voiceDraft)
        }
    }

    private func integrateVoiceTranscript(_ voiceDraft: VoiceDraft) {
        Task {
            do {
                let store = voice.store
                let attachment = try await Task.detached(priority: .userInitiated) {
                    try store.attachment(from: voiceDraft.url)
                }.value
                guard !Task.isCancelled else { return }
                if !attachments.contains(where: { $0.localDraftURL == voiceDraft.url }) {
                    attachments.append(attachment)
                }
                if let transcript = voiceDraft.transcript {
                    draft = VoiceTranscriptText.merging(
                        transcript,
                        originalText: voiceDraft.originalText,
                        currentText: draft
                    )
                }
                errorMessage = nil
                voice.dispatch(.transcriptIntegrated)
                #if os(iOS)
                isEditorFocused = true
                #endif
            } catch {
                voice.dispatch(.transcriptionFailed(voiceDraft, error.localizedDescription))
            }
        }
    }

    func runVoicePublish(_ voiceDraft: VoiceDraft) {
        guard !isSending else { return }
        let submittedText = draft
        let submittedRecipients = selectedRecipients
        let submittedReply = reply
        let submittedAttachments = attachments
        isSending = true
        errorMessage = nil

        sendTask = Task {
            let error = await publishVoice(voiceDraft)
            guard !Task.isCancelled else { return }
            isSending = false
            sendTask = nil
            if let error {
                let message = "Couldn’t Send — Your text and recording are saved in this chat. \(error)"
                errorMessage = message
                voice.dispatch(.publishFailed(message))
                return
            }

            if draft == submittedText || draft == composedText(for: voiceDraft) { draft = "" }
            if selectedRecipients == submittedRecipients { selectedRecipients = [] }
            if reply == submittedReply { reply = nil }
            let submittedIDs = Set(submittedAttachments.map(\.id))
            attachments.removeAll { submittedIDs.contains($0.id) }
            submittedAttachments.forEach { $0.removeLocalDraft() }
            voice.dispatch(.sendSucceeded)
        }
    }

    func publishVoice(_ voiceDraft: VoiceDraft) async -> String? {
        do {
            let store = voice.store
            let attachment = try await Task.detached(priority: .userInitiated) {
                try store.attachment(from: voiceDraft.url)
            }.value
            let request = ComposerRequest(
                content: composedText(for: voiceDraft),
                recipients: ChatComposerState.recipients(
                    selectedRecipients: selectedRecipients,
                    reply: reply
                ),
                reply: reply,
                attachments: attachments + [attachment]
            )
            return await send(request)
        } catch {
            return error.localizedDescription
        }
    }

    private func composedText(for voiceDraft: VoiceDraft) -> String {
        guard let transcript = voiceDraft.transcript, !transcript.isEmpty else {
            return draft.isEmpty ? voiceDraft.originalText : draft
        }
        return VoiceTranscriptText.merging(
            transcript,
            originalText: voiceDraft.originalText,
            currentText: draft
        )
    }
}

#if os(iOS)
extension ChatComposer {
    @ViewBuilder
    var voiceAwareControls: some View {
        if showsVoiceSurface {
            voiceSurface
        } else {
            textComposer
        }
    }

    var showsVoiceSurface: Bool {
        switch voice.state.capture {
        case .review, .transcribing, .transcriptReady, .publishing:
            true
        case .failed(let failure):
            failure.draft != nil || (failure.isPermissionDenied && voice.state.permission == .denied)
        default:
            voice.state.isLockedActive || voice.state.isHeldRecording
        }
    }

    @ViewBuilder
    private var voiceSurface: some View {
        switch voice.state.capture {
        case .transcribing(let draft), .transcriptReady(let draft):
            VoiceTranscriptionProgressCard(
                draft: draft,
                message: progressMessage(for: draft)
            )
        case .review(let draft):
            draftCard(draft: draft, failure: nil, isBusy: false)
        case .publishing(let draft):
            draftCard(draft: draft, failure: nil, isBusy: true)
        case .failed(let failure) where failure.draft != nil:
            draftCard(draft: failure.draft!, failure: failure, isBusy: false)
        case .failed(.permissionDenied):
            VoicePermissionDeniedRow(onOpenSettings: openAppSettings)
        default:
            VoiceLockedToolbar(
                elapsed: voice.state.elapsed,
                samples: voice.state.waveform,
                isBusy: voice.state.isFinalizingOrPublishing,
                onCancel: { isVoiceDeleteConfirmationPresented = true },
                onStop: voice.stopForReview,
                onSend: voice.send
            )
        }
    }

    private func draftCard(
        draft: VoiceDraft,
        failure: VoiceFailure?,
        isBusy: Bool
    ) -> some View {
        VoiceDraftReviewCard(
            draft: draft,
            isBusy: isBusy,
            failureMessage: failure?.message,
            primaryLabel: primaryLabel(for: failure),
            onDelete: { isVoiceDeleteConfirmationPresented = true },
            onPrimary: {
                if case .publish = failure {
                    voice.send()
                } else {
                    voice.retryTranscription()
                }
            },
            onSettings: failure == nil ? nil : { isVoiceSettingsPresented = true },
            onSendAudioOnly: failure == nil
                ? nil
                : { voice.dispatch(.audioOnlyPublishStarted(draft)) }
        )
    }

    private func primaryLabel(for failure: VoiceFailure?) -> String {
        if case .publish = failure { return "Retry sending" }
        return "Retry transcription"
    }

    private func progressMessage(for draft: VoiceDraft) -> String {
        let provider = draft.providerName ?? voiceProviders.activeName
        return draft.intent == .send
            ? "Transcribing with \(provider), then sending…"
            : "Transcribing with \(provider)…"
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif
