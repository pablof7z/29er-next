import Foundation
import NMP

extension RoomTimelineModel {
    private static let maximumOutstandingReactionCount = 4

    func startReaction(to message: RoomMessage, emoji: String) {
        guard reactionTasks.count < Self.maximumOutstandingReactionCount else {
            _ = recordReactionSubmissionFailure(
                "Wait for an earlier reaction to finish before sending another."
            )
            return
        }
        let taskID = UUID()
        reactionTasks[taskID] = Task { [weak self] in
            guard let self else { return }
            _ = await self.reactToMessage(message, emoji: emoji)
            self.reactionTasks.removeValue(forKey: taskID)
        }
    }

    func cancelReactionObservations() {
        for task in reactionTasks.values {
            task.cancel()
        }
        reactionTasks.removeAll()
    }

    /// Publish a NIP-25 kind:7 reaction to `message`. NMP has no dedicated
    /// reaction-intent helper yet, so this composes the raw `WriteIntent`
    /// directly. #144 deletes this entire composer when the group gate lands.
    func reactToMessage(_ message: RoomMessage, emoji: String) async -> String? {
        guard let viewer = recipient else {
            return recordReactionSubmissionFailure("Sign in to react.")
        }

        do {
            let correlation = "reaction-\(UUID().uuidString.lowercased())"
            let intent = WriteIntent(
                payload: .unsigned(
                    pubkey: viewer,
                    createdAt: UInt64(Date().timeIntervalSince1970),
                    kind: 7,
                    tags: [["e", message.id], ["p", message.author], ["h", groupID]],
                    content: emoji
                ),
                durability: .durable,
                routing: .authorOutbox,
                correlation: correlation
            )
            let submission = try await submitCrashRecoverableWrite(
                correlation: correlation,
                maximumRecoveryCount: Self.maximumOutstandingReactionCount,
                store: reactionReceiptStore,
                publish: { try await engine.publish(intent) },
                receiptID: \.id
            )
            if let failure = submission.recoveryPersistenceFailure {
                _ = recordReactionSubmissionFailure(
                    "Reaction recovery could not be saved: \(failure)"
                )
            }
            let deliveryFailure = await consumeReactionReceipt(submission.value)
            return deliveryFailure ?? submission.recoveryPersistenceFailure
        } catch {
            guard !Task.isCancelled else { return nil }
            return recordReactionSubmissionFailure(error.localizedDescription)
        }
    }

    func observeRetainedReactionReceipts() async {
        let correlations: [String]
        let receiptIDs: [UInt64]
        do {
            correlations = try reactionReceiptStore.loadCorrelations()
            receiptIDs = try reactionReceiptStore.loadReceiptIDs()
            guard correlations.count + receiptIDs.count
                    <= Self.maximumOutstandingReactionCount else {
                _ = recordReactionSubmissionFailure(
                    "The reaction recovery journal exceeds NMP's observation limit."
                )
                return
            }
        } catch {
            _ = recordReactionSubmissionFailure(error.localizedDescription)
            return
        }
        var attachedIDs = Set<UInt64>()
        await withTaskGroup(of: Void.self) { group in
            for correlation in correlations {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                do {
                    switch try engine.reattachReceipt(correlation: correlation) {
                    case .attached(let receipt):
                        try reactionReceiptStore.replaceCorrelation(
                            correlation,
                            with: receipt.id
                        )
                        attachedIDs.insert(receipt.id)
                        group.addTask { [weak self] in
                            _ = await self?.consumeReactionReceipt(receipt)
                        }
                    case .notFound:
                        try reactionReceiptStore.removeCorrelation(correlation)
                    case .retainedButUnreadable:
                        _ = recordReactionSubmissionFailure(
                            "NMP retains a reaction receipt, but its history is unreadable."
                        )
                    }
                } catch {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    _ = recordReactionSubmissionFailure(error.localizedDescription)
                }
            }

            for receiptID in receiptIDs where !attachedIDs.contains(receiptID) {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                do {
                    switch try engine.reattachReceipt(id: receiptID) {
                    case .attached(let receipt):
                        group.addTask { [weak self] in
                            _ = await self?.consumeReactionReceipt(receipt)
                        }
                    case .notFound:
                        try reactionReceiptStore.removeReceiptID(receiptID)
                    case .retainedButUnreadable:
                        reactionReceiptPresentation.record(
                            .failed(
                                receiptID: receiptID,
                                failure: .retainedButUnreadable(receiptID: receiptID)
                            )
                        )
                    }
                } catch {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    reactionReceiptPresentation.record(
                        .failed(
                            receiptID: receiptID,
                            failure: .observationFailed(reason: error.localizedDescription)
                        )
                    )
                }
            }
        }
    }

    private func consumeReactionReceipt(_ receipt: Receipt) async -> String? {
        var observedReceiptIDs = Set<UInt64>()
        let outcome = await observeReceiptThroughClosure(
            initial: receipt,
            driver: NMPReceiptObservationDriver(engine: engine),
            onReceiptID: { receiptID in
                observedReceiptIDs.insert(receiptID)
                try reactionReceiptStore.recordReceiptID(receiptID)
            },
            onState: { reactionReceiptPresentation.record($0) }
        )
        guard let outcome else { return nil }
        reactionReceiptPresentation.record(outcome.state)
        if outcome.shouldForgetReceipt {
            for receiptID in observedReceiptIDs {
                do {
                    try reactionReceiptStore.removeReceiptID(receiptID)
                } catch {
                    _ = recordReactionSubmissionFailure(error.localizedDescription)
                }
            }
        }
        return outcome.state.failureMessage
    }

    private func recordReactionSubmissionFailure(_ message: String) -> String {
        reactionReceiptPresentation.recordSubmissionFailure(message)
        return message
    }
}
