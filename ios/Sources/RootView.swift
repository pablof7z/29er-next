import NMPContent
import SwiftUI

struct SubchannelsRoute: Hashable {
    let parent: GroupSummary
}

struct RootView: View {
    @Bindable var model: AppModel
    @State private var path = NavigationPath()
    @State private var directory: RoomDirectoryModel?
    @State private var inbox: InboxModel?
    @State private var reads = MentionReads()
    @State private var showingDiagnostics = false
    @State private var showingIdentity = false
    @State private var showingRelayBrowser = false

    var body: some View {
        NavigationStack(path: $path) {
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
                    roomContent
                }
            }
            .navigationTitle("Channels")
            .navigationDestination(for: GroupSummary.self) { group in
                if let engine = model.engine {
                    RoomView(
                        group: group,
                        allGroups: model.groups,
                        engine: engine,
                        activePubkey: model.activePubkey,
                        reads: reads,
                        onOpen: { directory?.markRead(group) }
                    )
                }
            }
            .navigationDestination(for: SubchannelsRoute.self) { route in
                ChannelListView(
                    channels: GroupDirectoryProjection.directChildren(
                        of: route.parent,
                        in: model.groups
                    ),
                    allGroups: model.groups,
                    directory: directory,
                    contentClient: model.contentClient,
                    path: $path
                )
                .navigationTitle(route.parent.name)
                .platformInlineNavigationTitle()
            }
            .navigationDestination(for: InboxRoute.self) { _ in
                if let inbox {
                    InboxView(inbox: inbox, groups: model.groups)
                }
            }
            .navigationDestination(for: MentionRoute.self) { route in
                if let engine = model.engine {
                    RoomView(
                        group: route.group,
                        allGroups: model.groups,
                        engine: engine,
                        activePubkey: model.activePubkey,
                        reads: reads,
                        focusMessageID: route.messageID,
                        onOpen: { directory?.markRead(route.group) }
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: PlatformSupport.leadingToolbarPlacement) {
                    Button {
                        showingRelayBrowser = true
                    } label: {
                        Label("Favorite Relays", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .accessibilityIdentifier("favorite-relays-button")
                }
                // One group with a @ViewBuilder body: a conditional first item
                // inserts reliably when the account signs in, which a
                // conditional standalone ToolbarItem does not.
                ToolbarItemGroup(placement: PlatformSupport.trailingToolbarPlacement) {
                    if model.activePubkey != nil {
                        Button {
                            path.append(InboxRoute())
                        } label: {
                            InboxBell(count: inbox?.unreadCount ?? 0)
                        }
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
            .sheet(isPresented: $showingDiagnostics) {
                DiagnosticsView(snapshot: model.diagnostics, error: model.diagnosticsError)
            }
            .sheet(isPresented: $showingIdentity) {
                IdentitySheet(model: model)
            }
            .sheet(isPresented: $showingRelayBrowser) {
                FavoriteRelayBrowser(
                    activePubkey: model.activePubkey,
                    bootstrapHost: model.groupRelay,
                    remembered: model.remembered,
                    hasReceivedRemembered: model.hasReceivedRememberedGroups,
                    rememberedError: model.rememberedGroupsError,
                    selectedHost: model.selectedHost,
                    editState: model.favoriteRelayEditState,
                    selectHost: selectHost,
                    addRelay: model.addFavoriteRelay,
                    removeRelay: model.removeFavoriteRelay,
                    clearEditError: model.clearFavoriteRelayError
                )
            }
        }
        .id(model.engineGeneration)
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
    }

    /// Re-roots the inbox query whenever the engine is replaced or the signed-in
    /// account changes (sign-in does not bump the engine generation).
    private struct InboxContext: Hashable {
        let generation: Int
        let pubkey: String?
    }

    private struct HostContext: Hashable {
        let generation: Int
        let host: String?
    }

    @ViewBuilder
    private var roomContent: some View {
        Group {
            if let groupsError = model.groupsError {
                ContentUnavailableView(
                    "Rooms unavailable",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text(groupsError)
                )
            } else if model.selectedHost == nil {
                ContentUnavailableView(
                    "No favorite chat relays",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Open Favorite Relays to choose a relay from your NIP-51 chat list.")
                )
            } else if model.groups.isEmpty {
                ContentUnavailableView {
                    Label("Looking for Rooms", systemImage: "sailboat")
                } description: {
                    Text("Public rooms from \(relayHost) will appear here.")
                } actions: {
                    if !model.hasReceivedGroups { ProgressView() }
                }
            } else {
                ChannelListView(
                    channels: GroupDirectoryProjection.roots(in: model.groups),
                    allGroups: model.groups,
                    directory: directory,
                    contentClient: model.contentClient,
                    path: $path
                )
            }
        }
    }

    private func selectHost(_ host: String) {
        path = NavigationPath()
        model.selectHost(host)
    }

    private var relayHost: String {
        guard let host = model.selectedHost else { return "the selected host" }
        return URL(string: host)?.host ?? host
    }
}
