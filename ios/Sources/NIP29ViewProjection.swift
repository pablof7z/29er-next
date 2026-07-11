import Foundation
import NMP

struct GroupSummary: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let about: String?
    let pictureURL: URL?
    let isPublic: Bool
    let isOpen: Bool

    var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let value = words.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "#" : value.uppercased()
    }
}

struct RoomMessage: Identifiable, Hashable, Sendable {
    let id: String
    let author: String
    let createdAt: UInt64
    let content: String

    var authorLabel: String {
        guard author.count > 16 else { return author }
        return "\(author.prefix(8))…\(author.suffix(8))"
    }
}

enum NIP29ViewProjection {
    static func groups(from rows: [Row]) -> [GroupSummary] {
        rows.compactMap(group(from:))
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    static func messages(from rows: [Row]) -> [RoomMessage] {
        rows.compactMap(message(from:))
            .sorted {
                if $0.createdAt == $1.createdAt { return $0.id < $1.id }
                return $0.createdAt < $1.createdAt
            }
    }

    static func group(
        eventID: String,
        kind: UInt16,
        tags: [[String]]
    ) -> GroupSummary? {
        guard kind == 39_000, let groupID = firstTag("d", in: tags), !groupID.isEmpty else {
            return nil
        }
        let name = firstTag("name", in: tags).flatMap { $0.isEmpty ? nil : $0 } ?? groupID
        let about = firstTag("about", in: tags).flatMap { $0.isEmpty ? nil : $0 }
        let pictureURL = firstTag("picture", in: tags).flatMap(URL.init(string:))
        return GroupSummary(
            id: groupID,
            name: name,
            about: about,
            pictureURL: pictureURL,
            isPublic: containsMarker("public", in: tags),
            isOpen: containsMarker("open", in: tags)
        )
    }

    static func message(
        eventID: String,
        pubkey: String,
        createdAt: UInt64,
        kind: UInt16,
        content: String
    ) -> RoomMessage? {
        guard kind == 9 else { return nil }
        return RoomMessage(id: eventID, author: pubkey, createdAt: createdAt, content: content)
    }

    private static func group(from row: Row) -> GroupSummary? {
        group(eventID: row.id, kind: row.kind, tags: row.tags)
    }

    private static func message(from row: Row) -> RoomMessage? {
        message(
            eventID: row.id,
            pubkey: row.pubkey,
            createdAt: row.createdAt,
            kind: row.kind,
            content: row.content
        )
    }

    private static func firstTag(_ name: String, in tags: [[String]]) -> String? {
        tags.first { $0.first == name && $0.count > 1 }?[1]
    }

    private static func containsMarker(_ name: String, in tags: [[String]]) -> Bool {
        tags.contains { $0.first == name }
    }
}
