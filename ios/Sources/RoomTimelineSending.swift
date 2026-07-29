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

        messageReceiptPresentation.clearCompletedRetainedState()
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
        let storedReceiptIDs: [UInt64]
        do {
            storedReceiptIDs = try messageReceiptStore.loadReceiptIDs()
        } catch {
            messageDeliveryState = .failed(
                receiptID: nil,
                failure: .observationFailed(reason: error.localizedDescription)
            )
            return
        }
        var receiptIDs = storedReceiptIDs.sorted(by: >).makeIterator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<MessageReceiptPresentation.maximumActiveReceiptCount {
                guard let receiptID = receiptIDs.next() else { break }
                group.addTask { [weak self] in
                    await self?.observeRetainedMessageReceipt(receiptID)
                }
            }
            while await group.next() != nil {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                guard let receiptID = receiptIDs.next() else { continue }
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
                try messageReceiptStore.removeReceiptID(receiptID)
                completeRetainedObservation(
                    .failed(
                        receiptID: receiptID,
                        failure: .receiptNotFound(receiptID: receiptID)
                    )
                )
            case .retainedButUnreadable:
                completeRetainedObservation(
                    .failed(
                        receiptID: receiptID,
                        failure: .retainedButUnreadable(receiptID: receiptID)
                    )
                )
            }
        } catch {
            guard !Task.isCancelled else { return }
            completeRetainedObservation(
                .failed(
                    receiptID: receiptID,
                    failure: .observationFailed(reason: error.localizedDescription)
                )
            )
        }
    }

    private func consumeMessageReceipt(
        _ receipt: Receipt,
        retained: Bool
    ) async -> String? {
        var observedReceiptIDs = Set<UInt64>()
        let outcome = await observeReceiptThroughClosure(
            initial: receipt,
            driver: NMPReceiptObservationDriver(engine: engine),
            onReceiptID: { receiptID in
                observedReceiptIDs.insert(receiptID)
                try messageReceiptStore.recordReceiptID(receiptID)
            },
            onState: { state in
                guard let receiptID = state.receiptID else { return }
                recordMessageDeliveryState(state, receiptID: receiptID, retained: retained)
            }
        )

        if retained {
            for receiptID in observedReceiptIDs {
                messageReceiptPresentation.endRetainedObservation(receiptID: receiptID)
            }
            if let outcome, let receiptID = outcome.state.receiptID {
                messageReceiptPresentation.completeRetained(
                    outcome.state,
                    receiptID: receiptID
                )
            }
        }
        guard let outcome else { return nil }
        if outcome.shouldForgetReceipt {
            for receiptID in observedReceiptIDs {
                do {
                    try messageReceiptStore.removeReceiptID(receiptID)
                } catch {
                    let state = MessageDeliveryState.failed(
                        receiptID: receiptID,
                        failure: .observationFailed(reason: error.localizedDescription)
                    )
                    recordMessageDeliveryState(state, receiptID: receiptID, retained: retained)
                }
            }
        }
        return outcome.state.failureMessage
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

    private func completeRetainedObservation(_ state: MessageDeliveryState) {
        guard let receiptID = state.receiptID else { return }
        messageReceiptPresentation.recordRetained(state, receiptID: receiptID)
        messageReceiptPresentation.completeRetained(state, receiptID: receiptID)
    }
}
