import SwiftUI

/// The full player surface. A narrated branch pushes another player onto this
/// stack; popping back resumes the parent where it left off.
struct TTS29PlayerView: View {
    let root: TTS29Item
    @Bindable var playback: TTS29PlaybackController
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            TTS29ItemPlayer(
                item: root,
                playback: playback,
                isRoot: true,
                onOpenChild: openChild
            )
            .navigationDestination(for: String.self) { childID in
                if let child = find(childID, in: root) {
                    TTS29ItemPlayer(
                        item: child,
                        playback: playback,
                        isRoot: false,
                        onOpenChild: openChild
                    )
                }
            }
        }
    }

    private func openChild(_ child: TTS29Item) {
        playback.openChild(child)
        path.append(child.id)
    }

    private func find(_ id: String, in item: TTS29Item) -> TTS29Item? {
        if item.id == id { return item }
        for child in item.children {
            if let match = find(id, in: child) { return match }
        }
        return nil
    }
}

private struct TTS29ItemPlayer: View {
    let item: TTS29Item
    @Bindable var playback: TTS29PlaybackController
    let isRoot: Bool
    let onOpenChild: (TTS29Item) -> Void

    @State private var transcript: TTS29Transcript
    @State private var following = true
    @State private var previewed: TTS29Artifact?
    @Environment(\.openURL) private var openURL

    init(item: TTS29Item, playback: TTS29PlaybackController, isRoot: Bool, onOpenChild: @escaping (TTS29Item) -> Void) {
        self.item = item
        self.playback = playback
        self.isRoot = isRoot
        self.onOpenChild = onOpenChild
        _transcript = State(initialValue: TTS29Transcript(item.body))
    }

    private var identity: TTS29Identity { TTS29Identity(item) }
    private var isActive: Bool { playback.isActive(item) }
    private var focus: TTS29Focus? { isActive ? transcript.focus(at: playback.progress) : nil }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Text(item.title).font(.title2.bold()).lineLimit(3)
                    if !transcript.isEmpty {
                        TTS29TranscriptView(
                            transcript: transcript,
                            item: item,
                            focus: focus,
                            onSeek: seek,
                            onOpenAttachment: openAttachment,
                            onOpenChild: onOpenChild
                        )
                    }
                    if item.hasChildren {
                        TTS29BranchesRail(children: item.children, onOpen: onOpenChild)
                    }
                    if item.hasAttachments {
                        TTS29AttachmentsRail(attachments: item.attachments, onOpen: openAttachment)
                    }
                    if item.hasQuestions {
                        TTS29QuestionsSection(
                            item: item,
                            existingAnswer: playback.answer(for: item),
                            canAnswer: playback.context.activePubkey != nil,
                            answerState: playback.answerState,
                            onSubmit: submitAnswer
                        )
                    }
                }
                .padding(16)
                .padding(.bottom, 12)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in following = false })
            .onChange(of: focus?.block) { _, block in
                guard following, let block else { return }
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(block, anchor: .center) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            TTS29TransportCluster(playback: playback, item: item)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .navigationTitle(isRoot ? "" : item.title)
        .platformInlineNavigationTitle()
        .toolbar { toolbarContent }
        .sheet(item: $previewed) { TTS29AttachmentPreview(attachment: $0) }
        .onAppear(perform: resumeIfReturning)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isRoot {
            ToolbarItem(placement: PlatformSupport.leadingToolbarPlacement) {
                Button {
                    playback.presentedRoot = nil
                } label: {
                    Label("Minimize", systemImage: "chevron.down")
                }
                .accessibilityIdentifier("tts29-minimize")
            }
        }
        ToolbarItem(placement: PlatformSupport.trailingToolbarPlacement) {
            TTS29SpeedControl(playback: playback)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            TTS29AgentAvatar(identity: identity, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(identity.displayName).font(.subheadline.weight(.medium))
                Text(TTS29Formatting.timestamp(item.createdDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !following, isActive, playback.isPlaying {
                Button {
                    following = true
                } label: {
                    Label("Following", systemImage: "waveform")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .tts29GlassCapsule(tint: .accentColor)
            }
        }
    }

    private func seek(to block: TTS29Block) {
        if !isActive { playback.toggle(item) }
        following = true
        playback.seek(toFraction: block.startFraction)
    }

    private func openAttachment(_ attachment: TTS29Artifact) {
        if attachment.kind.opensInApp {
            previewed = attachment
        } else if let url = attachment.resolvedURL {
            openURL(url)
        }
    }

    private func submitAnswer(_ answers: [TTS29Answer]) {
        Task { await playback.submitAnswer(for: item, answers: answers) }
    }

    private func resumeIfReturning() {
        if !isActive, playback.resumeOffset(for: item) != nil {
            playback.toggle(item)
        }
    }
}
