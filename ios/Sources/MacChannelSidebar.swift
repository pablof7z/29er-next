#if os(macOS)
import SwiftUI

struct MacChannelSidebar: View {
    let groups: [GroupSummary]
    let directory: RoomDirectoryModel?
    @Binding var selection: GroupSummary?
    @State private var expanded: Set<GroupCoordinate> = []
    @State private var knownParents: Set<GroupCoordinate> = []

    private var tree: [GroupTreeNode] {
        GroupDirectoryProjection.tree(in: groups)
    }

    private var parentIDs: Set<GroupCoordinate> {
        Set(tree.flatMap(collectParentIDs))
    }

    private var visibleRows: [SidebarTreeRow] {
        flatten(tree, depth: 0)
    }

    var body: some View {
        List(selection: $selection) {
            if let notice = ChannelListPresentation.activityNotice(
                error: directory?.observationError
            ) {
                Section {
                    DegradedStateNotice(notice)
                }
            }

            Section("Channels") {
                ForEach(visibleRows) { row in
                    HStack(spacing: 6) {
                        disclosureButton(for: row)
                        Image(systemName: row.hasChildren ? "folder" : "number")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(row.group.name)
                            .lineLimit(1)
                            .foregroundStyle(
                                row.depth == 0
                                    ? WorkspaceTint.color(for: row.group.localID)
                                    : .primary
                            )
                        Spacer(minLength: 8)
                        if let unread = directory?.entries[row.group.localID]?.unread,
                           unread > 0 {
                            UnreadBadge(count: unread)
                        }
                    }
                    .padding(.leading, CGFloat(row.depth) * 14)
                    .contentShape(Rectangle())
                    .tag(row.group)
                    .accessibilityIdentifier("sidebar-channel-\(row.group.localID)")
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: parentIDs, initial: true) { _, currentParents in
            let newParents = currentParents.subtracting(knownParents)
            expanded.formUnion(newParents)
            expanded.formIntersection(currentParents)
            knownParents = currentParents
        }
    }

    @ViewBuilder
    private func disclosureButton(for row: SidebarTreeRow) -> some View {
        if row.hasChildren {
            Button {
                if expanded.contains(row.id) {
                    expanded.remove(row.id)
                } else {
                    expanded.insert(row.id)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(expanded.contains(row.id) ? 90 : 0))
                    .frame(width: 14, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded.contains(row.id) ? "Collapse" : "Expand")
        } else {
            Color.clear.frame(width: 14, height: 18)
        }
    }

    private func flatten(_ nodes: [GroupTreeNode], depth: Int) -> [SidebarTreeRow] {
        nodes.flatMap { node in
            let row = SidebarTreeRow(
                group: node.group,
                depth: depth,
                hasChildren: !node.children.isEmpty
            )
            guard expanded.contains(node.id) else { return [row] }
            return [row] + flatten(node.children, depth: depth + 1)
        }
    }

    private func collectParentIDs(_ node: GroupTreeNode) -> [GroupCoordinate] {
        guard !node.children.isEmpty else { return [] }
        return [node.id] + node.children.flatMap(collectParentIDs)
    }
}

private struct SidebarTreeRow: Identifiable {
    let group: GroupSummary
    let depth: Int
    let hasChildren: Bool

    var id: GroupCoordinate { group.id }
}
#endif
