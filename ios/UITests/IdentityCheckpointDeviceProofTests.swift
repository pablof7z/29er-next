import XCTest

@MainActor
final class IdentityCheckpointDeviceProofTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NMP_DEVICE_PROOF"] == "1",
            "Run only for the explicit device proof gate."
        )
    }

    func testSignedOutIdentityExplainsTheGovernedKeychainCheckpoint() {
        let app = XCUIApplication()
        app.launchArguments = ["--identity-checkpoint-proof"]
        app.launch()

        XCTAssertTrue(app.secureTextFields["identity-secret-field"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts[
                "NMP saves the key in the device Keychain for automatic login. It is "
                    + "readable only after this device has been unlocked, and is never "
                    + "synced to another device."
            ].exists
        )
    }
}
