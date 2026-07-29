import Foundation

private struct ReactionFailureNotice: Equatable, Sendable {
    let key: String
    let message: String
}

struct ReactionReceiptPresentation: Equatable, Sendable {
    private static let maximumReceiptCount = 32

    private(set) var states: [UInt64: MessageDeliveryState] = [:]
    private var failureNotices: [ReactionFailureNotice] = []

    var currentFailureMessage: String? {
        failureNotices.first?.message
    }

    mutating func record(_ state: MessageDeliveryState) {
        if let receiptID = state.receiptID {
            states[receiptID] = state
            trimStates()
            if let failure = state.failureMessage {
                enqueueFailure(
                    ReactionFailureNotice(
                        key: "receipt:\(receiptID)",
                        message: failure
                    )
                )
            }
        } else if let failure = state.failureMessage {
            recordSubmissionFailure(failure)
        }
    }

    mutating func recordSubmissionFailure(_ message: String) {
        enqueueFailure(
            ReactionFailureNotice(
                key: "submission:\(UUID().uuidString)",
                message: message
            )
        )
    }

    mutating func dismissCurrentFailure() {
        guard !failureNotices.isEmpty else { return }
        failureNotices.removeFirst()
    }

    private mutating func enqueueFailure(_ notice: ReactionFailureNotice) {
        guard !failureNotices.contains(where: { $0.key == notice.key }) else { return }
        failureNotices.append(notice)
        if failureNotices.count > Self.maximumReceiptCount {
            failureNotices.removeFirst(failureNotices.count - Self.maximumReceiptCount)
        }
    }

    private mutating func trimStates() {
        while states.count > Self.maximumReceiptCount,
              let oldest = states.keys.min() {
            states.removeValue(forKey: oldest)
        }
    }
}
