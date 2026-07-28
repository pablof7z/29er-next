import Foundation
import NMP

extension RoomTimelineModel {
    /// Publish a NIP-25 kind:7 reaction to `message`. NMP has no dedicated
    /// reaction-intent helper yet, so this composes the raw `WriteIntent`
    /// directly -- `h`-tagged to this room so `roomReactionsDemand` (the
    /// same `h`-scoped read this model already observes) picks it back up.
    func reactToMessage(_ message: RoomMessage, emoji: String) async -> String? {
        guard let viewer = recipient else {
            return finishReaction(failure: "Sign in to react.")
        }
        reactionDeliveryFailure = nil

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
            defer { receipt.status.cancel() }
            var convergence = MessageReceiptConvergence()
            for try await status in receipt.status {
                guard !Task.isCancelled else { return nil }
                _ = convergence.apply(status, receiptID: receipt.id)
            }
            guard !Task.isCancelled else { return nil }
            guard let finalState = convergence.stateAfterStreamClosed(receiptID: receipt.id) else {
                return finishReaction(
                    failure: "Reaction delivery ended without a terminal NMP outcome."
                )
            }
            return finishReaction(failure: finalState.failureMessage)
        } catch {
            guard !Task.isCancelled else { return nil }
            return finishReaction(failure: error.localizedDescription)
        }
    }

    private func finishReaction(failure: String?) -> String? {
        reactionDeliveryFailure = failure
        return failure
    }
}
