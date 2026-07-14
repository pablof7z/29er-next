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
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                liquidGlassContent
            } else {
                fallbackContent
            }
        }
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

    @available(iOS 26.0, macOS 26.0, *)
    private var liquidGlassContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canSend {
                GlassEffectContainer(spacing: 8) {
                    HStack(alignment: .bottom, spacing: 10) {
                        liquidMentionButton
                        editorPanel
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: 48)
                            .glassEffect(in: .rect(cornerRadius: 22))
                        liquidSendButton
                    }
                }
            } else {
                signedOutComposer
                    .glassEffect(in: .capsule)
            }
            ComposerDeliveryStatus(isSending: isSending, errorMessage: errorMessage)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var liquidMentionButton: some View {
        Button { isRecipientPickerPresented = true } label: {
            Image(systemName: "at")
                .font(.title3.weight(.semibold))
                .frame(width: 52, height: 52)
        }
        .contentShape(Circle())
        .buttonStyle(.glass)
        .disabled(isSending)
        .accessibilityLabel("Mention an agent")
        .accessibilityIdentifier("room-message-mention")
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var liquidSendButton: some View {
        Button(action: submit) { sendButtonLabel }
            .frame(width: 56, height: 56)
            .contentShape(Circle())
            .buttonStyle(.glassProminent)
            .tint(canSubmit ? .blue : .gray)
            .disabled(!canSubmit || isSending)
            .accessibilityLabel("Send message")
            .accessibilityIdentifier("room-message-send")
    }

    private var fallbackContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canSend {
                HStack(alignment: .bottom, spacing: 10) {
                    Button { isRecipientPickerPresented = true } label: {
                        Image(systemName: "at")
                            .font(.title3.weight(.semibold))
                            .frame(width: 52, height: 52)
                    }
                    .contentShape(Circle())
                    .background(.thinMaterial, in: .circle)
                    .buttonStyle(.plain)
                    .disabled(isSending)
                    .accessibilityLabel("Mention an agent")
                    .accessibilityIdentifier("room-message-mention")

                    editorPanel
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 48)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))

                    Button(action: submit) { sendButtonLabel }
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                        .background(Color.accentColor.opacity(canSubmit ? 0.9 : 0.2), in: .circle)
                        .buttonStyle(.plain)
                        .disabled(!canSubmit || isSending)
                        .accessibilityLabel("Send message")
                        .accessibilityIdentifier("room-message-send")
                }
            } else {
                signedOutComposer
                    .background(.thinMaterial, in: .capsule)
            }
            ComposerDeliveryStatus(isSending: isSending, errorMessage: errorMessage)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
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
                .font(.headline.weight(.semibold))
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
