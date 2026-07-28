import XCTest

/// Deterministic UI coverage of the voice composer's visible states. Each case launches
/// the proof surface in an injected state and asserts the affordances and accessibility
/// identifiers a user (and VoiceOver) would rely on — no microphone, no timing.
@MainActor
final class VoiceComposerDeviceProofTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NMP_DEVICE_PROOF"] == "1",
            "Run only for the explicit device proof gate."
        )
    }

    private func launch(_ state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--voice-composer-proof", "--voice-proof-state", state]
        app.launch()
        return app
    }

    func testIdleShowsMicrophone() {
        let app = launch("idle")
        XCTAssertTrue(app.buttons["room-message-mic"].waitForExistence(timeout: 10))
    }

    func testIdleComposerAcceptsKeyboardFocus() {
        let app = launch("idle")
        let editor = app.textFields["room-message-composer"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))

        editor.tap()
        editor.typeText("x")

        XCTAssertEqual(editor.value as? String, "x")
        XCTAssertTrue(app.buttons["room-message-send"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["room-message-send"].isHittable)
        XCTAssertTrue(app.buttons["room-message-attach"].isHittable)
    }

    /// Tap-once: a single mic tap drops straight into the locked recording bar, which
    /// exposes cancel (✕), stop (◼ → review), and send (↑) — no held panel, no slide-to-
    /// lock rail, no slide-to-cancel track, no pause.
    func testLockedToolbarExposesCancelStopAndSend() {
        let app = launch("lockedRecording")
        XCTAssertTrue(app.descendants(matching: .any)["voice-locked-toolbar"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["voice-delete"].exists)
        XCTAssertTrue(app.buttons["voice-stop"].exists)
        XCTAssertTrue(app.buttons["voice-send"].exists)
    }

    func testCompletedDraftShowsVoiceCardNotFilename() {
        let app = launch("completedDraft")
        XCTAssertTrue(app.descendants(matching: .any)["voice-draft-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["voice-preview-toggle"].exists)
        XCTAssertTrue(app.buttons["voice-send"].exists)
        // No generated UUID filename in the primary UI.
        XCTAssertFalse(app.staticTexts["voice-proof.m4a"].exists)
    }

    func testPermissionDeniedIsRecoverable() {
        let app = launch("permissionDenied")
        XCTAssertTrue(app.descendants(matching: .any)["voice-permission-denied"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["voice-open-settings"].exists)
    }

    func testPublishFailureExposesRetry() {
        let app = launch("publishFailure")
        XCTAssertTrue(app.descendants(matching: .any)["voice-draft-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["voice-retry"].exists)
        XCTAssertTrue(app.staticTexts["voice-draft-error"].exists)
    }
}
