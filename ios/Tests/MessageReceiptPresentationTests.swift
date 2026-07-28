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
}
