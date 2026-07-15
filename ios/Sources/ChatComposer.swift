import SwiftUI
import UniformTypeIdentifiers

/// Bottom-of-room composer. Display names and unsent state stay in SwiftUI;
/// NMP owns materializing recipients/replies into the published group event.
struct ChatComposer: View {
    let canSend: Bool
    let recipients: [ComposerRecipient]
    @Binding var reply: ComposerReply?
    let send: (ComposerRequest) async -> String?

    @State private var draft = ""
    @State private var selectedRecipients: [ComposerRecipient] = []
    @State private var attachments: [ComposerAttachment] = []
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var isRecipientPickerPresented = false
    @State private var isAttachmentPickerPresented = false
    @State private var didRestoreVoiceDrafts = false
    @StateObject private var voiceRecorder: VoiceMessageRecorder
    @FocusState private var isEditorFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(
        canSend: Bool,
        recipients: [ComposerRecipient],
        reply: Binding<ComposerReply?>,
        initialAttachments: [ComposerAttachment] = [],
        voiceDraftScope: String = "default",
        send: @escaping (ComposerRequest) async -> String?
    ) {
        self.canSend = canSend
        self.recipients = recipients
        _reply = reply
        _attachments = State(initialValue: initialAttachments)
        _voiceRecorder = StateObject(
            wrappedValue: VoiceMessageRecorder(store: VoiceDraftStore(scope: voiceDraftScope))
        )
        self.send = send
    }

    var body: some View {
        content
        .sheet(isPresented: $isRecipientPickerPresented) {
            ComposerRecipientPicker(
                recipients: pickerRecipients,
                requiredRecipientID: reply?.author.id,
                selectedRecipients: $selectedRecipients
            )
        }
        .fileImporter(
            isPresented: $isAttachmentPickerPresented,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true,
            onCompletion: handlePickedFiles
        )
        .onChange(of: reply?.id) { _, eventID in
            if eventID != nil { isEditorFocused = true }
        }
        .onChange(of: voiceRecorder.completedDraft) { _, completed in
            guard let completed else { return }
            acceptVoiceDraft(completed)
        }
        .onChange(of: voiceRecorder.failureMessage) { _, message in
            if let message { errorMessage = message }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voiceRecorder.preserveForBackground() }
        }
        .onAppear(perform: restoreVoiceDrafts)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canSend {
                composerBar
            } else {
                signedOutComposer
                    .background(
                        PlatformSupport.secondaryGroupedBackground,
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .overlay(composerBorder)
            }
            ComposerDeliveryStatus(
                isSending: isSending,
                progressMessage: attachments.isEmpty ? "Sending…" : "Uploading attachments…",
                errorMessage: errorMessage
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 6) {
            composerControls
        }
        .padding(.leading, 6)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background(
            PlatformSupport.secondaryGroupedBackground,
            in: RoundedRectangle(cornerRadius: 21)
        )
        .overlay(composerBorder)
    }

    @ViewBuilder
    private var composerControls: some View {
        #if os(iOS)
        if voiceRecorder.isActive {
            VoiceRecordingPanel(recorder: voiceRecorder)
                .padding(.leading, 8)
                .padding(.vertical, 8)
                .frame(minHeight: 40)
            actionButton
        } else {
            standardComposerControls
        }
        #else
        standardComposerControls
        #endif
    }

    @ViewBuilder
    private var standardComposerControls: some View {
        attachmentButton
        mentionButton
        editorPanel
            .padding(.vertical, 8)
            .frame(minHeight: 40)
        actionButton
    }

    private var attachmentButton: some View {
        Button { isAttachmentPickerPresented = true } label: {
            Image(systemName: "paperclip")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(attachments.isEmpty ? Color.secondary : Color.accentColor)
                .frame(width: 30, height: 30)
                .background(
                    attachments.isEmpty
                        ? Color.secondary.opacity(0.08)
                        : Color.accentColor.opacity(0.14),
                    in: .circle
                )
        }
        .frame(width: 36, height: 36)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(isSending)
        .help("Attach files")
        .accessibilityLabel("Attach files")
        .accessibilityIdentifier("room-message-attach")
    }

