import NMP

/// What a NIP-29 membership event actually says.
///
/// The four kinds are two different sentences with two different subjects.
/// kind:9000 put-user and kind:9001 remove-user are MODERATION: somebody with
/// authority acted on the person named in the event's `p` tag. kind:9021
/// join-request and kind:9022 leave-request are SELF-SERVICE: the event's own
/// author acted on themselves and there is no `p` tag at all. NMP names all
/// four in `crates/nmp-nip29/src/operations.rs`.
enum RoomMembershipChange: Hashable, Sendable {
    /// kind:9000 -- a moderator added this person to the room.
    case added
    /// kind:9001 -- a moderator removed this person from the room.
    case removed
    /// kind:9021 -- this person asked to join.
    case joined
    /// kind:9022 -- this person left.
    case left
}

struct RoomMembershipEvent: Identifiable, Hashable, Sendable {
    let id: String
    let pubkey: String
    let createdAt: UInt64
    let change: RoomMembershipChange

    var personLabel: String {
        PubkeyDisplay.shortHex(pubkey)
    }
}

enum RoomTimelineItem: Identifiable, Hashable, Sendable {
    case message(RoomMessage)
    case membership(RoomMembershipEvent)

    var id: String {
        switch self {
        case .message(let message): message.id
        case .membership(let event): event.id
        }
    }

    var createdAt: UInt64 {
        switch self {
        case .message(let message): message.createdAt
        case .membership(let event): event.createdAt
        }
    }

    var message: RoomMessage? {
        guard case .message(let message) = self else { return nil }
        return message
    }
}

extension NIP29ViewProjection {
    static func timelineItems(from rows: [Row]) -> [RoomTimelineItem] {
        rows.compactMap { row in
            if let message = message(
                eventID: row.id,
                pubkey: row.pubkey,
                createdAt: row.createdAt,
                kind: row.kind,
                content: row.content
            ) {
                return .message(message)
            }
            return membershipEvent(
                eventID: row.id,
                author: row.pubkey,
                createdAt: row.createdAt,
                kind: row.kind,
                tags: row.tags
            ).map(RoomTimelineItem.membership)
        }
        .sorted {
            if $0.createdAt == $1.createdAt { return $0.id < $1.id }
            return $0.createdAt < $1.createdAt
        }
    }

    /// The subject of a moderation event is its `p` tag; the subject of a
    /// self-service event is `author`, which is the only person a 9021/9022
    /// can be about.
    static func membershipEvent(
        eventID: String,
        author: String,
        createdAt: UInt64,
        kind: UInt16,
        tags: [[String]]
    ) -> RoomMembershipEvent? {
        let change: RoomMembershipChange
        let subject: String?

        switch kind {
        case RoomKind.putUser:
            change = .added
            subject = moderationSubject(in: tags)
        case RoomKind.removeUser:
            change = .removed
            subject = moderationSubject(in: tags)
        case RoomKind.joinRequest:
            change = .joined
            subject = author.isEmpty ? nil : author
        case RoomKind.leaveRequest:
            change = .left
            subject = author.isEmpty ? nil : author
        default:
            return nil
        }

        guard let subject else { return nil }
        return RoomMembershipEvent(
            id: eventID,
            pubkey: subject,
            createdAt: createdAt,
            change: change
        )
    }

    private static func moderationSubject(in tags: [[String]]) -> String? {
        tags.first {
            $0.first == "p" && $0.count > 1 && !$0[1].isEmpty
        }?[1]
    }
}
