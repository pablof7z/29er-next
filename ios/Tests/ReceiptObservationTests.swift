import NMP
import XCTest
@testable import TwentyNinerNext

@MainActor
final class ReceiptObservationTests: XCTestCase {
    func testCrashRecoverableSubmissionPersistsCorrelationBeforePublish() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("receipt-submit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DurableReceiptStore(
            rootDirectory: root,
            storeGeneration: "generation-a",
            scope: .reaction,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )
        var correlationDuringPublish: [String] = []

        let submission = try await submitCrashRecoverableWrite(
            correlation: "reaction-correlation",
            maximumRecoveryCount: 4,
            store: store,
            publish: {
                correlationDuringPublish = try store.loadCorrelations()
                return TestReceipt(id: 41)
            },
            receiptID: \.id
        )

        let reopened = DurableReceiptStore(
            rootDirectory: root,
            storeGeneration: "generation-a",
            scope: .reaction,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )
        XCTAssertEqual(submission.value.id, 41)
        XCTAssertNil(submission.recoveryPersistenceFailure)
        XCTAssertEqual(correlationDuringPublish, ["reaction-correlation"])
        XCTAssertEqual(try reopened.loadReceiptIDs(), [41])
        XCTAssertEqual(try reopened.loadCorrelations(), [])
    }

    func testPreAcceptancePublishFailureRemovesRecoveryCorrelation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("receipt-submit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DurableReceiptStore(
            rootDirectory: root,
            storeGeneration: "generation-a",
            scope: .reaction,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )

        do {
            _ = try await submitCrashRecoverableWrite(
                correlation: "accepted-before-interruption",
                maximumRecoveryCount: 4,
                store: store,
                publish: { () async throws -> TestReceipt in
                    throw TestPublishFailure.refused
                },
                receiptID: \.id
            )
            XCTFail("Expected publication refusal")
        } catch is TestPublishFailure {
            let reopened = DurableReceiptStore(
                rootDirectory: root,
                storeGeneration: "generation-a",
                scope: .reaction,
                account: "alice",
                host: "wss://one",
                groupID: "room"
            )
            XCTAssertEqual(
                try reopened.loadCorrelations(),
                []
            )
            XCTAssertEqual(try reopened.loadReceiptIDs(), [])
        }
    }

    func testCancelledSubmissionDoesNotCreateARecoveryIdentity() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("receipt-submit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DurableReceiptStore(
            rootDirectory: root,
            storeGeneration: "generation-a",
            scope: .reaction,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await submitCrashRecoverableWrite(
                correlation: "cancelled-before-publish",
                maximumRecoveryCount: 4,
                store: store,
                publish: { TestReceipt(id: 51) },
                receiptID: \.id
            )
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(try store.recoveryIdentityCount, 0)
        }
    }

    func testUnreadableRecoveryJournalRefusesBeforePublish() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("receipt-submit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DurableReceiptStore(
            rootDirectory: root,
            storeGeneration: "generation-a",
            scope: .reaction,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )
        try store.reserveCorrelation("existing", maximumCount: 4)
        let journalDirectory = root
            .appendingPathComponent("receipt-recovery")
            .appendingPathComponent("generation-a")
        let journal = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: journalDirectory,
                includingPropertiesForKeys: nil
            ).first
        )
        try Data("not-json".utf8).write(to: journal, options: .atomic)
        var didPublish = false

        do {
            _ = try await submitCrashRecoverableWrite(
                correlation: "must-not-publish",
                maximumRecoveryCount: 4,
                store: store,
                publish: {
                    didPublish = true
                    return TestReceipt(id: 61)
                },
                receiptID: \.id
            )
            XCTFail("Expected unreadable journal refusal")
        } catch {
            XCTAssertFalse(didPublish)
        }
    }

    func testPostAcceptanceJournalFailureStillReturnsTheAcceptedReceipt() async throws {
        let store = FailingReplacementStore()
        let submission = try await submitCrashRecoverableWrite(
            correlation: "accepted",
            maximumRecoveryCount: 4,
            store: store,
            publish: { TestReceipt(id: 71) },
            receiptID: \.id
        )

        XCTAssertEqual(submission.value.id, 71)
        XCTAssertEqual(submission.recoveryPersistenceFailure, "replacement failed")
        XCTAssertEqual(store.correlations, ["accepted"])
    }

    func testPreAcceptanceCleanupFailureIsNotHidden() async throws {
        let store = FailingRemovalStore()

        do {
            _ = try await submitCrashRecoverableWrite(
                correlation: "refused",
                maximumRecoveryCount: 4,
                store: store,
                publish: { () async throws -> TestReceipt in
                    throw TestPublishFailure.refused
                },
                receiptID: \.id
            )
            XCTFail("Expected cleanup failure")
        } catch let error as ReceiptPreAcceptanceCleanupError {
            XCTAssertTrue(error.publicationFailure.contains("refused"))
            XCTAssertEqual(error.cleanupFailure, "cleanup failed")
            XCTAssertEqual(store.correlations, ["refused"])
        }
    }

    func testRepeatedLagReattachesIterativelyAndPreservesMixedTerminalEvidence() async throws {
        let driver = ScriptedReceiptDriver(
            remainingLags: 256,
            terminalStatuses: [
                .acked(relay: "wss://one"),
                .rejected(relay: "wss://two", reason: "blocked")
            ]
        )
        var observedIDs: [UInt64] = []
        var states: [MessageDeliveryState] = []

        let outcome = await observeReceiptThroughClosure(
            initial: ScriptedReceiptDriver.Segment(id: 141),
            driver: driver,
            onReceiptID: { observedIDs.append($0) },
            onState: { states.append($0) }
        )

        XCTAssertEqual(driver.consumeCount, 257)
        XCTAssertEqual(driver.reattachIDs, Array(repeating: 141, count: 256))
        XCTAssertEqual(observedIDs, Array(repeating: 141, count: 257))
        XCTAssertEqual(
            try XCTUnwrap(outcome),
            ReceiptObservationOutcome(
                state: .converged(
                    receiptID: 141,
                    acknowledgedRelays: ["wss://one"],
                    failures: [.rejected(relay: "wss://two", reason: "blocked")]
                ),
                shouldForgetReceipt: true
            )
        )
        XCTAssertEqual(states.last, outcome?.state)
    }

    func testLagReattachNotFoundIsTypedAndForgettable() async throws {
        let driver = ScriptedReceiptDriver(
            remainingLags: 1,
            terminalStatuses: [],
            reattachResult: .notFound
        )

        let outcome = await observeReceiptThroughClosure(
            initial: ScriptedReceiptDriver.Segment(id: 151),
            driver: driver,
            onReceiptID: { _ in },
            onState: { _ in }
        )

        XCTAssertEqual(
            try XCTUnwrap(outcome),
            ReceiptObservationOutcome(
                state: .failed(
                    receiptID: 151,
                    failure: .receiptNotFound(receiptID: 151)
                ),
                shouldForgetReceipt: true
            )
        )
    }

    func testReplayUnavailableKeepsCorrelationAndTypedIdentity() async throws {
        let driver = ScriptedReceiptDriver(
            remainingLags: 1,
            terminalStatuses: [],
            replayUnavailable: true
        )

        let outcome = await observeReceiptThroughClosure(
            initial: ScriptedReceiptDriver.Segment(id: 161),
            driver: driver,
            onReceiptID: { _ in },
            onState: { _ in }
        )

        XCTAssertEqual(
            try XCTUnwrap(outcome),
            ReceiptObservationOutcome(
                state: .failed(
                    receiptID: 161,
                    failure: .receiptReplayUnavailable(receiptID: 161)
                ),
                shouldForgetReceipt: false
            )
        )
    }

    func testLagWithoutNamedReplayReceiptReattachesCurrentReceipt() async throws {
        let driver = ScriptedReceiptDriver(
            remainingLags: 1,
            terminalStatuses: [.acked(relay: "wss://one")],
            unnamedLag: true
        )

        let outcome = await observeReceiptThroughClosure(
            initial: ScriptedReceiptDriver.Segment(id: 171),
            driver: driver,
            onReceiptID: { _ in },
            onState: { _ in }
        )

        XCTAssertEqual(driver.reattachIDs, [171])
        XCTAssertEqual(outcome?.state.receiptID, 171)
        XCTAssertEqual(outcome?.shouldForgetReceipt, true)
    }

    func testCancellationReturnsNoClaimedOutcome() async {
        let driver = ScriptedReceiptDriver(
            remainingLags: 0,
            terminalStatuses: [],
            cancelDuringConsume: true
        )
        var states: [MessageDeliveryState] = []

        let task = Task { @MainActor in
            await observeReceiptThroughClosure(
                initial: ScriptedReceiptDriver.Segment(id: 181),
                driver: driver,
                onReceiptID: { _ in },
                onState: { states.append($0) }
            )
        }

        let outcome = await task.value
        XCTAssertNil(outcome)
        XCTAssertEqual(states, [])
    }
}

