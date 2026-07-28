import Foundation

/// A room agent the user can address from the composer. The visible label is
/// presentation-only; the pubkey is the semantic recipient sent to NMP.
struct ComposerRecipient: Identifiable, Hashable, Sendable {
    let pubkey: String
    let displayName: String
    let pictureURL: URL?
    let activity: AgentActivity?

    var id: String { pubkey }

    var mentionLabel: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.drop(while: { $0 == "@" })
        return "@\(label.isEmpty ? PubkeyDisplay.shortHex(pubkey) : String(label))"
    }

    var activitySummary: String? {
        guard let activity else { return nil }
        let title = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let detail = activity.activity.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? activity.activityLabel : detail
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
    let attachments: [ComposerAttachment]
}

enum ChatComposerState {
    static func message(from draft: String) -> String? {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }

    static func request(
        draft: String,
        selectedRecipients: [ComposerRecipient],
        reply: ComposerReply?,
        attachments: [ComposerAttachment] = []
    ) -> ComposerRequest? {
        let content = message(from: draft) ?? ""
        guard !content.isEmpty || !attachments.isEmpty else { return nil }

        return ComposerRequest(
            content: content,
            recipients: recipients(selectedRecipients: selectedRecipients, reply: reply),
            reply: reply,
            attachments: attachments
        )
    }

    static func showsVoiceAction(draft: String, attachments: [ComposerAttachment]) -> Bool {
        message(from: draft) == nil && attachments.isEmpty
    }

    static func messageContent(draft: String, attachmentURLs: [URL]) -> String? {
        let content = message(from: draft)
        let urls = attachmentURLs.map(\.absoluteString)
        guard content != nil || !urls.isEmpty else { return nil }
        guard let content else { return urls.joined(separator: "\n") }
        guard !urls.isEmpty else { return content }
        return content + "\n\n" + urls.joined(separator: "\n")
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

    /// True once every pickable recipient is already tagged. A
    /// `requiredRecipientID` (the reply author, if any) always counts as
    /// selected even if `selectedRecipients` doesn't literally contain it.
    static func everyoneIsSelected(
        pickable: [ComposerRecipient],
        selectedRecipients: [ComposerRecipient],
        requiredRecipientID: String?
    ) -> Bool {
        pickable.allSatisfy { recipient in
            recipient.id == requiredRecipientID
                || selectedRecipients.contains { $0.id == recipient.id }
        }
    }

    /// Toggles a bulk "@everyone" selection: tags every pickable recipient at
    /// once (the same result as tapping each row individually, so it's
    /// ordinary per-person mentions, not a new "everyone" concept at the
    /// protocol level), or -- if everyone is already tagged -- clears back
    /// down to just the required recipient, if any.
    static func togglingEveryone(
        pickable: [ComposerRecipient],
        selectedRecipients: [ComposerRecipient],
        requiredRecipientID: String?
    ) -> [ComposerRecipient] {
        if everyoneIsSelected(
            pickable: pickable,
            selectedRecipients: selectedRecipients,
            requiredRecipientID: requiredRecipientID
        ) {
            return selectedRecipients.filter { $0.id == requiredRecipientID }
        }
        var updated = selectedRecipients
        for recipient in pickable where !updated.contains(where: { $0.id == recipient.id }) {
            updated.append(recipient)
        }
        return updated
    }
}
