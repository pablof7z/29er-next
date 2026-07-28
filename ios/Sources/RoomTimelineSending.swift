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
            return await consumeMessageReceipt(receipt, retained: false)
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
                _ = await consumeMessageReceipt(receipt, retained: true)
            case .notFound:
                messageReceiptStore.remove(receiptID)
                recordMessageDeliveryState(
                    .failed(
                        receiptID: receiptID,
                        failure: .receiptNotFound(receiptID: receiptID)
                    ),
                    receiptID: receiptID,
                    retained: true
                )
            case .retainedButUnreadable:
                recordMessageDeliveryState(
                    .failed(
                        receiptID: receiptID,
                        failure: .retainedButUnreadable(receiptID: receiptID)
                    ),
                    receiptID: receiptID,
                    retained: true
                )
            }
        } catch {
            guard !Task.isCancelled else { return }
            recordMessageDeliveryState(
                .failed(
                    receiptID: receiptID,
                    failure: .observationFailed(reason: error.localizedDescription)
                ),
                receiptID: receiptID,
                retained: true
            )
        }
    }

    private func consumeMessageReceipt(
        _ receipt: Receipt,
        retained: Bool
    ) async -> String? {
        let receiptID = receipt.id
        messageReceiptStore.record(receiptID)
        defer { receipt.status.cancel() }

        do {
            var convergence = MessageReceiptConvergence()
            for try await status in receipt.status {
                guard !Task.isCancelled else { return nil }
                let state = convergence.apply(status, receiptID: receiptID)
                recordMessageDeliveryState(state, receiptID: receiptID, retained: retained)
            }
            guard !Task.isCancelled else { return nil }
            guard let finalState = convergence.stateAfterStreamClosed(receiptID: receiptID) else {
                let state = MessageDeliveryState.failed(
                    receiptID: receiptID,
                    failure: .streamEndedWithoutTerminal
                )
                recordMessageDeliveryState(state, receiptID: receiptID, retained: retained)
                return state.failureMessage
            }
            recordMessageDeliveryState(
                finalState,
                receiptID: receiptID,
                retained: retained
            )
            messageReceiptStore.remove(receiptID)
            return finalState.failureMessage
        } catch let error as NMPError {
            guard !Task.isCancelled else { return nil }
            switch error {
            case .factStreamLagged(let replayID):
                return await resumeMessageReceipt(
                    id: replayID ?? receiptID,
                    retained: retained
                )
            case .receiptReplayUnavailable(let unavailableID):
                let state = MessageDeliveryState.failed(
                    receiptID: unavailableID,
                    failure: .receiptReplayUnavailable(receiptID: unavailableID)
                )
                recordMessageDeliveryState(
                    state,
                    receiptID: unavailableID,
                    retained: retained
                )
                return state.failureMessage
            default:
                let state = MessageDeliveryState.failed(
                    receiptID: receiptID,
                    failure: .observationFailed(reason: error.localizedDescription)
                )
                recordMessageDeliveryState(state, receiptID: receiptID, retained: retained)
                return state.failureMessage
            }
        } catch {
            guard !Task.isCancelled else { return nil }
            let state = MessageDeliveryState.failed(
                receiptID: receiptID,
                failure: .observationFailed(reason: error.localizedDescription)
            )
            recordMessageDeliveryState(state, receiptID: receiptID, retained: retained)
            return state.failureMessage
        }
    }

    private func resumeMessageReceipt(
        id receiptID: UInt64,
        retained: Bool
    ) async -> String? {
        do {
            switch try engine.reattachReceipt(id: receiptID) {
            case .attached(let receipt):
                return await consumeMessageReceipt(receipt, retained: retained)
            case .notFound:
                messageReceiptStore.remove(receiptID)
                let state = MessageDeliveryState.failed(
                    receiptID: receiptID,
                    failure: .receiptNotFound(receiptID: receiptID)
                )
                recordMessageDeliveryState(state, receiptID: receiptID, retained: retained)
                return state.failureMessage
            case .retainedButUnreadable:
                let state = MessageDeliveryState.failed(
                    receiptID: receiptID,
                    failure: .retainedButUnreadable(receiptID: receiptID)
                )
                recordMessageDeliveryState(state, receiptID: receiptID, retained: retained)
                return state.failureMessage
            }
        } catch let error as NMPError {
            guard !Task.isCancelled else { return nil }
            switch error {
            case .receiptReplayUnavailable(let unavailableID):
                let state = MessageDeliveryState.failed(
                    receiptID: unavailableID,
                    failure: .receiptReplayUnavailable(receiptID: unavailableID)
                )
                recordMessageDeliveryState(
                    state,
                    receiptID: unavailableID,
                    retained: retained
                )
                return state.failureMessage
            default:
                let state = MessageDeliveryState.failed(
                    receiptID: receiptID,
                    failure: .observationFailed(reason: error.localizedDescription)
                )
                recordMessageDeliveryState(state, receiptID: receiptID, retained: retained)
                return state.failureMessage
            }
        } catch {
            guard !Task.isCancelled else { return nil }
            let state = MessageDeliveryState.failed(
                receiptID: receiptID,
                failure: .observationFailed(reason: error.localizedDescription)
            )
            recordMessageDeliveryState(state, receiptID: receiptID, retained: retained)
            return state.failureMessage
        }
    }

    private func recordMessageDeliveryState(
        _ state: MessageDeliveryState,
        receiptID: UInt64,
        retained: Bool
    ) {
        if retained {
            messageReceiptPresentation.recordRetained(state, receiptID: receiptID)
        } else {
            messageDeliveryState = state
        }
    }
}
