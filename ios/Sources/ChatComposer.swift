import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UIKit
#endif

/// Bottom-of-room composer. Display names and unsent state stay in SwiftUI;
/// NMP owns materializing recipients/replies into the published group event.
/// Voice capture is owned by `VoiceComposerCoordinator`; this view only hosts its
/// surfaces and bridges a finalized draft into the existing send path.
struct ChatComposer: View {
    let canSend: Bool
    let recipients: [ComposerRecipient]
    /// The most recent speaker other than the signed-in user, if any (#118).
    /// Auto-tagged into `selectedRecipients` the moment typing starts, so a
    /// fresh message defaults to continuing the conversation with them --
    /// unless a reply or a manual mention pick already supplies a target.
    let defaultRecipient: ComposerRecipient?
    @Binding var reply: ComposerReply?
    let send: (ComposerRequest) async -> String?
    let draftStore: ComposerDraftStore

    // Internal, not private: `ChatComposer+Submission` resets it on send.
    @State var draft: String
    @State var selectedRecipients: [ComposerRecipient] = []
    @State var attachments: [ComposerAttachment] = []
    @State var isSending = false
    @State var errorMessage: String?
    @State private var isRecipientPickerPresented = false
    @State private var isAttachmentPickerPresented = false
    #if os(iOS)
    @State private var isPhotoPickerPresented = false
    @State var photoPickerSelection: [PhotosPickerItem] = []
    #endif
    @State var didConfigureVoice = false
    @StateObject var voice: VoiceComposerCoordinator
    @FocusState private var isEditorFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(
        canSend: Bool,
        recipients: [ComposerRecipient],
        defaultRecipient: ComposerRecipient? = nil,
        reply: Binding<ComposerReply?>,
        initialAttachments: [ComposerAttachment] = [],
        voiceDraftScope: String = "default",
        voiceCoordinator: VoiceComposerCoordinator? = nil,
        send: @escaping (ComposerRequest) async -> String?
    ) {
        self.canSend = canSend
        self.recipients = recipients
        self.defaultRecipient = defaultRecipient
        _reply = reply
        _attachments = State(initialValue: initialAttachments)
        _voice = StateObject(
            wrappedValue: voiceCoordinator ?? .live(store: VoiceDraftStore(scope: voiceDraftScope))
        )
        let draftStore = ComposerDraftStore(scope: voiceDraftScope)
        self.draftStore = draftStore
        _draft = State(initialValue: draftStore.load())
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
        #if os(iOS)
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $photoPickerSelection,
            maxSelectionCount: 10,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: photoPickerSelection) { _, items in
            handlePickedPhotos(items)
        }
        #endif
        .onChange(of: reply?.id) { _, eventID in
            if eventID != nil { isEditorFocused = true }
        }
        .onChange(of: draft.isEmpty) { wasEmpty, isEmptyNow in
            guard wasEmpty, !isEmptyNow,
                  reply == nil, selectedRecipients.isEmpty,
                  let defaultRecipient else { return }
            selectedRecipients = [defaultRecipient]
        }
        .onChange(of: draft) { _, newValue in
            draftStore.save(newValue)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voice.sceneBecameInactive() }
        }
        .onChange(of: voice.state.publishingDraft?.url) { _, url in
            guard url != nil, let draft = voice.state.publishingDraft else { return }
            runVoicePublish(draft)
        }
        .onChange(of: voice.state.failure) { _, failure in
            errorMessage = failure?.isPermissionDenied == true ? nil : failure?.message
        }
        .onAppear(perform: configureVoice)
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
        voiceAwareControls
        #else
        standardComposerControls
        #endif
    }

    @ViewBuilder
    var standardComposerControls: some View {
        standardLeadingControls
        actionButton
    }

    /// Attach + mention + editor, without the trailing action button. Used by the macOS
    /// composer, which keeps the two side buttons rather than the iOS focus reflow.
    @ViewBuilder
    var standardLeadingControls: some View {
        VStack(spacing: 4) {
            attachmentButton
            mentionButton
        }
        editorPanel
            .padding(.vertical, 8)
            .frame(minHeight: 40)
    }

    #if os(iOS)
    /// The composer is "expanded" (text on top, controls in a bottom row) whenever the
    /// user is writing or has added content; otherwise it collapses to a single line with
    /// the `+` and mic hugging the sides.
    var isComposerExpanded: Bool {
        isEditorFocused
            || !draft.isEmpty
            || !attachments.isEmpty
            || !visibleRecipients.isEmpty
            || reply != nil
    }

    /// iOS text composer with one stable editor that moves between the resting row and
    /// the expanded writing layout without surrendering keyboard focus.
    var textComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                ComposerAttachmentPreviewStrip(
                    attachments: attachments,
                    isDisabled: isSending
                ) { id in
                    removeAttachment(id)
                }
            }
            ComposerTextReflowLayout(isExpanded: isComposerExpanded) {
                plusMenu
                composerEditor
                mentionPillsInline
                actionButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isComposerExpanded ? 2 : 0)
    }

    private var composerEditor: some View {
        TextField("Message", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(isComposerExpanded ? 1...6 : 1...1)
            .focused($isEditorFocused)
            .disabled(isSending)
            .padding(.horizontal, isComposerExpanded ? 4 : 0)
            .padding(.top, isComposerExpanded ? 2 : 0)
            .accessibilityIdentifier("room-message-composer")
    }

    /// Mention pills, inline in the bottom row right after the `+`. Scrolls horizontally
    /// in place when there are more than fit, so the row stays a single line.
    private var mentionPillsInline: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(visibleRecipients) { recipient in
                    // Every mention pill is removable now that the "Replying to…" summary
                    // is gone — removing the reply author's pill also clears the reply.
                    ComposerMentionChip(recipient: recipient, isRequired: false) {
                        if reply?.author.id == recipient.id { reply = nil }
                        selectedRecipients.removeAll { $0.id == recipient.id }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The single "add" entry point: attachments and mentions both live under `+`, so there
    /// is no separate mention button on iOS.
    private var plusMenu: some View {
        Menu {
            Button {
                isPhotoPickerPresented = true
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            Button {
                isAttachmentPickerPresented = true
            } label: {
                Label("Browse Files", systemImage: "folder")
            }
            Button {
                handlePastedProviders(UIPasteboard.general.itemProviders)
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            Divider()
            Button {
                isRecipientPickerPresented = true
            } label: {
                Label("Mention someone", systemImage: "at")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.regular))
                .foregroundStyle(plusMenuHasContent ? Color.accentColor : Color.secondary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .frame(width: 36, height: 36)
        .disabled(isSending)
        .accessibilityLabel("Add attachment or mention")
        .accessibilityIdentifier("room-message-attach")
    }

    private var plusMenuHasContent: Bool {
        !attachments.isEmpty || !visibleRecipients.isEmpty
    }
    #endif

    private var attachmentButton: some View {
        #if os(iOS)
        Menu {
            Button {
                isPhotoPickerPresented = true
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            Button {
                isAttachmentPickerPresented = true
            } label: {
                Label("Browse Files", systemImage: "folder")
            }
            Button {
                handlePastedProviders(UIPasteboard.general.itemProviders)
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
        } label: {
            attachmentIcon
        }
        .frame(width: 36, height: 36)
        .contentShape(Rectangle())
        .disabled(isSending)
        .accessibilityLabel("Attach files")
        .accessibilityIdentifier("room-message-attach")
        #else
        Button { isAttachmentPickerPresented = true } label: {
            attachmentIcon
        }
        .frame(width: 36, height: 36)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(isSending)
        .help("Attach files")
        .accessibilityLabel("Attach files")
        .accessibilityIdentifier("room-message-attach")
        #endif
    }

    private var attachmentIcon: some View {
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
    var actionButton: some View {
        #if os(iOS)
        VoiceComposerActionButton(
            coordinator: voice,
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
