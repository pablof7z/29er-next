import SwiftUI

/// The one channel list, used for both the root directory and any subchannel
/// screen. Rows carry live previews, unread badges, and subchannel counts;
/// they sort by most-recent activity and expose a swipe to their own
/// subchannels. Navigation is value-based so it resolves against the
/// destinations declared once on `RootView`'s stack (room and subchannels).
struct ChannelListView: View {
    let channels: [GroupSummary]
    let allGroups: [GroupSummary]
    let directory: RoomDirectoryModel?
    @Binding var path: NavigationPath

    var body: some View {
        List {
            if let error = directory?.observationError {
                Section {
                    DegradedStateNotice(
                        title: "Room activity unavailable",
                        message: error
                    )
                    .listRowInsets(EdgeInsets())
                }
            }
            channelRows
        }
        .listStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            proofRoomShortcut
        }
    }

    @ViewBuilder
    private var proofRoomShortcut: some View {
        if RoomOpenProbe.shared.isEnabled,
           let groupID = RoomOpenProbe.shared.targetGroupID,
           let group = channels.first(where: { $0.localID == groupID }) {
            Button {
                RoomOpenProbe.shared.begin(groupID: group.localID)
                path.append(group)
            } label: {
                Image(systemName: "stopwatch.fill")
                    .padding(12)
            }
            .buttonStyle(.borderedProminent)
            .padding(8)
            .accessibilityLabel("Open room performance proof")
            .accessibilityIdentifier("room-open-proof-shortcut")
        }
    }

    @ViewBuilder
    private var channelRows: some View {
        ForEach(ordered) { group in
            let childCount = GroupDirectoryProjection.directChildren(of: group, in: allGroups).count
            NavigationLink(value: group) {
                GroupRow(
                    group: group,
                    childCount: childCount,
                    entry: directory?.entries[group.localID]
                )
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if childCount > 0 {
                    Button {
                        path.append(SubchannelsRoute(parent: group))
                    } label: {
                        Label("Subchannels", systemImage: "rectangle.stack")
                    }
                    .tint(.indigo)
                    .accessibilityIdentifier("group-subchannels-swipe")
                }
            }
        }
    }

    /// Most-recent message first; rooms without any known message fall below
    /// active ones, alphabetically. Re-sorts live as messages arrive.
    private var ordered: [GroupSummary] {
        channels.sorted(by: activityDescending)
    }

    private func activityDescending(_ lhs: GroupSummary, _ rhs: GroupSummary) -> Bool {
        let lhsTime = directory?.entries[lhs.localID]?.latest?.createdAt
        let rhsTime = directory?.entries[rhs.localID]?.latest?.createdAt
        switch (lhsTime, rhsTime) {
        case let (left?, right?) where left != right:
            return left > right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
