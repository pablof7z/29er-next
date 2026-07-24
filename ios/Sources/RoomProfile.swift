import Foundation
import NMP

/// One agent a tenex-edge backend advertises on its kind:0, as
/// `["agent", <slug>, <description>]`. `slug` is exactly what the backend's
/// `add <slug>` management command accepts, so it round-trips to a kind:9.
struct BackendAgent: Hashable, Sendable, Identifiable {
    let slug: String
    let description: String
    var id: String { slug }
}

/// A resolved kind:0 identity for display. The app only formats these raw
/// values; NMP owns acquisition and storage.
struct RoomProfile: Hashable, Sendable {
    let pubkey: String
    let displayName: String?
    let pictureURL: URL?
    /// A tenex-edge management backend advertises itself with a bare
    /// `["backend"]` tag on its kind:0; these are read from tags, not content.
    let isBackend: Bool
    /// The backend's host label (`["host", "laptop"]`), when present.
    let host: String?
    /// Top-level workspace channel (`["workspace", root]`) published by an
    /// agent session. Used only to render consistent workspace color.
    let workspace: String?
    /// Agents this backend manages (`["agent", slug, description]`).
    let agents: [BackendAgent]
}

/// Display resolution for a set of pubkeys: a kind:0 name/avatar when known,
/// otherwise the caller's shortened-hex fallback. Shared by the timeline and
/// the People roster so both surfaces resolve identity the same way.
struct ProfileBook: Hashable, Sendable {
    private let profiles: [String: RoomProfile]

    init(_ profiles: [String: RoomProfile] = [:]) {
        self.profiles = profiles
    }

    func displayName(for pubkey: String, fallback: String) -> String {
        name(for: pubkey) ?? fallback
    }

    /// The kind:0 display name for `pubkey`, or `nil` when no profile has
    /// arrived yet (unlike `displayName(for:fallback:)`, which always
    /// returns something displayable).
    func name(for pubkey: String) -> String? {
        guard let name = profiles[pubkey]?.displayName, !name.isEmpty else { return nil }
        return name
    }

    func pictureURL(for pubkey: String) -> URL? {
        profiles[pubkey]?.pictureURL
    }

    func workspace(for pubkey: String) -> String? {
        profiles[pubkey]?.workspace
    }

    func profile(for pubkey: String) -> RoomProfile? {
        profiles[pubkey]
    }
}

enum RoomProfileProjection {
    /// Canonical kind:0 values delivered by NMP. Swift does not apply a second
    /// timestamp/replacement policy; a repeated pubkey would be an upstream
    /// delivery-contract violation, so the first canonical value is retained.
    static func profiles(from rows: [Row]) -> ProfileBook {
        var profilesByPubkey: [String: RoomProfile] = [:]
        for row in rows where row.kind == 0 && profilesByPubkey[row.pubkey] == nil {
            profilesByPubkey[row.pubkey] = profile(from: row)
        }
        return ProfileBook(profilesByPubkey)
    }

    static func profile(from row: Row) -> RoomProfile {
        profile(pubkey: row.pubkey, content: row.content, tags: row.tags)
    }

    static func profile(pubkey: String, content: String, tags: [[String]]) -> RoomProfile {
        let metadata = Metadata(json: content)
        let hostTag = tags.first { $0.first == "host" && $0.count > 1 }
        let host = hostTag.map { $0[1] }.flatMap { $0.isEmpty ? nil : $0 }
        let workspaceTag = tags.first { $0.first == "workspace" && $0.count > 1 }
        let workspace = workspaceTag.map { $0[1] }.flatMap { $0.isEmpty ? nil : $0 }
        return RoomProfile(
            pubkey: pubkey,
            displayName: metadata.displayName,
            pictureURL: metadata.pictureURL,
            isBackend: tags.contains { $0.first == "backend" },
            host: host,
            workspace: workspace,
            agents: backendAgents(from: tags)
        )
    }

    /// `["agent", slug, description]` tags, in declared order, ignoring
    /// malformed entries and empty slugs. Description defaults to empty.
    private static func backendAgents(from tags: [[String]]) -> [BackendAgent] {
        tags.compactMap { tag in
            guard tag.first == "agent", tag.count > 1, !tag[1].isEmpty else { return nil }
            let description = tag.count > 2 ? tag[2] : ""
            return BackendAgent(slug: tag[1], description: description)
        }
    }

    private struct Metadata {
        let displayName: String?
        let pictureURL: URL?

        init(json: String) {
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                displayName = nil
                pictureURL = nil
                return
            }

            let display = Metadata.string(object["display_name"]) ?? Metadata.string(object["displayName"])
            displayName = display ?? Metadata.string(object["name"])
            pictureURL = Metadata.string(object["picture"]).flatMap(URL.init(string:))
        }

        private static func string(_ value: Any?) -> String? {
            guard let text = value as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
