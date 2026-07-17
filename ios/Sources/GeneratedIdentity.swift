import Foundation
import NMP

struct GeneratedIdentityProfile: Codable, Equatable {
    let pubkey: String
    let name: String
    let avatarURL: URL

    static func make(pubkey: String) -> Self {
        let bytes = stride(from: 0, to: min(pubkey.count, 12), by: 2).compactMap { offset in
            let start = pubkey.index(pubkey.startIndex, offsetBy: offset)
            let end = pubkey.index(start, offsetBy: min(2, pubkey.distance(from: start, to: pubkey.endIndex)))
            return UInt8(pubkey[start..<end], radix: 16)
        }
        let adjectives = ["Bright", "Calm", "Copper", "Kind", "Lucky", "Merry", "Swift", "Wild"]
        let nouns = ["Albatross", "Dolphin", "Heron", "Marlin", "Otter", "Petrel", "Skipper", "Tern"]
        let adjective = adjectives[Int(bytes.first ?? 0) % adjectives.count]
        let noun = nouns[Int(bytes.dropFirst().first ?? 0) % nouns.count]
        let suffix = pubkey.prefix(4).uppercased()
        let seed = String(pubkey.prefix(16))
        let avatar = URL(string: "https://api.dicebear.com/9.x/shapes/png?seed=\(seed)")!
        return Self(pubkey: pubkey, name: "\(adjective) \(noun) \(suffix)", avatarURL: avatar)
    }

    func profileIntent(createdAt: UInt64) throws -> WriteIntent {
        let content = try JSONSerialization.data(
            withJSONObject: ["name": name, "display_name": name, "picture": avatarURL.absoluteString],
            options: [.sortedKeys]
        )
        return WriteIntent(
            payload: .unsigned(
                pubkey: pubkey,
                createdAt: createdAt,
                kind: 0,
                tags: [],
                content: String(decoding: content, as: UTF8.self)
            ),
            durability: .durable,
            routing: .authorOutbox,
            identityOverride: pubkey
        )
    }
}

struct GeneratedIdentityProfileStore {
    let fileURL: URL

    func load(matching pubkey: String?) -> GeneratedIdentityProfile? {
        guard let pubkey,
              let data = try? Data(contentsOf: fileURL),
              let profile = try? JSONDecoder().decode(GeneratedIdentityProfile.self, from: data),
              profile.pubkey == pubkey else { return nil }
        return profile
    }

    func save(_ profile: GeneratedIdentityProfile) throws {
        let data = try JSONEncoder().encode(profile)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