private struct TestReceipt {
    let id: UInt64
}

private enum TestPublishFailure: LocalizedError {
    case refused

    var errorDescription: String? { "publish refused" }
}

@MainActor
private final class FailingReplacementStore: ReceiptRecoveryStoring {
    enum Failure: LocalizedError {
        case replacement

        var errorDescription: String? { "replacement failed" }
    }

    private(set) var correlations: [String] = []

    func reserveCorrelation(_ correlation: String, maximumCount: Int) {
        correlations.append(correlation)
    }

    func replaceCorrelation(_ correlation: String, with receiptID: UInt64) throws {
        throw Failure.replacement
    }

    func removeCorrelation(_ correlation: String) {
        correlations.removeAll { $0 == correlation }
    }
}

@MainActor
private final class FailingRemovalStore: ReceiptRecoveryStoring {
    enum Failure: LocalizedError {
        case cleanup

        var errorDescription: String? { "cleanup failed" }
    }

    private(set) var correlations: [String] = []

    func reserveCorrelation(_ correlation: String, maximumCount: Int) {
        correlations.append(correlation)
    }

    func replaceCorrelation(_ correlation: String, with receiptID: UInt64) {}

    func removeCorrelation(_ correlation: String) throws {
        throw Failure.cleanup
    }
}

