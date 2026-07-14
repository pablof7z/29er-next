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
        .task(id: HostContext(generation: model.engineGeneration, host: model.selectedHost)) {
            guard let engine = model.engine, let host = model.selectedHost else {
                directory = nil
                return
            }
            let directory = RoomDirectoryModel(engine: engine, hostRelay: host)
            self.directory = directory
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await model.observeGroups(host: host) }
                group.addTask { await directory.observe() }
            }
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
        VStack(spacing: 0) {
            HostGroupSelector(
                activePubkey: model.activePubkey,
                bootstrapHost: model.groupRelay,
                remembered: model.remembered,
                hasReceivedRemembered: model.hasReceivedRememberedGroups,
                rememberedError: model.rememberedGroupsError,
                selectedHost: model.selectedHost,
                selectedGroup: model.selectedGroup,
                selectHost: selectHost,
                openGroup: openRememberedGroup
            )
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

    private func selectHost(_ host: String) {
        selectedGroup = nil
        model.selectHost(host)
    }

    private func openRememberedGroup(_ group: RememberedGroupChoice) {
        model.selectGroup(group)
        selectedGroup = model.summary(for: group)
    }

    private struct InboxContext: Hashable {
        let generation: Int
        let pubkey: String?
    }

    private struct HostContext: Hashable {
        let generation: Int
        let host: String?
    }

    private struct RoomContext: Hashable {
        let generation: Int
        let group: GroupCoordinate
        let pubkey: String?
    }
}

#endif
