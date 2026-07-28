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
        XCTAssertTrue(app.buttons["Remove room-photo.png"].exists)
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

    func testLiveComposerUploadUsesNMPBlossom() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NMP_BLOSSOM_LIVE_PROOF"] == "1",
            "Run only for the explicit bounded live Blossom proof."
        )
        let app = XCUIApplication()
        app.launchArguments = ["--attachment-composer-proof", "--attachment-upload-proof"]
        app.launch()

        let send = app.buttons["room-message-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        XCTAssertTrue(send.isEnabled)
        send.tap()

        let status = app.staticTexts["attachment-upload-proof-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 30))
        let pubkey = app.staticTexts["attachment-upload-proof-pubkey"]
        XCTAssertTrue(pubkey.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "succeeded", "proof pubkey: \(pubkey.label)")
        XCTAssertFalse(
            app.descendants(matching: .any)["room-composer-attachments"]
                .waitForExistence(timeout: 1)
        )
    }
}
