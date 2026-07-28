import XCTest

@MainActor
final class MessageReceiptDeviceProofTests: XCTestCase {
    func testAcceptedAckRejectionAndAmbiguityRemainDistinct() {
        let app = XCUIApplication()
        app.launchArguments = ["--message-receipt-proof"]
        app.launch()
        defer { app.terminate() }

        let report = app.staticTexts["message-receipt-proof-state"]
        XCTAssertTrue(report.waitForExistence(timeout: 10))
        XCTAssertEqual(report.label, "idle terminal=false")

        app.buttons["message-receipt-proof-accepted"].tap()
        assert(
            report,
            contains: "progress=Saved by NMP; delivering… terminal=false"
        )
        XCTAssertTrue(
            app.staticTexts["room-composer-sending"].waitForExistence(timeout: 10)
        )

        app.buttons["message-receipt-proof-acked"].tap()
        assert(
            report,
            contains: "acked=wss://groups.example terminal=true"
        )

        app.buttons["message-receipt-proof-rejected"].tap()
        assert(
            report,
            contains: "wss://groups.example rejected the message: permission denied"
        )
        let productError = app.staticTexts["room-composer-error"]
        XCTAssertTrue(productError.waitForExistence(timeout: 10))
        assert(productError, contains: "rejected the message: permission denied")

        app.buttons["message-receipt-proof-ambiguous"].tap()
        assert(
            report,
            contains: "Message delivery outcome for wss://groups.example is unknown."
        )

        app.buttons["message-receipt-proof-reaction-failure"].tap()
        let alert = app.alerts["Couldn’t Send Reaction"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(
            alert.staticTexts[
                "wss://groups.example rejected the reaction: permission denied"
            ].exists
        )
        alert.buttons["OK"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 2))
    }

    private func assert(_ element: XCUIElement, contains text: String) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 10),
            .completed,
            "Expected receipt proof to contain \(text); got \(element.label)"
        )
    }
}
