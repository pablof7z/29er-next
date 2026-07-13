import XCTest

@MainActor
final class RoomOpenDeviceProofTests: XCTestCase {
    private let expectedGroupID = "nmp-scale-hot-room"
    private let expectedContentRows = "200"
    private let expectedMessageRows = "200"
    private let expectedActivityRows = "0"
    private let expectedContentNewestID = "4718e3ccdff3511ade3b5b96b3a2f8561afc888f7b78ed2ff2c698e910743cc8"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NMP_DEVICE_PROOF"] == "1",
            "Run only for the explicit physical-device proof gate."
        )
    }

    func testColdAndWarmBusyRoomDistributions() throws {
        let groupID = try proofGroupID()
        print(
            "NMP_ROOM_OPEN_PROOF_CONFIG group=\(groupID) expectedContentRows=\(expectedContentRows) "
            + "expectedMessageRows=\(expectedMessageRows) expectedActivityRows=\(expectedActivityRows) "
            + "expectedContentNewest=\(expectedContentNewestID)"
        )

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
            try assertProofReport(report, mode: "cold", run: run, groupID: groupID)
            print("NMP_ROOM_OPEN_PROOF mode=cold run=\(run) \(report)")
        }

        for run in 1...10 {
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10), "room back button missing")
            back.tap()
            let report = try openRoom(in: app)
            try assertProofReport(report, mode: "warm", run: run, groupID: groupID)
            print("NMP_ROOM_OPEN_PROOF mode=warm run=\(run) \(report)")
        }
    }

    private func proofGroupID() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        let groupID = try XCTUnwrap(
            environment["NMP_DEVICE_PROOF_GROUP"],
            "NMP_DEVICE_PROOF_GROUP must be set by the DeviceProof scheme"
        )
        XCTAssertEqual(
            groupID,
            expectedGroupID,
            "DeviceProof must target the million-row fixture hot room"
        )
        return groupID
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

    private func assertProofReport(
        _ report: String,
        mode: String,
        run: Int,
        groupID: String
    ) throws {
        let fields = proofFields(from: report)
        XCTAssertEqual(fields["group"], groupID, "\(mode) run \(run) launched unexpected group")
        XCTAssertEqual(fields["contentRows"], expectedContentRows, "\(mode) run \(run) content rows")
        XCTAssertEqual(fields["messageRows"], expectedMessageRows, "\(mode) run \(run) message rows")
        XCTAssertEqual(fields["activityRows"], expectedActivityRows, "\(mode) run \(run) activity rows")
        XCTAssertEqual(
            fields["contentNewest"],
            expectedContentNewestID,
            "\(mode) run \(run) content newest ID"
        )
    }

    private func proofFields(from report: String) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: report
                .split(separator: " ")
                .compactMap { field -> (String, String)? in
                    guard let separator = field.firstIndex(of: "=") else { return nil }
                    let key = String(field[..<separator])
                    let value = String(field[field.index(after: separator)...])
                    return (key, value)
                }
        )
    }
}
