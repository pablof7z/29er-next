import SwiftUI

/// Bottom-of-room composer. Display names and unsent state stay in SwiftUI;
/// NMP owns materializing recipients/replies into the published group event.
struct ChatComposer: View {
    let canSend: Bool
    let recipients: [ComposerRecipient]
    @Binding var reply: ComposerReply?
    let send: (ComposerRequest) async -> String?

    @State private var draft = ""
    @State private var selectedRecipients: [ComposerRecipient] = []
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var isRecipientPickerPresented = false
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        content
        .sheet(isPresented: $isRecipientPickerPresented) {
            ComposerRecipientPicker(
                recipients: pickerRecipients,
                requiredRecipientID: reply?.author.id,
                selectedRecipients: $selectedRecipients
            )
        }
        .onChange(of: reply?.id) { _, eventID in
            if eventID != nil { isEditorFocused = true }
        }
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
            ComposerDeliveryStatus(isSending: isSending, errorMessage: errorMessage)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 6) {
            mentionButton
            editorPanel
                .padding(.vertical, 8)
                .frame(minHeight: 40)
            sendButton
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
        canSend && ChatComposerState.message(from: draft) != nil
    }

    private func submit() {
        guard let request = ChatComposerState.request(
            draft: draft,
            selectedRecipients: selectedRecipients,
            reply: reply
        ), !isSending else { return }

        let submittedRecipients = selectedRecipients
        let submittedReply = reply
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
            if ChatComposerState.message(from: draft) == request.content { draft = "" }
            if selectedRecipients == submittedRecipients { selectedRecipients = [] }
            if reply == submittedReply { reply = nil }
        }
    }
}
