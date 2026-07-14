import SwiftUI

struct HostGroupSelector: View {
    let activePubkey: String?
    let bootstrapHost: String
    let remembered: RememberedGroupSnapshot
    let hasReceivedRemembered: Bool
    let rememberedError: String?
    let selectedHost: String?
    let selectedGroup: GroupCoordinate?
    let selectHost: (String) -> Void
    let openGroup: (RememberedGroupChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                hostMenu
                groupMenu
            }
            status
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("host-group-selector")
    }

    private var hostMenu: some View {
        Menu {
            ForEach(hosts, id: \.self) { host in
                Button {
                    selectHost(host)
                } label: {
                    if host == selectedHost {
                        Label(relayLabel(host), systemImage: "checkmark")
                    } else {
                        Text(relayLabel(host))
                    }
                }
            }
        } label: {
            selectorLabel(
                title: activePubkey == nil ? "Bootstrap" : "Host",
                value: selectedHost.map(relayLabel) ?? "No host",
                symbol: "antenna.radiowaves.left.and.right"
            )
        }
        .disabled(hosts.isEmpty)
        .accessibilityIdentifier("host-selector")
    }

    private var groupMenu: some View {
        Menu {
            ForEach(groupsForSelectedHost) { group in
                Button {
                    openGroup(group)
                } label: {
                    if group.coordinate == selectedGroup {
                        Label(group.displayName, systemImage: "checkmark")
                    } else {
                        Text(group.displayName)
                    }
                }
            }
        } label: {
            selectorLabel(
                title: "Remembered room",
                value: selectedGroupName ?? groupPlaceholder,
                symbol: "number"
            )
        }
        .disabled(activePubkey == nil || groupsForSelectedHost.isEmpty)
        .accessibilityIdentifier("remembered-group-selector")
    }

    private func selectorLabel(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var status: some View {
        if let rememberedError {
            Label(rememberedError, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityIdentifier("remembered-groups-error")
        } else if activePubkey == nil {
            Text("Signed out: browsing the operator bootstrap host read-only.")
        } else if !hasReceivedRemembered {
            Label("Loading remembered rooms…", systemImage: "arrow.triangle.2.circlepath")
        } else if remembered.groups.isEmpty {
            Text("This account has no public remembered NIP-29 rooms.")
        } else if remembered.hasPrivateContent {
            Label(
                "Some private remembered items are unavailable and were not replaced.",
                systemImage: "lock.fill"
            )
        }
    }

    private var hosts: [String] {
        activePubkey == nil ? [bootstrapHost].filter { !$0.isEmpty } : remembered.hosts
    }

    private var groupsForSelectedHost: [RememberedGroupChoice] {
        remembered.groups.filter { $0.host == selectedHost }
    }

    private var selectedGroupName: String? {
        remembered.groups.first { $0.coordinate == selectedGroup }?.displayName
    }

    private var groupPlaceholder: String {
        activePubkey == nil ? "Sign in to choose" : "Choose a room"
    }

    private func relayLabel(_ relay: String) -> String {
        URL(string: relay)?.host ?? relay
    }
}
