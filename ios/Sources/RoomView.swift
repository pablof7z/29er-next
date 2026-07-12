import NMP
import SwiftUI

struct RoomView: View {
    let group: GroupSummary
    let allGroups: [GroupSummary]
    let engine: NMPEngine
    @State private var model: RoomTimelineModel

    init(group: GroupSummary, allGroups: [GroupSummary], engine: NMPEngine) {
        self.group = group
        self.allGroups = allGroups
        self.engine = engine
        _model = State(initialValue: RoomTimelineModel(engine: engine, groupID: group.localID))
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
                    NavigationLink {
                        ChildChannelsView(
                            parent: group,
                            children: childGroups,
                            allGroups: allGroups,
                            engine: engine
                        )
                    } label: {
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
    }

    private var roomContent: some View {
        ChatTimelineView(
            messages: model.messages,
            profiles: model.profiles,
            hasReceivedSnapshot: model.hasReceivedMessages,
            error: model.messageError
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
            activityError: model.activityError
        )
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
    }
}