@MainActor
private final class ScriptedReceiptDriver: ReceiptObservationDriving {
    struct Segment {
        let id: UInt64
    }

    var remainingLags: Int
    let terminalStatuses: [WriteStatus]
    let reattachResult: ReceiptObservationReattachment<Segment>?
    let replayUnavailable: Bool
    let unnamedLag: Bool
    let cancelDuringConsume: Bool
    private(set) var consumeCount = 0
    private(set) var reattachIDs: [UInt64] = []

    init(
        remainingLags: Int,
        terminalStatuses: [WriteStatus],
        reattachResult: ReceiptObservationReattachment<Segment>? = nil,
        replayUnavailable: Bool = false,
        unnamedLag: Bool = false,
        cancelDuringConsume: Bool = false
    ) {
        self.remainingLags = remainingLags
        self.terminalStatuses = terminalStatuses
        self.reattachResult = reattachResult
        self.replayUnavailable = replayUnavailable
        self.unnamedLag = unnamedLag
        self.cancelDuringConsume = cancelDuringConsume
    }

    func receiptID(for segment: Segment) -> UInt64 {
        segment.id
    }

    func consume(
        _ segment: Segment,
        onState: (MessageDeliveryState) -> Void
    ) async throws -> MessageReceiptConvergence? {
        consumeCount += 1
        if cancelDuringConsume {
            withUnsafeCurrentTask { task in task?.cancel() }
            return nil
        }
        if remainingLags > 0 {
            remainingLags -= 1
            throw NMPError.factStreamLagged(receiptId: unnamedLag ? nil : segment.id)
        }
        var convergence = MessageReceiptConvergence()
        for status in terminalStatuses {
            onState(convergence.apply(status, receiptID: segment.id))
        }
        return convergence
    }

    func reattach(receiptID: UInt64) throws -> ReceiptObservationReattachment<Segment> {
        reattachIDs.append(receiptID)
        if replayUnavailable {
            throw NMPError.receiptReplayUnavailable(receiptId: receiptID)
        }
        return reattachResult ?? .attached(Segment(id: receiptID))
    }
}
