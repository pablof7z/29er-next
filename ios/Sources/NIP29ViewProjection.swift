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

struct AgentActivity: Identifiable, Hashable, Sendable {
    let id: String
    let eventID: String
    let author: String
    let sessionID: String
    let title: String
    let activity: String
    let isBusy: Bool
    let host: String?
    let slug: String?
    let relativeWorkingDirectory: String?
    let expiresAt: UInt64

    var authorLabel: String {
        if let slug, !slug.isEmpty { return slug }
        guard author.count > 16 else { return author }
        return "\(author.prefix(8))…\(author.suffix(8))"
    }

    var activityLabel: String {
        if !activity.isEmpty { return activity }
        return isBusy ? "Working" : "Idle"
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

    static func activities(from rows: [Row]) -> [AgentActivity] {
        rows.compactMap(activity(from:))
            .sorted {
                if $0.isBusy != $1.isBusy { return $0.isBusy }
                if $0.title != $1.title {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.id < $1.id
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

    static func activity(
        eventID: String,
        pubkey: String,
        createdAt: UInt64,
        kind: UInt16,
        tags: [[String]],
        content: String
    ) -> AgentActivity? {
        guard kind == 30_315,
              let sessionID = firstTag("d", in: tags),
              !sessionID.isEmpty,
              let status = firstTag("status", in: tags),
              status == "busy" || status == "idle",
              let expirationValue = firstTag("expiration", in: tags),
              let expiresAt = UInt64(expirationValue),
              expiresAt >= createdAt else {
            return nil
        }

        return AgentActivity(
            id: "\(pubkey):\(sessionID)",
            eventID: eventID,
            author: pubkey,
            sessionID: sessionID,
            title: firstTag("title", in: tags) ?? "",
            activity: content,
            isBusy: status == "busy",
            host: nonEmptyTag("host", in: tags),
            slug: nonEmptyTag("slug", in: tags),
            relativeWorkingDirectory: nonEmptyTag("rel-cwd", in: tags),
            expiresAt: expiresAt
        )
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

    private static func activity(from row: Row) -> AgentActivity? {
        activity(
            eventID: row.id,
            pubkey: row.pubkey,
            createdAt: row.createdAt,
            kind: row.kind,
            tags: row.tags,
            content: row.content
        )
    }

    private static func firstTag(_ name: String, in tags: [[String]]) -> String? {
        tags.first { $0.first == name && $0.count > 1 }?[1]
    }

    private static func nonEmptyTag(_ name: String, in tags: [[String]]) -> String? {
        firstTag(name, in: tags).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func containsMarker(_ name: String, in tags: [[String]]) -> Bool {
        tags.contains { $0.first == name }
    }
}
