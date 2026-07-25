import SwiftUI
#if os(iOS)
import PhotosUI
#endif

extension ChatComposer {
    @ViewBuilder
    var sendButtonLabel: some View {
        if isSending {
            ProgressView()
        } else {
            Image(systemName: "arrow.up")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(canSubmit ? .white : .secondary)
        }
    }

    var visibleRecipients: [ComposerRecipient] {
        ChatComposerState.recipients(selectedRecipients: selectedRecipients, reply: reply)
    }

    var pickerRecipients: [ComposerRecipient] {
        guard let reply, !recipients.contains(where: { $0.id == reply.author.id }) else {
            return recipients
        }
        return [reply.author] + recipients
    }

    var canSubmit: Bool {
        canSend && (ChatComposerState.message(from: draft) != nil || !attachments.isEmpty)
    }

    var showsVoiceAction: Bool {
        canSend
            && !isSending
            && ChatComposerState.showsVoiceAction(draft: draft, attachments: attachments)
    }

    func submit() {
        guard let request = ChatComposerState.request(
            draft: draft,
            selectedRecipients: selectedRecipients,
            reply: reply,
            attachments: attachments
        ), !isSending else { return }

        let submittedRecipients = selectedRecipients
        let submittedReply = reply
        let submittedAttachments = attachments
        let submittedDraft = draft
        isSending = true
        errorMessage = nil
        Task {
            let error = await send(request)
            guard !Task.isCancelled else { return }
            isSending = false
            if let error {
                errorMessage = error
                return
            }
            if draft == submittedDraft { draft = "" }
            if selectedRecipients == submittedRecipients { selectedRecipients = [] }
            if reply == submittedReply { reply = nil }
            let submittedIDs = Set(submittedAttachments.map(\.id))
            attachments.removeAll { submittedIDs.contains($0.id) }
            submittedAttachments.forEach { $0.removeLocalDraft() }
        }
    }

    func removeAttachment(_ id: UUID) {
        guard let attachment = attachments.first(where: { $0.id == id }) else { return }
        #if os(iOS)
        if attachment.localDraftURL != nil {
            pendingVoiceAttachmentRemoval = id
            return
        }
        #endif
        removeAttachmentImmediately(id)
    }

    func removeAttachmentImmediately(_ id: UUID) {
        guard let attachment = attachments.first(where: { $0.id == id }) else { return }
        attachment.removeLocalDraft()
        attachments.removeAll { $0.id == id }
    }

    #if os(iOS)
    var voiceAttachmentRemovalPresented: Binding<Bool> {
        Binding(
            get: { pendingVoiceAttachmentRemoval != nil },
            set: { if !$0 { pendingVoiceAttachmentRemoval = nil } }
        )
    }
    #endif

    func handlePickedFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard attachments.count + urls.count <= 10 else {
                errorMessage = "You can attach up to 10 files to one message."
                return
            }
            Task {
                do {
                    let loaded = try await Task.detached(priority: .userInitiated) {
                        try urls.map(ComposerAttachment.load(from:))
                    }.value
                    attachments.append(contentsOf: loaded)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if os(iOS)
    func handlePickedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        guard attachments.count + items.count <= 10 else {
            errorMessage = "You can attach up to 10 files to one message."
            photoPickerSelection = []
            return
        }
        Task {
            var loaded: [ComposerAttachment] = []
            for item in items {
                do {
                    loaded.append(try await ComposerAttachment.load(from: item))
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            attachments.append(contentsOf: loaded)
            photoPickerSelection = []
        }
    }
    #endif

    func handlePastedProviders(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        guard attachments.count + providers.count <= 10 else {
            errorMessage = "You can attach up to 10 files to one message."
            return
        }
        Task {
            var loaded: [ComposerAttachment] = []
            for provider in providers {
                do {
                    loaded.append(try await ComposerAttachment.load(from: provider))
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            attachments.append(contentsOf: loaded)
        }
    }
}
