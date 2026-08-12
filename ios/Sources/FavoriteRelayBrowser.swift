import SwiftUI

struct FavoriteRelayBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddRelay = false
    @State private var relayInput = ""

    let relays: [FavoriteRelayChoice]
    let selectedHost: String?
    let editState: FavoriteRelayEditState
    let selectHost: (String) -> Void
    let addRelay: (String) -> Void
    let removeRelay: (String) -> Void
    let clearEditError: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if relays.isEmpty {
                    emptyFavorites
                } else {
                    relayList(relays)
                }
            }
            .navigationTitle("Favorite Relays")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingAddRelay = true
                    } label: {
                        Label("Add Relay", systemImage: "plus")
                    }
                    .accessibilityIdentifier("add-favorite-relay")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .platformRelayBrowserPresentation()
        .accessibilityIdentifier("favorite-relay-browser")
        .alert("Add Favorite Relay", isPresented: $showingAddRelay) {
            TextField("wss://relay.example", text: $relayInput)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { relayInput = "" }
            Button("Add") { submitRelay() }
                .disabled(relayInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter the WebSocket URL of a chat relay.")
        }
        .alert("Couldn’t Add Relay", isPresented: errorPresented) {
            Button("OK", action: clearEditError)
        } message: {
            Text(editState.failureMessage ?? "The relay could not be added.")
        }
    }

    private func relayList(_ relays: [FavoriteRelayChoice]) -> some View {
        List {
            Section {
                ForEach(relays) { relay in
                    Button {
                        selectHost(relay.url)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(relay.displayName)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(relay.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if relay.url == selectedHost {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("favorite-relay-\(relay.accessibilityKey)")
                    .contextMenu {
                        if relay.isRemovable {
                            Button("Remove Relay", role: .destructive) {
                                removeRelay(relay.url)
                            }
                        }
                    }
#if os(iOS)
                    .swipeActions {
                        if relay.isRemovable {
                            Button("Remove", role: .destructive) {
                                removeRelay(relay.url)
                            }
                        }
                    }
#endif
                }
            } footer: {
                footer
            }
        }
    }

    private var emptyFavorites: some View {
        VStack(spacing: 18) {
            unavailable(
                title: "No favorite chat relays",
                symbol: "antenna.radiowaves.left.and.right",
                description: "Add a relay to connect to it from this device."
            )
            Button {
                showingAddRelay = true
            } label: {
                Label("Add Relay", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("add-first-favorite-relay")
        }
        .padding()
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { editState.failureMessage != nil },
            set: { if !$0 { clearEditError() } }
        )
    }

    private func submitRelay() {
        let relay = relayInput.trimmingCharacters(in: .whitespacesAndNewlines)
        relayInput = ""
        addRelay(relay)
    }

    @ViewBuilder
    private var footer: some View {
        Text("Relays added here are saved on this device. Their connection state comes from NMP.")
    }

    private func unavailable(title: String, symbol: String, description: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: symbol,
            description: Text(description)
        )
    }
}

struct FavoriteRelayChoice: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case `default`
        case saved
        case remembered
    }

    let url: String
    let source: Source
    let roomCount: Int?

    var id: String { url }
    var displayName: String { URL(string: url)?.host ?? url }
    var accessibilityKey: String { displayName.replacingOccurrences(of: ".", with: "-") }

    var detail: String {
        let sourceDescription = switch source {
        case .default: "Default chat relay"
        case .saved: "Saved on this device"
        case .remembered: "Listed in remembered rooms"
        }
        guard let roomCount, roomCount > 0 else { return sourceDescription }
        let rooms = roomCount == 1 ? "1 remembered room" : "\(roomCount) remembered rooms"
        return "\(sourceDescription) · \(rooms)"
    }

    var isRemovable: Bool { source == .saved }

    static func favorites(
        defaultRelay: String,
        savedRelays: [String],
        remembered: RememberedGroupSnapshot
    ) -> [FavoriteRelayChoice] {
        var seen = Set<String>()
        var entries: [(String, Source)] = []
        func append(_ relay: String, source: Source) {
            guard !relay.isEmpty, seen.insert(relay).inserted else { return }
            entries.append((relay, source))
        }

        append(defaultRelay, source: .default)
        savedRelays.forEach { append($0, source: .saved) }
        remembered.hosts.forEach { append($0, source: .remembered) }
        return entries.map { relay, source in
            FavoriteRelayChoice(
                url: relay,
                source: source,
                roomCount: remembered.groups.lazy.filter { $0.host == relay }.count
            )
        }
    }
}
