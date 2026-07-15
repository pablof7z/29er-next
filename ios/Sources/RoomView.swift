import NMP
import SwiftUI

struct RoomView: View {
    let group: GroupSummary
    let allGroups: [GroupSummary]
    let engine: NMPEngine
    let activePubkey: String?
    let reads: MentionReads?
    let focusMessageID: String?
    let onOpen: (() -> Void)?
    @State private var model: RoomTimelineModel
    @State private var replyTarget: ComposerReply?
    @State private var roomOpenProbe = RoomOpenProbe.shared
    @State private var presentedImage: PresentedURL?
    @State private var presentedBrowser: PresentedURL?
    @Environment(\.openURL) private var openURL

    init(
        group: GroupSummary,
        allGroups: [GroupSummary],
        engine: NMPEngine,
        activePubkey: String?,
        reads: MentionReads?,
        focusMessageID: String? = nil,
        onOpen: (() -> Void)?
    ) {
        self.group = group
        self.allGroups = allGroups
        self.engine = engine
        self.activePubkey = activePubkey
        self.reads = reads
        self.focusMessageID = focusMessageID
        self.onOpen = onOpen
        _model = State(
            initialValue: RoomTimelineModel(
                engine: engine,
                groupID: group.localID,
                hostRelay: group.hostRelay,
                recipient: activePubkey
            )
        )
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView("Opening room…")
            case .observing:
                roomContent
            }
        }
        .navigationTitle(group.name)
        .platformInlineNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: PlatformSupport.trailingToolbarPlacement) {
                #if os(iOS)
                if !childGroups.isEmpty {
                    NavigationLink(value: SubchannelsRoute(parent: group)) {
                        Label("Subchannels", systemImage: "rectangle.stack")
                    }
                    .accessibilityIdentifier("room-subchannels-button")
                }
                #endif

                NavigationLink {
                    peopleView
                } label: {
                    Label("People", systemImage: "person.2")
                }
                .accessibilityIdentifier("room-people-button")
            }
        }
        .task {
            await model.observe()
        }
        .onAppear {
            if roomOpenProbe.groupID != group.localID {
                // XCUITest does not always deliver a NavigationLink's
                // simultaneous gesture. Starting here is the deterministic
                // fallback; ordinary taps still start at activation time.
                roomOpenProbe.begin(groupID: group.localID)
            }
            roomOpenProbe.recordFirstFrame(groupID: group.localID)
            onOpen?()
        }
        .safeAreaInset(edge: .bottom) {
            if roomOpenProbe.isEnabled {
                Text(roomOpenProbe.report)
                    .font(.caption2.monospaced())
                    .lineLimit(12)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
                    .accessibilityIdentifier("room-open-proof")
            }
        }
        #if os(iOS)
        .fullScreenCover(item: $presentedImage) { item in
            ZoomableRemoteImage(url: item.url)
        }
        .fullScreenCover(item: $presentedBrowser) { item in
            NIP07BrowserView(url: item.url, engine: engine)
        }
        #else
        .sheet(item: $presentedImage) { item in
            ZoomableRemoteImage(url: item.url)
                .frame(minWidth: 640, minHeight: 480)
        }
        #endif
    }

    private var roomContent: some View {
        ChatTimelineView(
            items: model.timelineItems,
            profiles: model.profiles,
            people: model.people,
            hasReceivedSnapshot: model.hasReceivedChat,
            error: model.chatError,
            profileError: model.profileError,
            mentionIDs: model.mentionIDs,
            reads: reads,
            focusMessageID: focusMessageID,
            onOpenLink: openLink,
            onOpenImage: { presentedImage = PresentedURL($0) },
            onReply: beginReply
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatComposer(
                canSend: activePubkey != nil,
                recipients: model.composerRecipients,
                reply: $replyTarget,
                voiceDraftScope: "\(group.hostRelay)|\(group.localID)",
                send: sendMessage
            )
        }
    }

    #if os(iOS)
    private var childGroups: [GroupSummary] {
        GroupDirectoryProjection.directChildren(of: group, in: allGroups)
    }
    #endif

    private var peopleView: some View {
        RoomPeopleView(
            people: model.people,
            hasReceivedMembership: model.hasReceivedMembership,
            hasMembershipMetadata: model.hasMembershipMetadata,
            membershipError: model.membershipError,
            hasReceivedActivities: model.hasReceivedActivities,
            activityError: model.activityError,
            adminError: model.adminError,
            profileError: model.profileError,
            backends: model.backends,
            canSendCommands: activePubkey != nil,
            sendCommand: sendCommand
        )
        .navigationTitle("People")
        .platformInlineNavigationTitle()
    }

    private func sendCommand(_ command: String, to backendPubkey: String) async -> String? {
        guard activePubkey != nil else { return "Sign in to send commands." }
        return await model.sendManagementCommand(
            command,
            backendPubkey: backendPubkey
        )
    }

    private func sendMessage(_ request: ComposerRequest) async -> String? {
        guard activePubkey != nil else { return "Sign in to write in this room." }
        return await model.sendMessage(request)
    }

    private func beginReply(_ message: RoomMessage) {
        replyTarget = model.composerReply(to: message)
    }

    private func openLink(_ url: URL) {
        #if os(iOS)
        presentedBrowser = PresentedURL(url)
        #else
        openURL(url)
        #endif
    }
}
