import XCTest

@MainActor
final class AudioPlayerDeviceProofTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NMP_DEVICE_PROOF"] == "1",
            "Run only for the explicit device proof gate."
        )
    }

    func testInlineVoiceBubbleOpensPersistentPlayerAcrossNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--audio-player-proof"]
        app.launch()

        let attachment = app.descendants(matching: .any)["audio-attachment"]
        XCTAssertTrue(attachment.waitForExistence(timeout: 10), "voice-message bubble missing")

        let play = app.buttons["audio-attachment-playback-toggle"]
        XCTAssertTrue(play.waitForExistence(timeout: 5), "voice-message play button missing")
        play.tap()

        let miniPlayer = app.descendants(matching: .any)["audio-mini-player"]
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5), "persistent mini-player missing")

        let navigateAway = app.buttons["audio-player-navigate-away"]
        XCTAssertTrue(navigateAway.waitForExistence(timeout: 5), "navigation proof control missing")
        navigateAway.tap()

        let awayScreen = app.descendants(matching: .any)["audio-player-away-screen"]
        XCTAssertTrue(awayScreen.waitForExistence(timeout: 5), "navigation did not complete")
        XCTAssertTrue(miniPlayer.exists, "mini-player disappeared after leaving the source screen")
        XCTAssertTrue(app.buttons["audio-mini-player-toggle"].exists, "mini-player transport missing")

        let close = app.buttons["audio-mini-player-close"]
        XCTAssertTrue(close.exists, "mini-player close control missing")
        close.tap()
        XCTAssertFalse(miniPlayer.waitForExistence(timeout: 1), "mini-player remained after close")
    }
}
