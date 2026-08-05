import Foundation
import NMP

extension RoomTimelineModel {
    /// Publish a NIP-25 kind:7 reaction to `message` through NMP's NIP-29
    /// publication gate.
    ///
    /// The `h` row and the routing to this group's host are NMP's -- the app
    /// supplies the reaction's own NIP-25 tags and nothing else. It used to
    /// hand-build both, and route a group-scoped event to the author's outbox.
    ///
    /// NIP-25's own rows are the last thing here that is not NMP's. There is
    /// no reaction door on the facade at all -- no composer and no typed
    /// decode -- so the `e`/`p` pair is stated here (nmp#155). Delete it the
    /// moment one lands.
    ///
    /// Returns the moment NMP takes the reaction, because that is the moment
    /// it is in the store and in this room's live query. A reaction that
    /// later settles badly reports through `writeFailure`, not through a
    /// spinner over an emoji the reader can already see.
    func reactToMessage(_ message: RoomMessage, emoji: String) -> String? {
        guard let viewer = recipient else { return "Sign in to react." }

        do {
            let receipt = try roomGroup(host: hostRelay, groupID: groupID).publish(
                engine: engine,
                authorPubkeyHex: viewer,
                kind: RoomKind.reaction,
                tags: [["e", message.id], ["p", message.author]],
                content: emoji
            )
            watchWrite(receipt, subject: "reaction")
            return nil
        } catch {
            return WriteFailureText.startFailure(error, action: "reaction")
        }
    }
}
