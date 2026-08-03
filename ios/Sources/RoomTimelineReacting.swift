import Foundation
import NMP

extension RoomTimelineModel {
    /// Publish a NIP-25 kind:7 reaction to `message` through NMP's NIP-29
    /// publication gate.
    ///
    /// The `h` row and the routing to this group's host are NMP's -- the app
    /// supplies the reaction's own NIP-25 tags and nothing else. It used to
    /// hand-build both, and route a group-scoped event to the author's outbox.
    func reactToMessage(_ message: RoomMessage, emoji: String) async -> String? {
        guard let viewer = recipient else { return "Sign in to react." }

        do {
            let status = try roomGroup(host: hostRelay, groupID: groupID).publish(
                engine: engine,
                authorPubkeyHex: viewer,
                kind: RoomKind.reaction,
                tags: [["e", message.id], ["p", message.author]],
                content: emoji
            )
            // Returns on `.accepted`, not `.acked`: an accepted write is
            // already in NMP's canonical store and therefore already in this
            // room's live query. Waiting for a relay acknowledgement kept a
            // spinner up over a reaction the user could already see.
            for try await frame in status {
                if let failure = WriteFailureText.message(for: frame, subject: "reaction") {
                    return failure
                }
                if case .accepted = frame { return nil }
            }
            return "Reaction delivery ended before NMP accepted it."
        } catch {
            return error.localizedDescription
        }
    }
}
