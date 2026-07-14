import NMP

enum RoomMembershipChange: Hashable, Sendable {
    case joined
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

    static func membershipEvent(
        eventID: String,
        createdAt: UInt64,
        kind: UInt16,
        tags: [[String]]
    ) -> RoomMembershipEvent? {
        let change: RoomMembershipChange
        switch kind {
        case 9_000: change = .joined
        case 9_001: change = .left
        default: return nil
        }

        guard let pubkey = tags.first(where: {
            $0.first == "p" && $0.count > 1 && !$0[1].isEmpty
        })?[1] else {
            return nil
        }

        return RoomMembershipEvent(
            id: eventID,
            pubkey: pubkey,
            createdAt: createdAt,
            change: change
        )
    }
}
