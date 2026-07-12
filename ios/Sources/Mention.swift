import Foundation
import NMP

/// One kind:9 message that p-tags the active user, projected for the inbox.
/// Carries the source room (`h` tag) so the inbox can deep-link into it, and
/// the raw values the app formats for display. NMP owns acquisition; the app
/// only decides that "a chat message p-tagging me" is a mention.
struct Mention: Identifiable, Hashable, Sendable {
    let id: String
    let author: String
    let createdAt: UInt64
    let content: String
    let groupLocalID: String

    var authorLabel: String {
        PubkeyDisplay.shortHex(author)
    }
}

enum MentionProjection {
    /// kind:9 rows that p-tag `recipient`, newest first. Self-authored messages
    /// are excluded (you are not your own mention), and rows without an `h` tag
    /// are dropped because there is no room to open for them.
    static func mentions(from rows: [Row], recipient: String) -> [Mention] {
        rows.compactMap { mention(from: $0, recipient: recipient) }
            .sorted {
                if $0.createdAt == $1.createdAt { return $0.id > $1.id }
                return $0.createdAt > $1.createdAt
            }
    }

    /// Event ids of the given rows that are mentions of `recipient`. Used by a
    /// room to recognise which of its on-screen messages mention the user.
    static func mentionIDs(from rows: [Row], recipient: String) -> Set<String> {
        Set(rows.compactMap { mention(from: $0, recipient: recipient)?.id })
    }

    static func mention(from row: Row, recipient: String) -> Mention? {
        mention(
            id: row.id,
            pubkey: row.pubkey,
            createdAt: row.createdAt,
            kind: row.kind,
            tags: row.tags,
            content: row.content,
            recipient: recipient
        )
    }

    static func mention(
        id: String,
        pubkey: String,
        createdAt: UInt64,
        kind: UInt16,
        tags: [[String]],
        content: String,
        recipient: String
    ) -> Mention? {
        guard kind == 9,
              pubkey != recipient,
              pTags(tags).contains(recipient),
              let group = firstTag("h", in: tags) else {
            return nil
        }
        return Mention(
            id: id,
            author: pubkey,
            createdAt: createdAt,
            content: content,
            groupLocalID: group
        )
    }

    static func pTags(_ tags: [[String]]) -> Set<String> {
        Set(tags.compactMap { tag in
            tag.first == "p" && tag.count > 1 && !tag[1].isEmpty ? tag[1] : nil
        })
    }

    private static func firstTag(_ name: String, in tags: [[String]]) -> String? {
        tags.first { $0.first == name && $0.count > 1 && !$0[1].isEmpty }?[1]
    }
}
