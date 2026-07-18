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

    func testNeutralHeldShowsPanelAndCancelWithoutInstructionalCopy() {
        let app = launch("neutralHeld")
        XCTAssertTrue(app.descendants(matching: .any)["voice-recording-panel"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["voice-cancel-track"].exists)
        // The removed defect: no explanatory sentence stands in for the affordance.
        XCTAssertFalse(app.staticTexts["Slide up to lock"].exists)
    }

    func testLockRailIsVisibleWhileProgressing() {
        let app = launch("lockHalf")
        XCTAssertTrue(app.descendants(matching: .any)["voice-lock-rail"].waitForExistence(timeout: 10))
    }

    func testCancelTrackVisibleWhileProgressing() {
        let app = launch("cancelHalf")
        XCTAssertTrue(app.descendants(matching: .any)["voice-cancel-track"].waitForExistence(timeout: 10))
    }

    func testLockedToolbarExposesEveryControl() {
        let app = launch("lockedRecording")
        XCTAssertTrue(app.descendants(matching: .any)["voice-locked-toolbar"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["voice-delete"].exists)
        XCTAssertTrue(app.buttons["voice-pause-resume"].exists)
        XCTAssertTrue(app.buttons["voice-send"].exists)
    }

    func testPausedShowsResumeControl() {
        let app = launch("paused")
        let resume = app.buttons["voice-pause-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        XCTAssertEqual(resume.label, "Resume recording")
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
