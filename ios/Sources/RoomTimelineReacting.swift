import Foundation
import NMP

extension RoomTimelineModel {
    /// Publish a NIP-25 kind:7 reaction to `message`. NMP has no dedicated
    /// reaction-intent helper yet, so this composes the raw `WriteIntent`
    /// directly -- `h`-tagged to this room so `roomReactionsDemand` (the
    /// same `h`-scoped read this model already observes) picks it back up.
    func reactToMessage(_ message: RoomMessage, emoji: String) async -> String? {
        guard let viewer = recipient else { return "Sign in to react." }

        do {
            let intent = WriteIntent(
                payload: .unsigned(
                    pubkey: viewer,
                    createdAt: UInt64(Date().timeIntervalSince1970),
                    kind: 7,
                    tags: [["e", message.id], ["p", message.author], ["h", groupID]],
                    content: emoji
                ),
                durability: .durable,
                routing: .authorOutbox
            )
            let receipt = try await engine.publish(intent)
            for try await status in receipt.status {
                if let failure = deliveryFailure(for: status) { return failure }
                if case .acked = status { return nil }
            }
            return "Reaction delivery ended without relay acknowledgement."
        } catch {
            return error.localizedDescription
        }
    }
}
