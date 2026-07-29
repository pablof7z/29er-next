import NMP
import XCTest
@testable import TwentyNinerNext

final class MessageReceiptPresentationTests: XCTestCase {
    func testReactionStyleReceiptReportsFailuresAfterAnEarlierAcknowledgement() throws {
        var convergence = MessageReceiptConvergence()
        _ = convergence.apply(.acked(relay: "wss://one"), receiptID: 71)
        _ = convergence.apply(
            .rejected(relay: "wss://two", reason: "blocked"),
            receiptID: 71
        )

        let state = try XCTUnwrap(convergence.stateAfterStreamClosed(receiptID: 71))

        XCTAssertEqual(
            state.failureMessage,
            "wss://two rejected the message: blocked"
        )
    }

    func testRetainedReceiptPresentationIsPerReceiptAndDeterministic() {
        var presentation = MessageReceiptPresentation()
        presentation.recordRetained(
            .progressing(receiptID: 91, progress: .accepted),
            receiptID: 91
        )
        presentation.recordRetained(
            .progressing(receiptID: 92, progress: .awaitingRelay(relay: "wss://two")),
            receiptID: 92
        )

        XCTAssertEqual(
            presentation.progressMessage(currentState: .idle),
            "Waiting for wss://two…"
        )

        presentation.recordRetained(
            .failed(
                receiptID: 91,
                failure: .rejected(relay: "wss://one", reason: "blocked")
            ),
            receiptID: 91
        )
        presentation.recordRetained(
            .failed(receiptID: 92, failure: .gaveUp(relay: "wss://two")),
            receiptID: 92
        )

        XCTAssertEqual(
            presentation.failureMessage(currentState: .idle),
            """
            wss://one rejected the message: blocked
            NMP could not deliver the message to wss://two.
            """
        )
    }

    func testCurrentReceiptProgressWinsWithoutDroppingRetainedFailure() {
        var presentation = MessageReceiptPresentation()
        presentation.recordRetained(
            .failed(receiptID: 101, failure: .outcomeUnknown(relay: "wss://old")),
            receiptID: 101
        )
        let current = MessageDeliveryState.progressing(
            receiptID: nil,
            progress: .enqueueing
        )

        XCTAssertEqual(
            presentation.progressMessage(currentState: current),
            "Saving with NMP…"
        )
        XCTAssertEqual(
            presentation.failureMessage(currentState: current),
            "Message delivery outcome for wss://old is unknown."
        )
    }

    func testTerminalCurrentStateDoesNotHideActiveRetainedProgress() {
        var presentation = MessageReceiptPresentation()
        presentation.recordRetained(
            .progressing(receiptID: 111, progress: .awaitingRelay(relay: "wss://active")),
            receiptID: 111
        )

        XCTAssertEqual(
            presentation.progressMessage(
                currentState: .acknowledged(receiptID: 110, relay: "wss://done")
            ),
            "Waiting for wss://active…"
        )
    }

    func testCompletedRetainedStatesAreBoundedAndClearOnANewSend() {
        var presentation = MessageReceiptPresentation()
        let older = MessageDeliveryState.failed(
            receiptID: 120,
            failure: .gaveUp(relay: "wss://old")
        )
        let newer = MessageDeliveryState.failed(
            receiptID: 121,
            failure: .outcomeUnknown(relay: "wss://new")
        )

        presentation.recordRetained(older, receiptID: 120)
        presentation.completeRetained(older, receiptID: 120)
        presentation.recordRetained(newer, receiptID: 121)
        presentation.completeRetained(newer, receiptID: 121)

        XCTAssertEqual(presentation.retainedStates, [:])
        XCTAssertEqual(
            presentation.completedRetainedStates,
            [120: older, 121: newer]
        )
        XCTAssertEqual(
            presentation.failureMessage(currentState: .idle),
            """
            NMP could not deliver the message to wss://old.
            Message delivery outcome for wss://new is unknown.
            """
        )

        presentation.clearCompletedRetainedState()
        XCTAssertNil(presentation.failureMessage(currentState: .idle))
    }

    func testCompletedRetainedStatesKeepOnlyFourNewestReceipts() {
        var presentation = MessageReceiptPresentation()
        for receiptID in 1...20 {
            let state = MessageDeliveryState.acknowledged(
                receiptID: UInt64(receiptID),
                relay: "wss://\(receiptID)"
            )
            presentation.completeRetained(state, receiptID: UInt64(receiptID))
        }

        XCTAssertEqual(
            presentation.completedRetainedStates.keys.sorted(),
            [17, 18, 19, 20]
        )
    }

    func testActiveRetainedPresentationCannotGrowPastObservationLimit() {
        var presentation = MessageReceiptPresentation()
        for receiptID in 1...20 {
            presentation.recordRetained(
                .progressing(receiptID: UInt64(receiptID), progress: .accepted),
                receiptID: UInt64(receiptID)
            )
        }

        XCTAssertEqual(
            presentation.retainedStates.keys.sorted(),
            [17, 18, 19, 20]
        )
    }

    func testConcurrentReactionOutcomesQueueFailuresWithoutSuccessClearingThem() throws {
        var presentation = ReactionReceiptPresentation()
        let failed = MessageDeliveryState.converged(
            receiptID: 131,
            acknowledgedRelays: ["wss://one"],
            failures: [.rejected(relay: "wss://two", reason: "blocked")]
        )
        let laterSuccess = MessageDeliveryState.converged(
            receiptID: 132,
            acknowledgedRelays: ["wss://one"],
            failures: []
        )

        presentation.record(failed)
        presentation.record(laterSuccess)

        XCTAssertEqual(
            presentation.currentFailureMessage,
            "wss://two rejected the message: blocked"
        )
        XCTAssertEqual(presentation.states[131], failed)
        XCTAssertEqual(
            try XCTUnwrap(presentation.states[131]),
            .converged(
                receiptID: 131,
                acknowledgedRelays: ["wss://one"],
                failures: [.rejected(relay: "wss://two", reason: "blocked")]
            )
        )

        presentation.dismissCurrentFailure()
        XCTAssertNil(presentation.currentFailureMessage)
    }

    func testReactionFailuresQueueAndDismissIndependently() {
        var presentation = ReactionReceiptPresentation()
        presentation.recordSubmissionFailure("first")
        presentation.recordSubmissionFailure("second")

        XCTAssertEqual(presentation.currentFailureMessage, "first")
        presentation.dismissCurrentFailure()
        XCTAssertEqual(presentation.currentFailureMessage, "second")
        presentation.dismissCurrentFailure()
        XCTAssertNil(presentation.currentFailureMessage)
    }
}
