import NMP
import SwiftUI

struct RoomView: View {
    let group: GroupSummary
    let allGroups: [GroupSummary]
    let engine: NMPEngine
    let activePubkey: String?
    var reads: MentionReads?
    var focusMessageID: String?
    var onOpen: (() -> Void)?
    @State private var model: RoomTimelineModel

    init(
        group: GroupSummary,
        allGroups: [GroupSummary],
        engine: NMPEngine,
        activePubkey: String?,
        reads: MentionReads? = nil,
        focusMessageID: String? = nil,
        onOpen: (() -> Void)? = nil
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
            case .failed(let message):
                ContentUnavailableView(
                    "Room Unavailable",
                    systemImage: "exclamationmark.bubble",
                    description: Text(message)
                )
            case .observing:
                roomContent
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !childGroups.isEmpty {
                    NavigationLink(value: SubchannelsRoute(parent: group)) {
                        Label("Subchannels", systemImage: "rectangle.stack")
                    }
                    .accessibilityIdentifier("room-subchannels-button")
                }

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
        .onAppear { onOpen?() }
    }

    private var roomContent: some View {
        ChatTimelineView(
            messages: model.messages,
            profiles: model.profiles,
            hasReceivedSnapshot: model.hasReceivedMessages,
            error: model.messageError,
            mentionIDs: model.mentionIDs,
            reads: reads,
            focusMessageID: focusMessageID
        )
    }

    private var childGroups: [GroupSummary] {
        GroupDirectoryProjection.directChildren(of: group, in: allGroups)
    }

    private var peopleView: some View {
        RoomPeopleView(
            people: model.people,
            hasReceivedMembership: model.hasReceivedMembership,
            hasMembershipMetadata: model.hasMembershipMetadata,
            membershipError: model.membershipError,
            hasReceivedActivities: model.hasReceivedActivities,
            activityError: model.activityError,
            backends: model.backends,
            canSendCommands: activePubkey != nil,
            sendCommand: sendCommand
        )
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendCommand(_ command: String, to backendPubkey: String) async -> String? {
        guard let activePubkey else { return "Sign in to send commands." }
        return await model.sendManagementCommand(
            command,
            backendPubkey: backendPubkey,
            author: activePubkey
        )
    }
}