    private var mentionButton: some View {
        Button { isRecipientPickerPresented = true } label: {
            Image(systemName: "at")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    visibleRecipients.isEmpty ? Color.secondary : Color.accentColor
                )
                .frame(width: 30, height: 30)
                .background(
                    visibleRecipients.isEmpty
                        ? Color.secondary.opacity(0.08)
                        : Color.accentColor.opacity(0.14),
                    in: .circle
                )
        }
        .frame(width: 36, height: 36)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(isSending)
        .help("Mention an agent")
        .accessibilityLabel("Mention an agent")
        .accessibilityIdentifier("room-message-mention")
    }

    private var sendButton: some View {
        Button(action: submit) { sendButtonLabel }
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .background(
                Color.accentColor.opacity(canSubmit ? 1 : 0.12),
                in: .circle
            )
            .buttonStyle(.plain)
            .disabled(!canSubmit || isSending)
            .help("Send message")
            .accessibilityLabel("Send message")
            .accessibilityIdentifier("room-message-send")
    }

    @ViewBuilder
    private var actionButton: some View {
        #if os(iOS)
        VoiceComposerActionButton(
            recorder: voiceRecorder,
            showsMic: showsVoiceAction,
            canSubmit: canSubmit,
            isSending: isSending,
            submit: submit
        )
        #else
        sendButton
        #endif
    }

    private var composerBorder: some View {
        RoundedRectangle(cornerRadius: 21)
            .stroke(PlatformSupport.separator.opacity(0.55), lineWidth: 0.5)
    }

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reply {
                ComposerReplySummary(reply: reply) { self.reply = nil }
            }
            if !visibleRecipients.isEmpty {
                recipientChips
            }
            if !attachments.isEmpty {
                ComposerAttachmentPreviewStrip(
                    attachments: attachments,
                    isDisabled: isSending
                ) { id in
                    removeAttachment(id)
                }
            }
            TextField("Message", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isEditorFocused)
                .disabled(isSending)
                .accessibilityIdentifier("room-message-composer")
        }
    }

    private var recipientChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(visibleRecipients) { recipient in
                    ComposerMentionChip(
                        recipient: recipient,
                        isRequired: reply?.author.id == recipient.id
                    ) {
                        selectedRecipients.removeAll { $0.id == recipient.id }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var signedOutComposer: some View {
        Label("Sign in to write", systemImage: "lock.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityIdentifier("room-composer-signed-out")
    }
}

extension ChatComposer {
    @ViewBuilder
    private var sendButtonLabel: some View {
        if isSending {
            ProgressView()
        } else {
            Image(systemName: "arrow.up")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(canSubmit ? .white : .secondary)
        }
    }

    private var visibleRecipients: [ComposerRecipient] {
        ChatComposerState.recipients(selectedRecipients: selectedRecipients, reply: reply)
    }

    private var pickerRecipients: [ComposerRecipient] {
        guard let reply, !recipients.contains(where: { $0.id == reply.author.id }) else {
            return recipients
        }
        return [reply.author] + recipients
    }

    private var canSubmit: Bool {
        canSend && (ChatComposerState.message(from: draft) != nil || !attachments.isEmpty)
    }

    private var showsVoiceAction: Bool {
        canSend
            && !isSending
            && ChatComposerState.showsVoiceAction(draft: draft, attachments: attachments)
    }

    private func submit() {
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

    private func acceptVoiceDraft(_ completed: CompletedVoiceDraft) {
        defer { voiceRecorder.consumeCompletedDraft() }
        do {
            let attachment = try voiceRecorder.store.attachment(from: completed.url)
            guard !attachments.contains(where: { $0.localDraftURL == completed.url }) else {
                return
            }
            attachments.append(attachment)
            errorMessage = completed.shouldSend ? nil : voiceRecorder.failureMessage
            if completed.shouldSend { submit() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreVoiceDrafts() {
        guard !didRestoreVoiceDrafts else { return }
        didRestoreVoiceDrafts = true
        do {
            let recovered = try voiceRecorder.recoverPendingAttachments()
            let existing = Set(attachments.compactMap(\.localDraftURL))
            attachments.append(contentsOf: recovered.filter { attachment in
                guard let url = attachment.localDraftURL else { return true }
                return !existing.contains(url)
            })
            if !recovered.isEmpty {
                errorMessage = "Recovered an unsent voice message."
            }
        } catch {
            errorMessage = "A saved voice message could not be restored: \(error.localizedDescription)"
        }
    }

    private func removeAttachment(_ id: UUID) {
        guard let attachment = attachments.first(where: { $0.id == id }) else { return }
        attachment.removeLocalDraft()
        attachments.removeAll { $0.id == id }
    }

    private func handlePickedFiles(_ result: Result<[URL], Error>) {
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
}
