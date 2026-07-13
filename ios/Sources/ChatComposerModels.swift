import Foundation

/// A room agent the user can address from the composer. The visible label is
/// presentation-only; the pubkey is the semantic recipient sent to NMP.
struct ComposerRecipient: Identifiable, Hashable, Sendable {
    let pubkey: String
    let displayName: String
    let pictureURL: URL?

    var id: String { pubkey }

    var mentionLabel: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.drop(while: { $0 == "@" })
        return "@\(label.isEmpty ? PubkeyDisplay.shortHex(pubkey) : String(label))"
    }
}

/// The message selected by tapping a timeline row. Preview and display label
/// stay local; NMP receives only the immutable direct-parent identity.
struct ComposerReply: Identifiable, Hashable, Sendable {
    let eventID: String
    let author: ComposerRecipient
    let preview: String

    var id: String { eventID }
}

/// Structured app intent. At send time NMP's codec canonicalizes npubs and its
/// group composer adds NIP-29 context before publication.
struct ComposerRequest: Equatable, Sendable {
    let content: String
    let recipients: [ComposerRecipient]
    let reply: ComposerReply?
}

enum ChatComposerState {
    static func message(from draft: String) -> String? {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }

    static func request(
        draft: String,
        selectedRecipients: [ComposerRecipient],
        reply: ComposerReply?
    ) -> ComposerRequest? {
        guard let content = message(from: draft) else { return nil }

        return ComposerRequest(
            content: content,
            recipients: recipients(selectedRecipients: selectedRecipients, reply: reply),
            reply: reply
        )
    }

    static func recipients(
        selectedRecipients: [ComposerRecipient],
        reply: ComposerReply?
    ) -> [ComposerRecipient] {
        var seen = Set<String>()
        var recipients: [ComposerRecipient] = []
        if let reply, seen.insert(reply.author.pubkey).inserted {
            recipients.append(reply.author)
        }
        for recipient in selectedRecipients where seen.insert(recipient.pubkey).inserted {
            recipients.append(recipient)
        }
        return recipients
    }
}
