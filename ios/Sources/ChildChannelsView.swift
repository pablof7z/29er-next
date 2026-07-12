import NMP
import SwiftUI

struct ChildChannelsView: View {
    let parent: GroupSummary
    let children: [GroupSummary]
    let allGroups: [GroupSummary]
    let engine: NMPEngine

    var body: some View {
        List {
            Section {
                ForEach(children) { child in
                    NavigationLink {
                        RoomView(group: child, allGroups: allGroups, engine: engine)
                    } label: {
                        GroupRow(
                            group: child,
                            children: GroupDirectoryProjection.directChildren(
                                of: child,
                                in: allGroups
                            )
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
