import NMP

/// One NIP-25 kind:7 reaction to a room message.
struct RoomReaction: Hashable, Sendable {
    let messageID: String
    let author: String
    let emoji: String
}

/// One message's reaction tally for a single emoji.
struct RoomReactionGroup: Hashable, Sendable, Identifiable {
    let emoji: String
    let count: Int
    let reactedByViewer: Bool
    var id: String { emoji }
}

enum RoomReactionProjection {
    static func reactions(from rows: [Row]) -> [RoomReaction] {
        rows.compactMap(reaction(from:))
    }

    private static func reaction(from row: Row) -> RoomReaction? {
        guard row.kind == 7,
              let target = row.tags.last(where: { $0.first == "e" && $0.count > 1 }) else {
            return nil
        }
        return RoomReaction(messageID: target[1], author: row.pubkey, emoji: emoji(for: row.content))
    }

    /// NIP-25: bare `+`/empty content is a like (shown as a heart); `-` is a
    /// dislike; anything else is the literal reaction content, by
    /// convention a single emoji.
    private static func emoji(for content: String) -> String {
        switch content {
        case "", "+": return "❤️"
        case "-": return "👎"
        default: return content
        }
    }

    /// Per-message emoji tallies, deduplicated so a repeated reaction from
    /// the same author with the same emoji counts once, keyed by message id.
    static func summaries(from reactions: [RoomReaction], viewer: String?) -> [String: [RoomReactionGroup]] {
        Dictionary(grouping: reactions, by: \.messageID).mapValues { messageReactions in
            Dictionary(grouping: messageReactions, by: \.emoji).map { emoji, group in
                let authors = Set(group.map(\.author))
                return RoomReactionGroup(
                    emoji: emoji,
                    count: authors.count,
                    reactedByViewer: viewer.map(authors.contains) ?? false
                )
            }.sorted { $0.emoji < $1.emoji }
        }
    }
}
