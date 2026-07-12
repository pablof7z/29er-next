import Foundation

/// A tenex-edge management backend present in this room (identified by a
/// `["backend"]` tag on its kind:0), plus the agents it advertises. Tapping one
/// issues management commands as kind:9 chat directed at `pubkey`.
struct RoomBackend: Identifiable, Hashable, Sendable {
    let pubkey: String
    let label: String
    let agents: [BackendAgent]
    var id: String { pubkey }
}

enum RoomBackendProjection {
    /// Backends among `candidatePubkeys` (members, admins, live-session
    /// authors): those whose resolved kind:0 carries a `["backend"]` tag.
    /// Ordered by label, deduplicated by pubkey.
    static func backends(candidatePubkeys: [String], profiles: ProfileBook) -> [RoomBackend] {
        var seen = Set<String>()
        var result: [RoomBackend] = []
        for pubkey in candidatePubkeys where seen.insert(pubkey).inserted {
            guard let profile = profiles.profile(for: pubkey), profile.isBackend else { continue }
            let label = profile.host ?? profile.displayName ?? shortHex(pubkey)
            result.append(RoomBackend(pubkey: pubkey, label: label, agents: profile.agents))
        }
        return result.sorted { lhs, rhs in
            let comparison = lhs.label.localizedCaseInsensitiveCompare(rhs.label)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.pubkey < rhs.pubkey
        }
    }

    private static func shortHex(_ pubkey: String) -> String {
        pubkey.count > 16 ? "\(pubkey.prefix(8))…\(pubkey.suffix(8))" : pubkey
    }
}
