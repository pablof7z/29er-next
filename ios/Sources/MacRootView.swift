#if os(macOS)
import SwiftUI

struct MacRootView: View {
    @Bindable var model: AppModel
    @State private var selectedGroup: GroupSummary?
    @State private var directory: RoomDirectoryModel?
    @State private var inbox: InboxModel?
    @State private var reads = MentionReads()
    @State private var showingDiagnostics = false
    @State private var showingIdentity = false
    @State private var showingInbox = false

    var body: some View {
        Group {
            switch model.state {
            case .starting:
                ProgressView("Starting NMP…")
            case .failed(let message):
                DatabaseRecoveryView(
                    message: message,
                    canReset: model.canResetLocalDatabase
                ) {
                    model.resetLocalDatabase()
                }
            case .observing:
                desktopContent
            }
        }
        .task(id: model.engineGeneration) {
            await model.run()
        }
        .task(id: model.engineGeneration) {
            guard let engine = model.engine else { return }
            let directory = RoomDirectoryModel(engine: engine)
            self.directory = directory
            await directory.observe()
        }
        .task(id: InboxContext(generation: model.engineGeneration, pubkey: model.activePubkey)) {
            guard let engine = model.engine, let pubkey = model.activePubkey else {
                inbox = nil
                return
            }
            let inbox = InboxModel(engine: engine, recipient: pubkey, reads: reads)
            self.inbox = inbox
            await inbox.observe()
        }
        .onChange(of: model.groups, initial: true) { _, groups in
            reconcileSelection(with: groups)
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView(snapshot: model.diagnostics, error: model.diagnosticsError)
        }
        .sheet(isPresented: $showingIdentity) {
            IdentitySheet(model: model)
        }
        .sheet(isPresented: $showingInbox) {
            NavigationStack {
                if let inbox {
                    InboxView(inbox: inbox, groups: model.groups)
                }
            }
            .frame(minWidth: 700, minHeight: 520)
        }
    }

    private var desktopContent: some View {
        NavigationSplitView {
            MacChannelSidebar(
                groups: model.groups,
                directory: directory,
                selection: $selectedGroup
            )
            .navigationTitle("Channels")
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            roomDetail
        }
        .toolbar {
            ToolbarItemGroup(placement: PlatformSupport.trailingToolbarPlacement) {
                if model.activePubkey != nil {
                    Button {
                        showingInbox = true
                    } label: {
                        InboxBell(count: inbox?.unreadCount ?? 0)
                    }
                    .accessibilityLabel("Inbox")
                    .accessibilityIdentifier("inbox-button")
                }
                Button {
                    showingIdentity = true
                } label: {
                    Label(
                        model.activePubkey == nil ? "Sign In" : "Account",
                        systemImage: model.activePubkey == nil
                            ? "person.crop.circle"
                            : "person.crop.circle.badge.checkmark"
                    )
                }
                Button {
                    showingDiagnostics = true
                } label: {
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                }
            }
        }
    }

    @ViewBuilder
    private var roomDetail: some View {
        if let selectedGroup, let engine = model.engine {
            NavigationStack {
                RoomView(
                    group: selectedGroup,
                    allGroups: model.groups,
                    engine: engine,
                    activePubkey: model.activePubkey,
                    reads: reads,
                    onOpen: { directory?.markRead(selectedGroup) }
                )
            }
            .id(
                RoomContext(
                    generation: model.engineGeneration,
                    group: selectedGroup.id,
                    pubkey: model.activePubkey
                )
            )
        } else {
            ContentUnavailableView(
                "Select a Channel",
                systemImage: "sidebar.left",
                description: Text("Choose a channel from the sidebar to open its timeline.")
            )
        }
    }

    private func reconcileSelection(with groups: [GroupSummary]) {
        if let selectedGroup,
           let current = groups.first(where: { $0.id == selectedGroup.id }) {
            self.selectedGroup = current
            return
        }
        selectedGroup = GroupDirectoryProjection.roots(in: groups).first ?? groups.first
    }

    private struct InboxContext: Hashable {
        let generation: Int
        let pubkey: String?
    }

    private struct RoomContext: Hashable {
        let generation: Int
        let group: GroupCoordinate
        let pubkey: String?
    }
}

private struct MacChannelSidebar: View {
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
