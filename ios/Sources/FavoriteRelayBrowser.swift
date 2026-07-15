import SwiftUI

struct FavoriteRelayBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddRelay = false
    @State private var relayInput = ""

    let activePubkey: String?
    let bootstrapHost: String
    let remembered: RememberedGroupSnapshot
    let hasReceivedRemembered: Bool
    let rememberedError: String?
    let selectedHost: String?
    let editState: FavoriteRelayEditState
    let selectHost: (String) -> Void
    let addRelay: (String) -> Void
    let removeRelay: (String) -> Void
    let clearEditError: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let rememberedError {
                    unavailable(
                        title: "Favorite relays unavailable",
                        symbol: "antenna.radiowaves.left.and.right.slash",
                        description: rememberedError
                    )
                } else if activePubkey == nil {
                    relayList(FavoriteRelayChoice.bootstrap(host: bootstrapHost))
                } else if !hasReceivedRemembered {
                    ProgressView("Loading favorite relays…")
                } else if remembered.hosts.isEmpty {
                    emptyFavorites
                } else {
                    relayList(FavoriteRelayChoice.favorites(from: remembered))
                }
            }
            .navigationTitle("Favorite Relays")
            .platformInlineNavigationTitle()
            .toolbar {
                if activePubkey != nil {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if editState.isWorking {
                            ProgressView()
                                .accessibilityLabel("Updating favorite relays")
                        } else {
#if os(iOS)
                            EditButton()
#endif
                        }
                        Button {
                            showingAddRelay = true
                        } label: {
                            Label("Add Relay", systemImage: "plus")
                        }
                        .disabled(editState.isWorking)
                        .accessibilityIdentifier("add-favorite-relay")
                    }
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
            Text("Enter the WebSocket URL of a NIP-29 chat relay.")
        }
        .alert("Couldn’t Update Favorite Relays", isPresented: errorPresented) {
            Button("OK", action: clearEditError)
        } message: {
            Text(editState.failureMessage ?? "The relay list could not be updated.")
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
                }
                .onDelete { offsets in
                    guard !editState.isWorking, let index = offsets.first else { return }
                    removeRelay(relays[index].url)
                }
            } footer: {
                footer
            }
        }
        .disabled(editState.isWorking)
    }

    private var emptyFavorites: some View {
        VStack(spacing: 18) {
            unavailable(
                title: "No favorite chat relays",
                symbol: "antenna.radiowaves.left.and.right",
                description: "Add a relay to your NIP-51 chat relay list."
            )
            if editState.isWorking {
                ProgressView("Updating favorite relays…")
            } else {
                Button {
                    showingAddRelay = true
                } label: {
                    Label("Add Relay", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("add-first-favorite-relay")
            }
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
        if activePubkey == nil {
            Text("Sign in to browse the chat relays saved to your account.")
        } else if remembered.hasPrivateContent {
            Label(
                "Some private list entries are not shown.",
                systemImage: "lock.fill"
            )
        }
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
    let url: String
    let roomCount: Int?

    var id: String { url }
    var displayName: String { URL(string: url)?.host ?? url }
    var accessibilityKey: String { displayName.replacingOccurrences(of: ".", with: "-") }

    var detail: String {
        guard let roomCount else { return "Default chat relay" }
        return roomCount == 1 ? "1 remembered room" : "\(roomCount) remembered rooms"
    }

    static func favorites(from snapshot: RememberedGroupSnapshot) -> [FavoriteRelayChoice] {
        snapshot.hosts.map { host in
            FavoriteRelayChoice(
                url: host,
                roomCount: snapshot.groups.lazy.filter { $0.host == host }.count
            )
        }
    }

    static func bootstrap(host: String) -> [FavoriteRelayChoice] {
        guard !host.isEmpty else { return [] }
        return [FavoriteRelayChoice(url: host, roomCount: nil)]
    }
}
