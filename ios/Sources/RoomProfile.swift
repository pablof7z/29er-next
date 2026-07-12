import Foundation
import NMP

/// A resolved kind:0 identity for display. The app only formats these raw
/// values; NMP owns acquisition and storage.
struct RoomProfile: Hashable, Sendable {
    let pubkey: String
    let displayName: String?
    let pictureURL: URL?
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
        guard let name = profiles[pubkey]?.displayName, !name.isEmpty else { return fallback }
        return name
    }

    func pictureURL(for pubkey: String) -> URL? {
        profiles[pubkey]?.pictureURL
    }
}

enum RoomProfileProjection {
    /// Latest kind:0 per author (rows already de-duplicated by NMP; we still
    /// keep the newest by createdAt defensively).
    static func profiles(from rows: [Row]) -> ProfileBook {
        var latestRowByPubkey: [String: Row] = [:]
        for row in rows where row.kind == 0 {
            if let current = latestRowByPubkey[row.pubkey], current.createdAt >= row.createdAt {
                continue
            }
            latestRowByPubkey[row.pubkey] = row
        }

        return ProfileBook(latestRowByPubkey.mapValues(profile(from:)))
    }

    static func profile(from row: Row) -> RoomProfile {
        let metadata = Metadata(json: row.content)
        return RoomProfile(
            pubkey: row.pubkey,
            displayName: metadata.displayName,
            pictureURL: metadata.pictureURL
        )
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
