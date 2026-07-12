import NMP
import SwiftUI

struct ChildChannelsView: View {
    let parent: GroupSummary
    let children: [GroupSummary]
    let allGroups: [GroupSummary]
    let engine: NMPEngine
    var directory: RoomDirectoryModel?

    var body: some View {
        List {
            Section {
                ForEach(children) { child in
                    NavigationLink {
                        RoomView(
                            group: child,
                            allGroups: allGroups,
                            engine: engine,
                            onOpen: { directory?.markRead(child) }
                        )
                    } label: {
                        GroupRow(
                            group: child,
                            childCount: GroupDirectoryProjection.directChildren(
                                of: child,
                                in: allGroups
                            ).count,
                            entry: directory?.entries[child.localID]
                        )
                    }
                }
            } header: {
                Text("Under \(parent.name)")
            }
        }
        .listStyle(.plain)
        .navigationTitle("Subchannels")
        .navigationBarTitleDisplayMode(.inline)
    }
}
