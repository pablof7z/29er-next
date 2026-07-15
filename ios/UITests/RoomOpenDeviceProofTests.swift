import XCTest

@MainActor
final class RoomOpenDeviceProofTests: XCTestCase {
    private let expectedGroupID = "nmp-scale-hot-room"
    private let expectedContentRows = "200"
    private let expectedMessageRows = "200"
    private let expectedActivityRows = "0"
    private let expectedContentNewestID =
        "4718e3ccdff3511ade3b5b96b3a2f8561afc888f7b78ed2ff2c698e910743cc8"
    private let expectedProfileRows = "32"
    private let expectedProfileNewestID =
        "c99de8f6e0d3001367faaffd886ae02cf1a363b5da84ce7fd0045342d2229e99"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NMP_DEVICE_PROOF"] == "1",
            "Run only for the explicit physical-device proof gate."
        )
        _ = try requiredEnvironment("NMP_DEVICE_PROOF_STORE_SIZE")
        _ = try requiredEnvironment("NMP_DEVICE_PROOF_STORE_SHA256")
    }

    func testColdAndWarmBusyRoomDistributions() throws {
        try assertInertDefaultMode()
        try assertCorpusPreflightMode()

        let app = XCUIApplication()
        app.launchArguments = [
            "--nmp-room-open-proof",
            "--nmp-room-open-proof-group", expectedGroupID,
            "--nmp-room-open-proof-offline-relay", "wss://nmp-device-proof.invalid"
        ]

        for run in 1...5 {
            app.terminate()
            app.launch()
            let report = try openRoom(in: app)
            try assertProofReport(report, mode: "cold", run: run)
            print("NMP_PRE_NOSTRDB_ROOM_OPEN_PROOF mode=cold run=\(run) \(report)")
        }

        for run in 1...10 {
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10), "room back button missing")
            back.tap()
            let report = try openRoom(in: app)
            try assertProofReport(report, mode: "warm", run: run)
            print("NMP_PRE_NOSTRDB_ROOM_OPEN_PROOF mode=warm run=\(run) \(report)")
        }
    }

    private func assertInertDefaultMode() throws {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        let inert = app.descendants(matching: .any)["nmp-proof-inert"]
        XCTAssertTrue(inert.waitForExistence(timeout: 10), "proof app did not stay inert")
        XCTAssertTrue(inert.label.contains("engine=not-started"), "proof inert report changed")
        XCTAssertFalse(app.buttons["room-open-proof-shortcut"].exists)
        print("NMP_PRE_NOSTRDB_PROOF_INERT \(inert.label)")
    }

    private func assertCorpusPreflightMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--nmp-corpus-preflight"]
        app.launch()
        defer { app.terminate() }

        let preflight = app.descendants(matching: .any)["nmp-corpus-preflight"]
        XCTAssertTrue(preflight.waitForExistence(timeout: 300), "corpus preflight missing")
        let completed = NSPredicate(format: "label BEGINSWITH 'complete '")
        let expectation = XCTNSPredicateExpectation(predicate: completed, object: preflight)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 300), .completed)

        let fields = proofFields(from: preflight.label)
        XCTAssertEqual(fields["size"], try requiredEnvironment("NMP_DEVICE_PROOF_STORE_SIZE"))
        XCTAssertEqual(fields["sha256"], try requiredEnvironment("NMP_DEVICE_PROOF_STORE_SHA256"))
        XCTAssertFalse(app.buttons["room-open-proof-shortcut"].exists)
        print("NMP_PRE_NOSTRDB_CORPUS_PREFLIGHT \(preflight.label)")
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
        XCTAssertTrue(proof.waitForExistence(timeout: 30), "room proof panel missing")
        let completed = NSPredicate(format: "label BEGINSWITH 'complete '")
        let expectation = XCTNSPredicateExpectation(predicate: completed, object: proof)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 300),
            .completed,
            "historical room query graph did not complete"
        )
        return proof.label
    }

    private func assertProofReport(_ report: String, mode: String, run: Int) throws {
        let fields = proofFields(from: report)
        XCTAssertEqual(fields["group"], expectedGroupID, "\(mode) run \(run) group")
        XCTAssertEqual(fields["contentRows"], expectedContentRows, "\(mode) run \(run) content")
        XCTAssertEqual(fields["messageRows"], expectedMessageRows, "\(mode) run \(run) messages")
        XCTAssertEqual(fields["activityRows"], expectedActivityRows, "\(mode) run \(run) activity")
        XCTAssertEqual(fields["contentNewest"], expectedContentNewestID, "\(mode) run \(run) newest")
        XCTAssertEqual(fields["messageNewest"], expectedContentNewestID, "\(mode) run \(run) message newest")
        XCTAssertEqual(fields["profilesRows"], expectedProfileRows, "\(mode) run \(run) profiles")
        XCTAssertEqual(fields["profilesNewest"], expectedProfileNewestID, "\(mode) run \(run) profile newest")
        XCTAssertEqual(fields["membershipRows"], "0", "\(mode) run \(run) membership")
        XCTAssertEqual(fields["adminsRows"], "0", "\(mode) run \(run) admins")
    }

    private func requiredEnvironment(_ name: String) throws -> String {
        let value = try XCTUnwrap(ProcessInfo.processInfo.environment[name], "\(name) is required")
        XCTAssertFalse(value.isEmpty, "\(name) must not be empty")
        return value
    }

    private func proofFields(from report: String) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: report.split(separator: " ").compactMap { field -> (String, String)? in
                guard let separator = field.firstIndex(of: "=") else { return nil }
                return (
                    String(field[..<separator]),
                    String(field[field.index(after: separator)...])
                )
            }
        )
    }
}
