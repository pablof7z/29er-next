import NMP
import SwiftUI

struct SubchannelsRoute: Hashable {
    let parent: GroupSummary
}

struct RootView: View {
    @Bindable var model: AppModel
    @State private var path = NavigationPath()
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
                    RoomView(group: group, allGroups: model.groups, engine: engine)
                }
            }
            .navigationDestination(for: SubchannelsRoute.self) { route in
                if let engine = model.engine {
                    ChildChannelsView(
                        parent: route.parent,
                        children: GroupDirectoryProjection.directChildren(
                            of: route.parent,
                            in: model.groups
                        ),
                        allGroups: model.groups,
                        engine: engine
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
                }
                ToolbarItem(placement: .topBarTrailing) {
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
            List(GroupDirectoryProjection.roots(in: model.groups)) { group in
                let children = GroupDirectoryProjection.directChildren(of: group, in: model.groups)
                NavigationLink(value: group) {
                    GroupRow(group: group, children: children)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if !children.isEmpty {
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
            .listStyle(.plain)
        }
    }

    private var relayHost: String {
        URL(string: model.groupRelay)?.host ?? model.groupRelay
    }
}

struct GroupRow: View {
    let group: GroupSummary
    var children: [GroupSummary] = []

    var body: some View {
        HStack(spacing: 12) {
            GroupAvatar(group: group)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(group.about ?? group.localID)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !children.isEmpty {
                    SubchannelChips(children: children)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 4)
            if group.isPublic {
                Image(systemName: "globe")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Public room")
            }
        }
        .padding(.vertical, 4)
    }
}

struct SubchannelChips: View {
    let children: [GroupSummary]
    private let maxVisible = 3

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "rectangle.stack")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ForEach(children.prefix(maxVisible)) { child in
                HStack(spacing: 4) {
                    Circle()
                        .fill(child.localID.avatarColor)
                        .frame(width: 6, height: 6)
                    Text(child.name)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
            if children.count > maxVisible {
                Text("+\(children.count - maxVisible)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chipsAccessibilityLabel)
    }

    private var chipsAccessibilityLabel: String {
        let names = children.map(\.name).joined(separator: ", ")
        return "\(children.count) subchannels: \(names)"
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
