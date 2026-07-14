import XCTest

@MainActor
final class RoomOpenDeviceProofTests: XCTestCase {
    private let expectedGroupID = "nmp-scale-hot-room"
    private let expectedContentRows = "200"
    private let expectedMessageRows = "200"
    private let expectedActivityRows = "0"
    private let expectedContentNewestID = "4718e3ccdff3511ade3b5b96b3a2f8561afc888f7b78ed2ff2c698e910743cc8"
    private let expectedStoreSize = "2155876352"
    private let expectedStoreSHA256 = "81361224ae95eefed42ab4fe9b437742c1a91012e12ab8905994039f05d24ff5"
    private let expectedEpochHex = "360a"
    private let expectedEpoch = "6"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NMP_DEVICE_PROOF"] == "1",
            "Run only for the explicit physical-device proof gate."
        )
    }

    func testColdAndWarmBusyRoomDistributions() throws {
        try assertInertDefaultMode()
        try assertCorpusPreflightMode()

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

    private func assertInertDefaultMode() throws {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        let inert = app.descendants(matching: .any)["nmp-proof-inert"]
        XCTAssertTrue(inert.waitForExistence(timeout: 10), "proof app did not stay inert by default")
        XCTAssertTrue(inert.label.contains("engine=not-started"), "proof inert report changed")
        XCTAssertFalse(
            app.buttons["room-open-proof-shortcut"].exists,
            "proof app reached room UI without an explicit proof mode"
        )
        print("NMP_PROOF_INERT \(inert.label)")
    }

    private func assertCorpusPreflightMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--nmp-corpus-preflight"]
        app.launch()
        defer { app.terminate() }

        let preflight = app.descendants(matching: .any)["nmp-corpus-preflight"]
        XCTAssertTrue(preflight.waitForExistence(timeout: 300), "corpus preflight report missing")
        let completed = NSPredicate(format: "label BEGINSWITH 'complete '")
        let expectation = XCTNSPredicateExpectation(predicate: completed, object: preflight)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 300),
            .completed,
            "corpus preflight did not complete"
        )

        let report = preflight.label
        let fields = proofFields(from: report)
        XCTAssertEqual(fields["size"], expectedStoreSize, "corpus preflight size")
        XCTAssertEqual(fields["sha256"], expectedStoreSHA256, "corpus preflight SHA-256")
        XCTAssertEqual(fields["epochHex"], expectedEpochHex, "corpus preflight epoch bytes")
        XCTAssertEqual(fields["epoch"], expectedEpoch, "corpus preflight epoch value")
        XCTAssertFalse(
            app.buttons["room-open-proof-shortcut"].exists,
            "corpus preflight constructed the room UI"
        )
        print("NMP_CORPUS_PREFLIGHT \(report)")
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
