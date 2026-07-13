import XCTest

@MainActor
final class RoomOpenDeviceProofTests: XCTestCase {
    private let groupID = "nostr-multi-platform"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NMP_DEVICE_PROOF"] == "1",
            "Run only for the explicit physical-device proof gate."
        )
    }

    func testColdAndWarmBusyRoomDistributions() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nmp-room-open-proof",
            "--nmp-room-open-proof-group", groupID,
            "--nmp-room-open-proof-offline-relay", "wss://nmp-device-proof.invalid"
        ]

        for run in 1...5 {
            app.terminate()
            app.launch()
            let report = try openRoom(in: app)
            print("NMP_ROOM_OPEN_PROOF mode=cold run=\(run) \(report)")
        }

        for run in 1...10 {
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10), "room back button missing")
            back.tap()
            let report = try openRoom(in: app)
            print("NMP_ROOM_OPEN_PROOF mode=warm run=\(run) \(report)")
        }
    }

    private func openRoom(in app: XCUIApplication) throws -> String {
        let shortcut = app.buttons["room-open-proof-shortcut"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 60), "busy room did not appear")
        shortcut.tap()

        XCTAssertTrue(
            app.buttons["room-people-button"].waitForExistence(timeout: 10),
            "room navigation did not complete"
        )
        let proof = app.descendants(matching: .any)["room-open-proof"]
        XCTAssertTrue(proof.waitForExistence(timeout: 30), "room proof panel did not appear")
        let completed = NSPredicate(format: "label BEGINSWITH 'complete '")
        let expectation = XCTNSPredicateExpectation(predicate: completed, object: proof)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 30),
            .completed,
            "room query graph did not produce a complete first snapshot"
        )
        return proof.label
    }
}
