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

struct RoomPerson: Identifiable, Hashable, Sendable {
    let activity: AgentActivity?
    let pubkey: String
    var id: String { pubkey }
    var authorLabel: String {
        activity?.authorLabel ?? PubkeyDisplay.shortHex(pubkey)
    }
}

struct RoomPeople: Hashable, Sendable {
    let members: [RoomPerson]
    let activeHere: [RoomPerson]

    func activity(for pubkey: String) -> AgentActivity? {
        members.first(where: { $0.pubkey == pubkey })?.activity
            ?? activeHere.first(where: { $0.pubkey == pubkey })?.activity
    }
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

    /// Joins the room's listed members to their live sessions.
    ///
    /// Takes pubkeys, not NMP's `NMPListedSubject`, because that is all the
    /// join needs -- the subjects themselves stay on the model in the shape
    /// NMP delivered them, unwrapped into no app-owned roster type.
    static func people(memberPubkeys: [String], activities: [AgentActivity]) -> RoomPeople {
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

        let listedPubkeys = Set(memberPubkeys)
        let listed = listedPubkeys.map { pubkey in
            RoomPerson(activity: latestActivityByPubkey[pubkey], pubkey: pubkey)
        }
        .sorted(by: personNameFirst)

        let activeHere = latestActivityByPubkey.values
            .filter { !listedPubkeys.contains($0.author) }
            .map { activity in
                RoomPerson(activity: activity, pubkey: activity.author)
            }
            .sorted(by: activePersonFirst)

        return RoomPeople(members: listed, activeHere: activeHere)
    }

    static func message(
        eventID: String,
        pubkey: String,
        createdAt: UInt64,
        kind: UInt16,
        content: String
    ) -> RoomMessage? {
        guard kind == RoomKind.chat else { return nil }
        return RoomMessage(id: eventID, author: pubkey, createdAt: createdAt, content: content)
    }

    // Mirrors the immutable fields needed from NMP Row without fabricating a
    // constructible raw event. NMP #45 owns the eventual typed activity input.
    // swiftlint:disable:next function_parameter_count
    static func activity(
        eventID: String,
        pubkey: String,
        createdAt: UInt64,
        kind: UInt16,
        tags: [[String]],
        content: String
    ) -> AgentActivity? {
        guard kind == RoomKind.liveStatus,
              let sessionID = firstTag("d", in: tags),
              !sessionID.isEmpty,
              // The live-status heartbeat carries its working/idle/suspended/
              // offline value on a tag literally named "state" -- the "d" tag's
              // own value is unrelated and happens to read "status" in today's
              // producer, which is not the same thing.
              let state = firstTag("state", in: tags),
              ["working", "idle", "suspended", "offline"].contains(state),
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
            isBusy: state == "working",
            host: nonEmptyTag("host", in: tags),
            slug: nonEmptyTag("slug", in: tags)
        )
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

    // kind:30315 is NIP-38 live status, not a NIP-29 group record. These two
    // rows are read here because NMP owns no live-status door (NMP #45); they
    // deliberately do not share a helper with the group-records path, which
    // no longer parses anything.
    private static func firstTag(_ name: String, in tags: [[String]]) -> String? {
        tags.first { $0.first == name && $0.count > 1 }?[1]
    }

    private static func nonEmptyTag(_ name: String, in tags: [[String]]) -> String? {
        firstTag(name, in: tags).flatMap { $0.isEmpty ? nil : $0 }
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
