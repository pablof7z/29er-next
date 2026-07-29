import Foundation
import XCTest
@testable import TwentyNinerNext

final class NMPStoreIdentityTests: XCTestCase {
    func testPrepareCreatesAndReusesAStableGeneration() throws {
        let harness = IdentityHarness()
        let identity = harness.identity()

        let first = try identity.prepare(
            appDirectory: harness.directory,
            storePath: harness.storePath
        )
        let second = try identity.prepare(
            appDirectory: harness.directory,
            storePath: harness.storePath
        )

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(second, first)
        XCTAssertEqual(harness.resetPaths, [])
        XCTAssertEqual(try harness.markerPhase(), "ready")
    }

    func testInterruptedResetIsFinishedBeforeGenerationReuse() throws {
        let harness = IdentityHarness()
        let identity = harness.identity()
        let generation = try identity.beginReset(appDirectory: harness.directory)

        let recovered = try identity.prepare(
            appDirectory: harness.directory,
            storePath: harness.storePath
        )

        XCTAssertEqual(recovered, generation)
        XCTAssertEqual(harness.resetPaths, [harness.storePath])
        XCTAssertEqual(try harness.markerPhase(), "ready")
    }

    func testResetFailureLeavesResettingMarkerForRetry() throws {
        enum Failure: Error { case reset }
        let harness = IdentityHarness()
        let generation = try harness.identity()
            .beginReset(appDirectory: harness.directory)
        harness.resetError = Failure.reset

        XCTAssertThrowsError(
            try harness.identity().prepare(
                appDirectory: harness.directory,
                storePath: harness.storePath
            )
        )
        XCTAssertEqual(try harness.markerPhase(), "resetting")
        XCTAssertEqual(try harness.markerGeneration(), generation)
    }

    func testUnsupportedOrMalformedMarkersFailWithoutResettingStore() throws {
        let harness = IdentityHarness()
        harness.markerData = Data(
            #"{"version":2,"generation":"old","phase":"ready"}"#.utf8
        )

        XCTAssertThrowsError(
            try harness.identity().prepare(
                appDirectory: harness.directory,
                storePath: harness.storePath
            )
        ) { error in
            XCTAssertEqual(error as? NMPStoreIdentityError, .unsupportedVersion(2))
        }
        XCTAssertEqual(harness.resetPaths, [])

        harness.markerData = Data("not-json".utf8)
        XCTAssertThrowsError(
            try harness.identity().prepare(
                appDirectory: harness.directory,
                storePath: harness.storePath
            )
        )
        XCTAssertEqual(harness.resetPaths, [])
    }
}

private final class IdentityHarness {
    let directory = URL(fileURLWithPath: "/app")
    let storePath = "/app/nmp.redb"
    var markerData: Data?
    var resetPaths: [String] = []
    var resetError: Error?

    func identity() -> NMPStoreIdentity {
        NMPStoreIdentity(
            fileExists: { [weak self] _ in self?.markerData != nil },
            read: { [weak self] _ in
                guard let data = self?.markerData else {
                    throw CocoaError(.fileNoSuchFile)
                }
                return data
            },
            resetStore: { [weak self] path in
                self?.resetPaths.append(path)
                if let error = self?.resetError {
                    throw error
                }
            },
            writeDurably: { [weak self] data, _ in
                self?.markerData = data
            }
        )
    }

    func markerPhase() throws -> String {
        try markerValue("phase")
    }

    func markerGeneration() throws -> String {
        try markerValue("generation")
    }

    private func markerValue(_ key: String) throws -> String {
        let data = try XCTUnwrap(markerData)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try XCTUnwrap(object[key] as? String)
    }
}
