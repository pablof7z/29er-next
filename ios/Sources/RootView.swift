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

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch model.state {
                case .starting:
                    ProgressView("Starting NMP…")
                case .failed(let message):
                    ContentUnavailableView(
                        "NMP Couldn’t Start",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                case .observing:
                    roomContent
                }
            }
            .navigationTitle("29er")
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
                    path: $path
                )
                .navigationTitle(route.parent.name)
                .navigationBarTitleDisplayMode(.inline)
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
                // One group with a @ViewBuilder body: a conditional first item
                // inserts reliably when the account signs in, which a
                // conditional standalone ToolbarItem does not.
                ToolbarItemGroup(placement: .topBarTrailing) {
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
                DiagnosticsView(snapshot: model.diagnostics)
            }
            .sheet(isPresented: $showingIdentity) {
                IdentitySheet(model: model)
            }
        }
        .id(model.engineGeneration)
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
    }

    /// Re-roots the inbox query whenever the engine is replaced or the signed-in
    /// account changes (sign-in does not bump the engine generation).
    private struct InboxContext: Hashable {
        let generation: Int
        let pubkey: String?
    }

    @ViewBuilder
    private var roomContent: some View {
        if model.groups.isEmpty {
            ContentUnavailableView {
                Label("Looking for Rooms", systemImage: "sailboat")
            } description: {
                Text("Public NIP-29 rooms will appear as NMP receives metadata from \(relayHost).")
            } actions: {
                ProgressView()
            }
        } else {
            ChannelListView(
                channels: GroupDirectoryProjection.roots(in: model.groups),
                allGroups: model.groups,
                directory: directory,
                path: $path
            )
        }
    }

    private var relayHost: String {
        URL(string: model.groupRelay)?.host ?? model.groupRelay
    }
}

struct GroupRow: View {
    let group: GroupSummary
    var childCount: Int = 0
    var entry: RoomDirectoryModel.Entry?

    var body: some View {
        HStack(spacing: 12) {
            GroupAvatar(group: group)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                if let latest = entry?.latest {
                    Text(GroupRow.relativeTime(latest.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                HStack(spacing: 6) {
                    if childCount > 0 {
                        SubchannelCountBadge(count: childCount)
                    }
                    if let unread = entry?.unread, unread > 0 {
                        UnreadBadge(count: unread)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        if let content = entry?.latest?.content.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return content
        }
        return group.about ?? group.localID
    }

    static func relativeTime(_ timestamp: UInt64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let seconds = Date().timeIntervalSince(date)
        switch seconds {
        case ..<60: return "now"
        case ..<3_600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3_600))h"
        case ..<604_800: return "\(Int(seconds / 86_400))d"
        default: return date.formatted(.dateTime.month().day())
        }
    }
}

struct SubchannelCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 10))
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.secondary.opacity(0.14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) subchannels")
    }
}

struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor))
            .accessibilityLabel("\(count) unread messages")
    }
}

struct GroupAvatar: View {
    let group: GroupSummary

    var body: some View {
        ZStack {
            Circle()
                .fill(group.localID.avatarColor.gradient)
            Text(group.initials)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 46, height: 46)
    }
}

extension String {
    var avatarColor: Color {
        let value = utf8.reduce(UInt64(0xcbf29ce484222325)) { partial, byte in
            (partial ^ UInt64(byte)) &* 0x100000001b3
        }
        return Color(hue: Double(value % 360) / 360, saturation: 0.58, brightness: 0.78)
    }
}
