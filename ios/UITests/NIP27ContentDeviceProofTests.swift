import XCTest

@MainActor
final class NIP27ContentDeviceProofTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NMP_DEVICE_PROOF"] == "1",
            "Run only for the explicit device proof gate."
        )
    }

    func testValidatedReferenceRendersAndMalformedReferenceStaysVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["--markdown-message-proof"]
        app.launch()

        XCTAssertTrue(app.otherElements["markdown-message-proof"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "npub14f8us…h9nsy")
            ).firstMatch.exists
        )
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "nostr:npub1notvalid")
            ).firstMatch.exists
        )
    }
}
