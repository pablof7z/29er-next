import Foundation
import NMP

struct RoomMessage: Identifiable, Hashable, Sendable {
    let id: String
    let author: String
    let createdAt: UInt64
    let content: String

    var authorLabel: String {
        PubkeyDisplay.shortHex(author)
    }
}

struct AgentActivity: Identifiable, Hashable, Sendable {
    let id: String
    let eventID: String
    let author: String
    let createdAt: UInt64
    let title: String
    let activity: String
    let isBusy: Bool
    let host: String?
    let slug: String?
    var authorLabel: String {
        if let slug, !slug.isEmpty { return slug }
        return PubkeyDisplay.shortHex(author)
    }

    var activityLabel: String {
        if !activity.isEmpty { return activity }
        return isBusy ? "Working" : "Idle"
    }
}

struct RoomMember: Identifiable, Hashable, Sendable {
    let id: String
    let pubkey: String
    var authorLabel: String {
        PubkeyDisplay.shortHex(pubkey)
    }
}

struct RoomPerson: Identifiable, Hashable, Sendable {
    let member: RoomMember?
    let activity: AgentActivity?
    let pubkey: String
    var id: String { pubkey }
    var authorLabel: String {
        activity?.authorLabel ?? member?.authorLabel ?? pubkey
    }
}

struct RoomPeople: Hashable, Sendable {
    let members: [RoomPerson]
    let activeHere: [RoomPerson]
}

enum NIP29ViewProjection {
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

    static func members(from rows: [Row]) -> [RoomMember] {
        var membersByPubkey: [String: RoomMember] = [:]

        for row in rows.sorted(by: newestRowFirst) {
            for member in members(kind: row.kind, tags: row.tags)
            where membersByPubkey[member.pubkey] == nil {
                membersByPubkey[member.pubkey] = member
            }
        }

        return membersByPubkey.values.sorted {
            $0.authorLabel.localizedCaseInsensitiveCompare($1.authorLabel) == .orderedAscending
        }
    }

    static func people(members: [RoomMember], activities: [AgentActivity]) -> RoomPeople {
        var latestActivityByPubkey: [String: AgentActivity] = [:]
        for activity in activities {
            guard let current = latestActivityByPubkey[activity.author] else {
                latestActivityByPubkey[activity.author] = activity
                continue
            }
            if activity.createdAt > current.createdAt ||
                (activity.createdAt == current.createdAt && activity.eventID > current.eventID) {
                latestActivityByPubkey[activity.author] = activity
            }
        }

        let memberPubkeys = Set(members.map(\.pubkey))
        let listed = members.map { member in
            RoomPerson(
                member: member,
                activity: latestActivityByPubkey[member.pubkey],
                pubkey: member.pubkey
            )
        }
        .sorted(by: personNameFirst)

        let activeHere = latestActivityByPubkey.values
            .filter { !memberPubkeys.contains($0.author) }
            .map { activity in
                RoomPerson(member: nil, activity: activity, pubkey: activity.author)
            }
            .sorted(by: activePersonFirst)

        return RoomPeople(members: listed, activeHere: activeHere)
    }

    /// Admin pubkeys from the room's kind:39001 admin lists. tenex-edge adds
    /// its backend management key as a group admin, so this is how the backend
    /// surfaces even when it is not in the kind:39002 member roster.
    static func admins(from rows: [Row]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for row in rows.sorted(by: newestRowFirst) {
            for pubkey in admins(kind: row.kind, tags: row.tags) where seen.insert(pubkey).inserted {
                result.append(pubkey)
            }
        }
        return result
    }

    static func admins(kind: UInt16, tags: [[String]]) -> [String] {
        guard kind == 39_001,
              let groupID = firstTag("d", in: tags),
              !groupID.isEmpty else {
            return []
        }
        return tags.compactMap { tag in
            guard tag.first == "p", tag.count > 1, !tag[1].isEmpty else { return nil }
            return tag[1]
        }
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
            createdAt: createdAt,
            title: firstTag("title", in: tags) ?? "",
            activity: content,
            isBusy: status == "busy",
            host: nonEmptyTag("host", in: tags),
            slug: nonEmptyTag("slug", in: tags)
        )
    }

    static func members(
        kind: UInt16,
        tags: [[String]]
    ) -> [RoomMember] {
        guard kind == 39_002,
              let groupID = firstTag("d", in: tags),
              !groupID.isEmpty else {
            return []
        }

        var seen = Set<String>()
        return tags.compactMap { tag in
            guard tag.first == "p", tag.count > 1, !tag[1].isEmpty, seen.insert(tag[1]).inserted else {
                return nil
            }
            return RoomMember(id: tag[1], pubkey: tag[1])
        }
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

    private static func newestRowFirst(_ lhs: Row, _ rhs: Row) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id > rhs.id
    }

    private static func personNameFirst(_ lhs: RoomPerson, _ rhs: RoomPerson) -> Bool {
        let comparison = lhs.authorLabel.localizedCaseInsensitiveCompare(rhs.authorLabel)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.pubkey < rhs.pubkey
    }

    private static func activePersonFirst(_ lhs: RoomPerson, _ rhs: RoomPerson) -> Bool {
        if lhs.activity?.isBusy != rhs.activity?.isBusy {
            return lhs.activity?.isBusy == true
        }
        return personNameFirst(lhs, rhs)
    }
}
