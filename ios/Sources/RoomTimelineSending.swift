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

        messageDeliveryState = .progressing(receiptID: nil, progress: .enqueueing)
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
            return await consumeMessageReceipt(receipt)
        } catch {
            messageDeliveryState = .failed(
                receiptID: nil,
                failure: .observationFailed(reason: error.localizedDescription)
            )
            return error.localizedDescription
        }
    }

    func observeRetainedMessageReceipts() async {
        await withTaskGroup(of: Void.self) { group in
            for receiptID in messageReceiptStore.load() {
                group.addTask { [weak self] in
                    await self?.observeRetainedMessageReceipt(receiptID)
                }
            }
        }
    }

    private func observeRetainedMessageReceipt(_ receiptID: UInt64) async {
        guard !Task.isCancelled else { return }
        do {
            switch try engine.reattachReceipt(id: receiptID) {
            case .attached(let receipt):
                _ = await consumeMessageReceipt(receipt)
            case .notFound:
                messageReceiptStore.remove(receiptID)
                messageDeliveryState = .failed(
                    receiptID: receiptID,
                    failure: .receiptNotFound(receiptID: receiptID)
                )
            case .retainedButUnreadable:
                messageDeliveryState = .failed(
                    receiptID: receiptID,
                    failure: .retainedButUnreadable(receiptID: receiptID)
                )
            }
        } catch {
            guard !Task.isCancelled else { return }
            messageDeliveryState = .failed(
                receiptID: receiptID,
                failure: .observationFailed(reason: error.localizedDescription)
            )
        }
    }

    private func consumeMessageReceipt(_ receipt: Receipt) async -> String? {
        let receiptID = receipt.id
        messageReceiptStore.record(receiptID)
        defer { receipt.status.cancel() }

        do {
            var convergence = MessageReceiptConvergence()
            for try await status in receipt.status {
                guard !Task.isCancelled else { return nil }
                messageDeliveryState = convergence.apply(status, receiptID: receiptID)
            }
            guard !Task.isCancelled else { return nil }
            guard let finalState = convergence.stateAfterStreamClosed(receiptID: receiptID) else {
                messageDeliveryState = .failed(
                    receiptID: receiptID,
                    failure: .streamEndedWithoutTerminal
                )
                return messageDeliveryState.failureMessage
            }
            messageDeliveryState = finalState
            messageReceiptStore.remove(receiptID)
            return messageDeliveryState.failureMessage
        } catch let error as NMPError {
            guard !Task.isCancelled else { return nil }
            switch error {
            case .factStreamLagged(let replayID):
                return await resumeMessageReceipt(id: replayID ?? receiptID)
            case .receiptReplayUnavailable(let unavailableID):
                messageDeliveryState = .failed(
                    receiptID: unavailableID,
                    failure: .receiptReplayUnavailable(receiptID: unavailableID)
                )
            default:
                messageDeliveryState = .failed(
                    receiptID: receiptID,
                    failure: .observationFailed(reason: error.localizedDescription)
                )
            }
            return messageDeliveryState.failureMessage
        } catch {
            guard !Task.isCancelled else { return nil }
            messageDeliveryState = .failed(
                receiptID: receiptID,
                failure: .observationFailed(reason: error.localizedDescription)
            )
            return messageDeliveryState.failureMessage
        }
    }

    private func resumeMessageReceipt(id receiptID: UInt64) async -> String? {
        do {
            switch try engine.reattachReceipt(id: receiptID) {
            case .attached(let receipt):
                return await consumeMessageReceipt(receipt)
            case .notFound:
                messageReceiptStore.remove(receiptID)
                messageDeliveryState = .failed(
                    receiptID: receiptID,
                    failure: .receiptNotFound(receiptID: receiptID)
                )
            case .retainedButUnreadable:
                messageDeliveryState = .failed(
                    receiptID: receiptID,
                    failure: .retainedButUnreadable(receiptID: receiptID)
                )
            }
        } catch let error as NMPError {
            guard !Task.isCancelled else { return nil }
            switch error {
            case .receiptReplayUnavailable(let unavailableID):
                messageDeliveryState = .failed(
                    receiptID: unavailableID,
                    failure: .receiptReplayUnavailable(receiptID: unavailableID)
                )
            default:
                messageDeliveryState = .failed(
                    receiptID: receiptID,
                    failure: .observationFailed(reason: error.localizedDescription)
                )
            }
        } catch {
            guard !Task.isCancelled else { return nil }
            messageDeliveryState = .failed(
                receiptID: receiptID,
                failure: .observationFailed(reason: error.localizedDescription)
            )
        }
        return messageDeliveryState.failureMessage
    }

    func deliveryFailure(for status: WriteStatus) -> String? {
        switch status {
        case .rejected(_, let reason):
            return "The relay rejected the message: \(reason)"
        case .failed(let reason):
            return reason
        case .gaveUp(let relay):
            return "Could not deliver the message to \(relay)."
        case .cancelled:
            return "Message delivery was cancelled."
        case .outcomeUnknown(let relay):
            return "Message delivery outcome for \(relay) is unknown."
        case .replaceableConflict(let expected, let actual):
            return "The event changed before publication (expected \(expected ?? "none"), "
                + "found \(actual ?? "none"))."
        default:
            return nil
        }
    }
}
