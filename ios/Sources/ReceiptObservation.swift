import Foundation
import NMP

enum ReceiptObservationReattachment<Segment> {
    case attached(Segment)
    case notFound
    case retainedButUnreadable
}

@MainActor
protocol ReceiptObservationDriving {
    associatedtype Segment

    func receiptID(for segment: Segment) -> UInt64
    func consume(
        _ segment: Segment,
        onState: (MessageDeliveryState) -> Void
    ) async throws -> MessageReceiptConvergence?
    func reattach(receiptID: UInt64) throws -> ReceiptObservationReattachment<Segment>
}

struct ReceiptObservationOutcome: Equatable, Sendable {
    let state: MessageDeliveryState
    let shouldForgetReceipt: Bool
}

struct CrashRecoverableSubmission<Value> {
    let value: Value
    let recoveryPersistenceFailure: String?
}

struct ReceiptPreAcceptanceCleanupError: LocalizedError {
    let publicationFailure: String
    let cleanupFailure: String

    var errorDescription: String? {
        "NMP refused the write before acceptance (\(publicationFailure)), "
            + "and its recovery correlation could not be removed (\(cleanupFailure))."
    }
}

@MainActor
func submitCrashRecoverableWrite<Value, Store: ReceiptRecoveryStoring>(
    correlation: String,
    maximumRecoveryCount: Int,
    store: Store,
    publish: () async throws -> Value,
    receiptID: (Value) -> UInt64
) async throws -> CrashRecoverableSubmission<Value> {
    try Task.checkCancellation()
    try store.reserveCorrelation(correlation, maximumCount: maximumRecoveryCount)
    let value: Value
    do {
        value = try await publish()
    } catch {
        let publicationFailure = error.localizedDescription
        do {
            try store.removeCorrelation(correlation)
        } catch {
            throw ReceiptPreAcceptanceCleanupError(
                publicationFailure: publicationFailure,
                cleanupFailure: error.localizedDescription
            )
        }
        throw error
    }
    do {
        try store.replaceCorrelation(correlation, with: receiptID(value))
        return CrashRecoverableSubmission(
            value: value,
            recoveryPersistenceFailure: nil
        )
    } catch {
        return CrashRecoverableSubmission(
            value: value,
            recoveryPersistenceFailure: error.localizedDescription
        )
    }
}

@MainActor
struct NMPReceiptObservationDriver: ReceiptObservationDriving {
    let engine: NMPEngine

    func receiptID(for segment: Receipt) -> UInt64 {
        segment.id
    }

    func consume(
        _ segment: Receipt,
        onState: (MessageDeliveryState) -> Void
    ) async throws -> MessageReceiptConvergence? {
        defer { segment.status.cancel() }
        var convergence = MessageReceiptConvergence()
        for try await status in segment.status {
            guard !Task.isCancelled else { return nil }
            onState(convergence.apply(status, receiptID: segment.id))
        }
        return Task.isCancelled ? nil : convergence
    }

    func reattach(receiptID: UInt64) throws -> ReceiptObservationReattachment<Receipt> {
        switch try engine.reattachReceipt(id: receiptID) {
        case .attached(let receipt):
            return .attached(receipt)
        case .notFound:
            return .notFound
        case .retainedButUnreadable:
            return .retainedButUnreadable
        }
    }
}

@MainActor
func observeReceiptThroughClosure<Driver: ReceiptObservationDriving>(
    initial: Driver.Segment,
    driver: Driver,
    onReceiptID: (UInt64) throws -> Void,
    onState: (MessageDeliveryState) -> Void
) async -> ReceiptObservationOutcome? {
    var segment = initial

    while !Task.isCancelled {
        let receiptID = driver.receiptID(for: segment)
        do {
            try onReceiptID(receiptID)
            guard let convergence = try await driver.consume(segment, onState: onState) else {
                return nil
            }
            guard !Task.isCancelled else { return nil }
            let completedState = convergence.stateAfterStreamClosed(receiptID: receiptID)
            let state = completedState
                ?? .failed(receiptID: receiptID, failure: .streamEndedWithoutTerminal)
            onState(state)
            return ReceiptObservationOutcome(
                state: state,
                shouldForgetReceipt: completedState != nil
            )
        } catch let error as NMPError {
            guard !Task.isCancelled else { return nil }
            switch error {
            case .factStreamLagged(let replayID):
                let targetID = replayID ?? receiptID
                do {
                    switch try driver.reattach(receiptID: targetID) {
                    case .attached(let replay):
                        segment = replay
                        continue
                    case .notFound:
                        let state = MessageDeliveryState.failed(
                            receiptID: targetID,
                            failure: .receiptNotFound(receiptID: targetID)
                        )
                        onState(state)
                        return ReceiptObservationOutcome(
                            state: state,
                            shouldForgetReceipt: true
                        )
                    case .retainedButUnreadable:
                        let state = MessageDeliveryState.failed(
                            receiptID: targetID,
                            failure: .retainedButUnreadable(receiptID: targetID)
                        )
                        onState(state)
                        return ReceiptObservationOutcome(
                            state: state,
                            shouldForgetReceipt: false
                        )
                    }
                } catch {
                    let state = receiptObservationFailure(error, receiptID: targetID)
                    onState(state)
                    return ReceiptObservationOutcome(
                        state: state,
                        shouldForgetReceipt: false
                    )
                }
            case .receiptReplayUnavailable(let unavailableID):
                let state = MessageDeliveryState.failed(
                    receiptID: unavailableID,
                    failure: .receiptReplayUnavailable(receiptID: unavailableID)
                )
                onState(state)
                return ReceiptObservationOutcome(
                    state: state,
                    shouldForgetReceipt: false
                )
            default:
                let state = receiptObservationFailure(error, receiptID: receiptID)
                onState(state)
                return ReceiptObservationOutcome(
                    state: state,
                    shouldForgetReceipt: false
                )
            }
        } catch {
            guard !Task.isCancelled else { return nil }
            let state = receiptObservationFailure(error, receiptID: receiptID)
            onState(state)
            return ReceiptObservationOutcome(
                state: state,
                shouldForgetReceipt: false
            )
        }
    }
    return nil
}

private func receiptObservationFailure(
    _ error: Error,
    receiptID: UInt64
) -> MessageDeliveryState {
    if case NMPError.receiptReplayUnavailable(let unavailableID) = error {
        return .failed(
            receiptID: unavailableID,
            failure: .receiptReplayUnavailable(receiptID: unavailableID)
        )
    }
    return .failed(
        receiptID: receiptID,
        failure: .observationFailed(reason: error.localizedDescription)
    )
}
