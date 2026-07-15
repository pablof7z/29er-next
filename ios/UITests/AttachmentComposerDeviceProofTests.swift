import XCTest

@MainActor
final class AttachmentComposerDeviceProofTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NMP_DEVICE_PROOF"] == "1",
            "Run only for the explicit device proof gate."
        )
    }

    func testAttachmentComposerShowsPreviewsAndSendsWithoutRawDraftURLs() {
        let app = XCUIApplication()
        app.launchArguments = ["--attachment-composer-proof"]
        app.launch()

        XCTAssertTrue(app.buttons["room-message-attach"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["room-composer-attachments"].exists)
        XCTAssertTrue(app.staticTexts["room-photo.png"].exists)
        XCTAssertTrue(app.staticTexts["notes.pdf"].exists)

        let editor = app.textFields["room-message-composer"]
        XCTAssertTrue(editor.exists)
        XCTAssertTrue((editor.value as? String)?.contains("http") == false)

        app.buttons["Remove notes.pdf"].tap()
        XCTAssertFalse(app.staticTexts["notes.pdf"].exists)
        XCTAssertTrue(app.buttons["room-message-send"].isEnabled)
        app.buttons["room-message-send"].tap()
        XCTAssertFalse(
            app.descendants(matching: .any)["room-composer-attachments"]
                .waitForExistence(timeout: 1)
        )
    }
}
