import Foundation
import Kingfisher
import NMP
import NMPUI
import SwiftUI

/// Picker-owned presentation for a relay's engine-owned NIP-11 snapshot.
///
/// NMP owns acquisition, validation, freshness, and its bounded in-memory
/// cache. This view only owns a visible row's task and how an advertised icon
/// is displayed.
struct FavoriteRelayBrandingRow: View {
    let relay: FavoriteRelayChoice
    let selectedHost: String?
    let engine: NMPEngine?
    let engineGeneration: Int
    let select: () -> Void

    @State private var information: NMPRelayInformationState

    init(
        relay: FavoriteRelayChoice,
        selectedHost: String?,
        engine: NMPEngine?,
        engineGeneration: Int,
        select: @escaping () -> Void
    ) {
        self.relay = relay
        self.selectedHost = selectedHost
        self.engine = engine
        self.engineGeneration = engineGeneration
        self.select = select
        _information = State(initialValue: .loading(relay: relay.url))
    }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                RelayAdvertisedIcon(information: information)
                VStack(alignment: .leading, spacing: 3) {
                    Text(information.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(FavoriteRelayBranding.subtitle(for: relay, information: information))
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
        .task(id: RelayInformationRequest(relay: relay.url, generation: engineGeneration)) {
            await loadInformation()
        }
    }

    private func loadInformation() async {
        guard let engine else {
            information = .unavailable(relay: relay.url, reason: "NMP is unavailable")
            return
        }

        information = .loading(relay: relay.url)
        do {
            let value = try await engine.relayInformation(for: relay.url)
            guard !Task.isCancelled else { return }
            information = NMPRelayInformationState(value)
        } catch {
            guard !Task.isCancelled else { return }
            information = .unavailable(relay: relay.url, reason: nil)
        }
    }
}

/// The currently visible relay's picker affordance in the channel header.
///
/// Like picker rows, this view owns only the lifetime of one visible NIP-11
/// request. The engine supplies cached or newly acquired relay information.
struct CurrentRelayTitleButton: View {
    let relay: String?
    let engine: NMPEngine?
    let engineGeneration: Int
    let openRelayBrowser: () -> Void

    @State private var information: NMPRelayInformationState

    init(
        relay: String?,
        engine: NMPEngine?,
        engineGeneration: Int,
        openRelayBrowser: @escaping () -> Void
    ) {
        self.relay = relay
        self.engine = engine
        self.engineGeneration = engineGeneration
        self.openRelayBrowser = openRelayBrowser
        _information = State(initialValue: .loading(relay: relay ?? ""))
    }

    var body: some View {
        Button(action: openRelayBrowser) {
            HStack(spacing: 4) {
                Text(RelayHeaderPresentation.title(relay: relay, information: information))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
        }
        .accessibilityLabel("Favorite Relays")
        .accessibilityValue(RelayHeaderPresentation.title(relay: relay, information: information))
        .accessibilityIdentifier("current-relay-button")
        .task(id: RelayInformationRequest(relay: relay ?? "", generation: engineGeneration)) {
            await loadInformation()
        }
    }

    private func loadInformation() async {
        guard let relay, let engine else { return }

        information = .loading(relay: relay)
        do {
            let value = try await engine.relayInformation(for: relay)
            guard !Task.isCancelled else { return }
            information = NMPRelayInformationState(value)
        } catch {
            guard !Task.isCancelled else { return }
            information = .unavailable(relay: relay, reason: nil)
        }
    }
}

private struct RelayInformationRequest: Hashable {
    let relay: String
    let generation: Int
}

private struct RelayAdvertisedIcon: View {
    let information: NMPRelayInformationState

    private var iconURL: URL? {
        RelayIconURL.value(from: information.presentation?.advertisedIcon)
    }

    var body: some View {
        ZStack {
            NMPRelayIcon(state: information, size: 32)
            if let iconURL {
                KFImage(iconURL)
                    .placeholder { Color.clear }
                    .onFailureView { Color.clear }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            }
        }
        .frame(width: 32, height: 32)
    }
}

enum FavoriteRelayBranding {
    static func subtitle(
        for relay: FavoriteRelayChoice,
        information: NMPRelayInformationState
    ) -> String {
        guard information.displayName != relay.displayName else { return relay.detail }
        return "\(relay.displayName) · \(relay.detail)"
    }
}

enum RelayHeaderPresentation {
    static func title(relay: String?, information: NMPRelayInformationState) -> String {
        guard let relay else { return "Favorite Relays" }
        guard information.relay == relay else { return fallbackName(for: relay) }
        return information.displayName
    }

    private static func fallbackName(for relay: String) -> String {
        URL(string: relay)?.host ?? relay
    }
}

/// The app's media boundary for an untrusted NIP-11 `icon` string.
///
/// This intentionally accepts HTTPS URLs whose literal host is neither local
/// nor private. NMP preserves the exact advertised value but never
/// dereferences it; Kingfisher only sees a URL that passed this product-level
/// policy.
enum RelayIconURL {
    static func value(from advertised: String?) -> URL? {
        guard let advertised,
              let components = URLComponents(string: advertised),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              let host = components.host?.lowercased(),
              isPublicHost(host),
              let url = components.url
        else { return nil }
        return url
    }

    private static func isPublicHost(_ host: String) -> Bool {
        guard host.contains("."),
              !host.contains(":"),
              host != "localhost",
              !host.hasSuffix(".localhost"),
              !host.hasSuffix(".local"),
              !host.hasSuffix(".internal")
        else { return false }
        return !isPrivateIPv4Literal(host)
    }

    private static func isPrivateIPv4Literal(_ host: String) -> Bool {
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4,
              let first = UInt8(components[0]),
              let second = UInt8(components[1]),
              components.dropFirst(2).allSatisfy({ UInt8($0) != nil })
        else { return false }

        return switch (first, second) {
        case (0, _), (10, _), (100, 64...127), (127, _), (169, 254),
            (172, 16...31), (192, 168), (198, 18...19), (224...255, _):
            true
        default:
            false
        }
    }
}
