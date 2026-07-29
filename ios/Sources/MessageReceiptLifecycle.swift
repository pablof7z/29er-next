import Foundation
import NMP

enum MessageDeliveryProgress: Equatable, Sendable {
    case enqueueing
    case accepted
    case awaitingCapability(pubkey: String)
    case signed(eventID: String)
    case routed(relays: [String])
    case awaitingRelay(relay: String)
    case awaitingAuth(relay: String)
    case persistenceBlocked(relay: String)
    case routePersistenceBlocked(relay: String)
    case retryEligible(relay: String, attempt: UInt64, eligibleAt: UInt64)
    case handoffAmbiguous(relay: String, attempt: UInt64, observedAt: UInt64)
    case sent(relay: String, attempt: UInt64, writtenAt: UInt64)

    var message: String {
        switch self {
        case .enqueueing:
            return "Saving with NMP…"
        case .accepted:
            return "Saved by NMP; delivering…"
        case .awaitingCapability:
            return "Waiting for the active signer…"
        case .signed:
            return "Signed; routing…"
        case .routed:
            return "Route selected; connecting…"
        case .awaitingRelay(let relay):
            return "Waiting for \(relay)…"
        case .awaitingAuth(let relay):
            return "Authenticating with \(relay)…"
        case .persistenceBlocked(let relay):
            return "Waiting to persist the next attempt for \(relay)…"
        case .routePersistenceBlocked(let relay):
            return "Waiting to persist message routing for \(relay)…"
        case .retryEligible(let relay, _, _):
            return "Retrying \(relay)…"
        case .handoffAmbiguous(let relay, _, _):
            return "Confirming delivery with \(relay)…"
        case .sent(let relay, _, _):
            return "Sent to \(relay); awaiting acknowledgement…"
        }
    }
}

enum MessageDeliveryFailure: Equatable, Sendable {
    case cancelled
    case rejected(relay: String, reason: String)
    case gaveUp(relay: String)
    case outcomeUnknown(relay: String)
    case replaceableConflict(expected: String?, actual: String?)
    case failed(reason: String)
    case streamEndedWithoutTerminal
    case receiptNotFound(receiptID: UInt64)
    case retainedButUnreadable(receiptID: UInt64)
    case receiptReplayUnavailable(receiptID: UInt64)
    case observationFailed(reason: String)

    var message: String {
        switch self {
        case .cancelled:
            return "Message delivery was cancelled."
        case .rejected(let relay, let reason):
            return "\(relay) rejected the message: \(reason)"
        case .gaveUp(let relay):
            return "NMP could not deliver the message to \(relay)."
        case .outcomeUnknown(let relay):
            return "Message delivery outcome for \(relay) is unknown."
        case .replaceableConflict(let expected, let actual):
            return "The event changed before publication (expected \(expected ?? "none"), "
                + "found \(actual ?? "none"))."
        case .failed(let reason):
            return "NMP could not deliver the message: \(reason)"
        case .streamEndedWithoutTerminal:
            return "Message delivery ended without a terminal NMP outcome."
        case .receiptNotFound(let receiptID):
            return "NMP no longer retains message receipt \(receiptID)."
        case .retainedButUnreadable(let receiptID):
            return "NMP retains message receipt \(receiptID), but its history is unreadable."
        case .receiptReplayUnavailable(let receiptID):
            return "NMP receipt \(receiptID) changed while its history was replaying."
        case .observationFailed(let reason):
            return "NMP receipt observation failed: \(reason)"
        }
    }
}

enum MessageDeliveryState: Equatable, Sendable {
    case idle
    case progressing(receiptID: UInt64?, progress: MessageDeliveryProgress)
    case acknowledged(receiptID: UInt64, relay: String)
    case failed(receiptID: UInt64?, failure: MessageDeliveryFailure)
    case converged(
        receiptID: UInt64,
        acknowledgedRelays: [String],
        failures: [MessageDeliveryFailure]
    )

    var progressMessage: String? {
        guard case .progressing(_, let progress) = self else { return nil }
        return progress.message
    }

    var failureMessage: String? {
        switch self {
        case .failed(_, let failure):
            return failure.message
        case .converged(_, _, let failures) where !failures.isEmpty:
            return failures.map(\.message).joined(separator: "\n")
        case .idle, .progressing, .acknowledged, .converged:
            return nil
        }
    }

