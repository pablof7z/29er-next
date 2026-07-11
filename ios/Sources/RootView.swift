import NMP
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @State private var showingDiagnostics = false
    @State private var showingIdentity = false

    var body: some View {
        NavigationStack {
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
                    RoomView(group: group, engine: engine)
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
            List(model.groups) { group in
                NavigationLink(value: group) {
                    GroupRow(group: group)
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .bottom) {
                statusBar
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.relayCount > 0 ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text("\(model.groups.count) rooms")
            Spacer()
            Text("\(model.activeSubscriptionCount) live subscriptions")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var relayHost: String {
        URL(string: model.groupRelay)?.host ?? model.groupRelay
    }
}

private struct GroupRow: View {
    let group: GroupSummary

    var body: some View {
        HStack(spacing: 12) {
            GroupAvatar(group: group)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(group.about ?? group.id)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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

struct GroupAvatar: View {
    let group: GroupSummary

    var body: some View {
        ZStack {
            Circle()
                .fill(group.id.avatarColor.gradient)
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
