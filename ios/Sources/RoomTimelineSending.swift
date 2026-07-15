import Foundation
import NMP

extension RoomTimelineModel {
    /// The canonical accepted event returns through `observeChat`; this never
    /// creates an app-owned pending-message mirror.
    func sendMessage(_ request: ComposerRequest) async -> String? {
        let uploader = BlossomAttachmentUploader(engine: engine)
        var attachmentURLs: [URL] = []
        do {
            for attachment in request.attachments {
                try Task.checkCancellation()
                attachmentURLs.append(try await uploader.upload(attachment, to: hostRelay))
            }
        } catch {
            return error.localizedDescription
        }
        guard let content = ChatComposerState.messageContent(
            draft: request.content,
            attachmentURLs: attachmentURLs
        ) else {
            return "Messages cannot be empty."
        }
        return await sendGroupMessage(
            content,
            recipientPubkeys: request.recipients.map(\.pubkey),
            reply: request.reply
        )
    }

    func sendManagementCommand(_ command: String, backendPubkey: String) async -> String? {
        await sendGroupMessage(command, recipientPubkeys: [backendPubkey], reply: nil)
    }

    private func sendGroupMessage(
        _ content: String,
        recipientPubkeys: [String],
        reply: ComposerReply?
    ) async -> String? {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Messages cannot be empty."
        }

        do {
            let replyParent = reply.map {
                GroupReplyParent(eventID: $0.eventID, authorPubkey: $0.author.pubkey)
            }
            let intent = try engine.groupMessageIntent(
                host: hostRelay,
                groupID: groupID,
                content: content,
                recipients: recipientPubkeys,
                reply: replyParent
            )
            let receipt = try await engine.publishComposed(intent)
            for await status in receipt.status {
                if let failure = deliveryFailure(for: status) { return failure }
                if case .acked = status { return nil }
            }
            return "Message delivery ended without relay acknowledgement."
        } catch {
            return error.localizedDescription
        }
    }

    private func deliveryFailure(for status: WriteStatus) -> String? {
        switch status {
        case .rejected(_, let reason):
            return "The relay rejected the message: \(reason)"
        case .failed(let reason):
            return reason
        case .gaveUp(let relay):
            return "Could not deliver the message to \(relay)."
        case .persistenceBlocked(let relay):
            return "Could not persist the message for \(relay)."
        case .routePersistenceBlocked(let relay):
            return "Could not persist message routing for \(relay)."
        case .outcomeUnknown(let relay):
            return "Message delivery outcome for \(relay) is unknown."
        default:
            return nil
        }
    }
}