    var receiptID: UInt64? {
        switch self {
        case .idle, .progressing(receiptID: nil, _), .failed(receiptID: nil, _):
            return nil
        case .progressing(let receiptID?, _), .failed(let receiptID?, _):
            return receiptID
        case .acknowledged(let receiptID, _), .converged(let receiptID, _, _):
            return receiptID
        }
    }

    static func applying(_ status: WriteStatus, receiptID: UInt64) -> MessageDeliveryState {
        switch status {
        case .accepted:
            return .progressing(receiptID: receiptID, progress: .accepted)
        case .awaitingCapability(let pubkey):
            return .progressing(
                receiptID: receiptID,
                progress: .awaitingCapability(pubkey: pubkey)
            )
        case .signed(let eventID):
            return .progressing(receiptID: receiptID, progress: .signed(eventID: eventID))
        case .routed(let relays):
            return .progressing(receiptID: receiptID, progress: .routed(relays: relays))
        case .awaitingRelay(let relay):
            return .progressing(receiptID: receiptID, progress: .awaitingRelay(relay: relay))
        case .awaitingAuth(let relay):
            return .progressing(receiptID: receiptID, progress: .awaitingAuth(relay: relay))
        case .persistenceBlocked(let relay):
            return .progressing(
                receiptID: receiptID,
                progress: .persistenceBlocked(relay: relay)
            )
        case .routePersistenceBlocked(let relay):
            return .progressing(
                receiptID: receiptID,
                progress: .routePersistenceBlocked(relay: relay)
            )
        case .retryEligible(let relay, let attempt, let eligibleAt):
            return .progressing(
                receiptID: receiptID,
                progress: .retryEligible(relay: relay, attempt: attempt, eligibleAt: eligibleAt)
            )
        case .handoffAmbiguous(let relay, let attempt, let observedAt):
            return .progressing(
                receiptID: receiptID,
                progress: .handoffAmbiguous(
                    relay: relay,
                    attempt: attempt,
                    observedAt: observedAt
                )
            )
        case .sent(let relay, let attempt, let writtenAt):
            return .progressing(
                receiptID: receiptID,
                progress: .sent(relay: relay, attempt: attempt, writtenAt: writtenAt)
            )
        case .acked(let relay):
            return .acknowledged(receiptID: receiptID, relay: relay)
        case .cancelled:
            return .failed(receiptID: receiptID, failure: .cancelled)
        case .rejected(let relay, let reason):
            return .failed(
                receiptID: receiptID,
                failure: .rejected(relay: relay, reason: reason)
            )
        case .gaveUp(let relay):
            return .failed(receiptID: receiptID, failure: .gaveUp(relay: relay))
        case .outcomeUnknown(let relay):
            return .failed(receiptID: receiptID, failure: .outcomeUnknown(relay: relay))
        case .replaceableConflict(let expected, let actual):
            return .failed(
                receiptID: receiptID,
                failure: .replaceableConflict(expected: expected, actual: actual)
            )
        case .failed(let reason):
            return .failed(receiptID: receiptID, failure: .failed(reason: reason))
        }
    }

    var isTerminalFact: Bool {
        switch self {
        case .acknowledged, .failed, .converged:
            return true
        case .idle, .progressing:
            return false
        }
    }
}

struct MessageReceiptConvergence: Equatable, Sendable {
    private(set) var failures: [MessageDeliveryFailure] = []
    private(set) var acknowledgedRelays: [String] = []

    mutating func apply(
        _ status: WriteStatus,
        receiptID: UInt64
    ) -> MessageDeliveryState {
        let state = MessageDeliveryState.applying(status, receiptID: receiptID)
        switch state {
        case .acknowledged(_, let relay):
            if !acknowledgedRelays.contains(relay) {
                acknowledgedRelays.append(relay)
            }
        case .failed(_, let failure):
            if !failures.contains(failure) {
                failures.append(failure)
            }
        case .idle, .progressing, .converged:
            break
        }
        return state
    }

    func stateAfterStreamClosed(receiptID: UInt64) -> MessageDeliveryState? {
        guard !acknowledgedRelays.isEmpty || !failures.isEmpty else { return nil }
        return .converged(
            receiptID: receiptID,
            acknowledgedRelays: acknowledgedRelays,
            failures: failures
        )
    }
}
