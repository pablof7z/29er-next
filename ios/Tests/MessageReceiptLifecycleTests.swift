import Foundation
import NMP
import XCTest
@testable import TwentyNinerNext

@MainActor
final class MessageReceiptLifecycleTests: XCTestCase {
    func testAcceptedRemainsIntermediateUntilAcknowledged() {
        let accepted = MessageDeliveryState.applying(.accepted, receiptID: 41)

        XCTAssertEqual(
            accepted,
            .progressing(receiptID: 41, progress: .accepted)
        )
        XCTAssertFalse(accepted.isTerminalFact)
        XCTAssertEqual(accepted.progressMessage, "Saved by NMP; delivering…")

        let acknowledged = MessageDeliveryState.applying(
            .acked(relay: "wss://groups.example"),
            receiptID: 41
        )
        XCTAssertEqual(
            acknowledged,
            .acknowledged(receiptID: 41, relay: "wss://groups.example")
        )
        XCTAssertTrue(acknowledged.isTerminalFact)
        XCTAssertNil(acknowledged.failureMessage)
    }

    func testEveryIntermediateFactRetainsItsTypedEvidence() {
        let statuses: [(WriteStatus, MessageDeliveryProgress)] = [
            (.accepted, .accepted),
            (
                .awaitingCapability(pubkey: "author"),
                .awaitingCapability(pubkey: "author")
            ),
            (.signed(eventId: "event"), .signed(eventID: "event")),
            (.routed(relays: ["wss://one", "wss://two"]), .routed(relays: [
                "wss://one", "wss://two"
            ])),
            (.awaitingRelay(relay: "wss://one"), .awaitingRelay(relay: "wss://one")),
            (.awaitingAuth(relay: "wss://one"), .awaitingAuth(relay: "wss://one")),
            (
                .persistenceBlocked(relay: "wss://one"),
                .persistenceBlocked(relay: "wss://one")
            ),
            (
                .routePersistenceBlocked(relay: "wss://one"),
                .routePersistenceBlocked(relay: "wss://one")
            ),
            (
                .retryEligible(relay: "wss://one", attempt: 2, eligibleAt: 99),
                .retryEligible(relay: "wss://one", attempt: 2, eligibleAt: 99)
            ),
            (
                .handoffAmbiguous(relay: "wss://one", attempt: 3, observedAt: 100),
                .handoffAmbiguous(relay: "wss://one", attempt: 3, observedAt: 100)
            ),
            (
                .sent(relay: "wss://one", attempt: 3, writtenAt: 101),
                .sent(relay: "wss://one", attempt: 3, writtenAt: 101)
            )
        ]

        for (status, progress) in statuses {
            XCTAssertEqual(
                MessageDeliveryState.applying(status, receiptID: 52),
                .progressing(receiptID: 52, progress: progress)
            )
        }
    }

    func testEveryTerminalFailureRetainsItsTypedEvidence() {
        let statuses: [(WriteStatus, MessageDeliveryFailure)] = [
            (.cancelled, .cancelled),
            (
                .rejected(relay: "wss://one", reason: "blocked"),
                .rejected(relay: "wss://one", reason: "blocked")
            ),
            (.gaveUp(relay: "wss://one"), .gaveUp(relay: "wss://one")),
            (
                .outcomeUnknown(relay: "wss://one"),
                .outcomeUnknown(relay: "wss://one")
            ),
            (
                .replaceableConflict(expected: "old", actual: "new"),
                .replaceableConflict(expected: "old", actual: "new")
            ),
            (.failed(reason: "disk full"), .failed(reason: "disk full"))
        ]

        var messages = Set<String>()
        for (status, failure) in statuses {
            let state = MessageDeliveryState.applying(status, receiptID: 63)
            XCTAssertEqual(state, .failed(receiptID: 63, failure: failure))
            XCTAssertTrue(state.isTerminalFact)
            messages.insert(try! XCTUnwrap(state.failureMessage))
        }
        XCTAssertEqual(messages.count, statuses.count)
    }

    func testPerRelayTerminalFactsDoNotEndReceiptBeforeStreamClosure() {
        var convergence = MessageReceiptConvergence()

        let firstRelay = convergence.apply(
            .acked(relay: "wss://one"),
            receiptID: 70
        )
        XCTAssertEqual(
            firstRelay,
            .acknowledged(receiptID: 70, relay: "wss://one")
        )

        let persistenceFact = convergence.apply(
            .persistenceBlocked(relay: "wss://two"),
            receiptID: 70
        )
        XCTAssertFalse(persistenceFact.isTerminalFact)

        _ = convergence.apply(
            .rejected(relay: "wss://two", reason: "blocked"),
            receiptID: 70
        )
        XCTAssertEqual(
            convergence.stateAfterStreamClosed(receiptID: 70),
            .converged(
                receiptID: 70,
                acknowledgedRelays: ["wss://one"],
                failures: [.rejected(relay: "wss://two", reason: "blocked")]
            )
        )
    }

    func testReceiptStoreIsBoundedToItsHostAndGroup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("message-receipts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = DurableReceiptStore(
            rootDirectory: root,
            storeGeneration: "generation-a",
            scope: .message,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )
        let other = DurableReceiptStore(
            rootDirectory: root,
            storeGeneration: "generation-a",
            scope: .message,
            account: "alice",
            host: "wss://two",
            groupID: "room"
        )

        try first.recordReceiptID(9)
        try first.recordReceiptID(2)
        try first.recordReceiptID(9)

        XCTAssertEqual(try first.loadReceiptIDs(), [2, 9])
        XCTAssertEqual(try other.loadReceiptIDs(), [])
        try first.removeReceiptID(2)
        XCTAssertEqual(try first.loadReceiptIDs(), [9])
        try first.removeReceiptID(9)
        XCTAssertEqual(try first.loadReceiptIDs(), [])
    }

    func testReceiptStoreKeepsScopesAndRecoveryIdentitiesSeparate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("durable-receipts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let messages = DurableReceiptStore(
            rootDirectory: root,
            storeGeneration: "generation-a",
            scope: .message,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )
        let reactions = DurableReceiptStore(
            rootDirectory: root,
            storeGeneration: "generation-a",
            scope: .reaction,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )

        try messages.recordReceiptID(11)
        try messages.reserveCorrelation("message-correlation", maximumCount: 4)
        try reactions.recordReceiptID(12)
        try reactions.reserveCorrelation("reaction-correlation", maximumCount: 4)

        XCTAssertEqual(try messages.loadReceiptIDs(), [11])
        XCTAssertEqual(try messages.loadCorrelations(), ["message-correlation"])
        XCTAssertEqual(try messages.recoveryIdentityCount, 2)
        XCTAssertEqual(try reactions.loadReceiptIDs(), [12])
        XCTAssertEqual(try reactions.loadCorrelations(), ["reaction-correlation"])

        try messages.removeCorrelation("message-correlation")
        XCTAssertEqual(try messages.recoveryIdentityCount, 1)
        XCTAssertEqual(try reactions.loadCorrelations(), ["reaction-correlation"])
    }

    func testPruningReplacedStoreGenerationPreservesCurrentAndUnrelatedData() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("message-receipts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DurableReceiptStore(
            rootDirectory: root,
            storeGeneration: "generation-a",
            scope: .message,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )
        let currentStore = DurableReceiptStore(
            rootDirectory: root,
            storeGeneration: "generation-b",
            scope: .message,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )
        try store.recordReceiptID(1)
        try store.reserveCorrelation("recover-me", maximumCount: 4)
        try currentStore.recordReceiptID(2)
        let unrelated = root.appendingPathComponent("presentation.preference")
        try Data("keep".utf8).write(to: unrelated)

        try DurableReceiptStore.pruneGenerations(
            rootDirectory: root,
            keeping: "generation-b"
        )

        XCTAssertEqual(try store.loadReceiptIDs(), [])
        XCTAssertEqual(try store.loadCorrelations(), [])
        XCTAssertEqual(try currentStore.loadReceiptIDs(), [2])
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
    }

    func testReceiptReservationIsAtomicAcrossStoreInstances() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("receipt-capacity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = DurableReceiptStore(
            rootDirectory: root,
            storeGeneration: "generation-a",
            scope: .reaction,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )
        let second = DurableReceiptStore(
            rootDirectory: root,
            storeGeneration: "generation-a",
            scope: .reaction,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )

        try first.reserveCorrelation("one", maximumCount: 2)
        try second.reserveCorrelation("two", maximumCount: 2)
        XCTAssertThrowsError(
            try first.reserveCorrelation("three", maximumCount: 2)
        ) { error in
            XCTAssertEqual(
                error as? ReceiptRecoveryCapacityError,
                .full(maximumCount: 2)
            )
        }
        XCTAssertEqual(try second.loadCorrelations(), ["one", "two"])
    }

    func testReplayUnavailableRetainsTypedReceiptIdentity() {
        let failure = MessageDeliveryFailure.receiptReplayUnavailable(receiptID: 81)

        XCTAssertEqual(
            failure.message,
            "NMP receipt 81 changed while its history was replaying."
        )
    }

    func testNMPReceiptReattachesByIDAndCorrelationAfterRestart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("message-receipt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storePath = directory.appendingPathComponent("nmp.redb").path
        let secretKey = String(repeating: "0", count: 63) + "1"
        let correlation = "message-\(UUID().uuidString)"

        let first = try NMPEngine(config: NMPConfig(storePath: storePath))
        let account = try await first.addAccount(secretKey: secretKey)
        try first.setActiveAccount(account.publicKey)
        let receipt = try await first.publish(
            WriteIntent(
                payload: .unsigned(
                    pubkey: account.publicKey,
                    createdAt: 1,
                    kind: 1,
                    tags: [],
                    content: "receipt lifecycle fixture"
                ),
                durability: .durable,
                routing: .authorOutbox,
                correlation: correlation
            )
        )
        let receiptID = receipt.id
        receipt.status.cancel()
        first.shutdown()

        let reopened = try NMPEngine(config: NMPConfig(storePath: storePath))
        defer { reopened.shutdown() }

        guard case .attached(let byID) = try reopened.reattachReceipt(id: receiptID) else {
            return XCTFail("Expected the durable receipt to reattach by id")
        }
        XCTAssertEqual(byID.id, receiptID)
        byID.status.cancel()

        guard case .attached(let byCorrelation) = try reopened.reattachReceipt(
            correlation: correlation
        ) else {
            return XCTFail("Expected the durable receipt to reattach by correlation")
        }
        XCTAssertEqual(byCorrelation.id, receiptID)
        byCorrelation.status.cancel()
    }

    func testJournaledCorrelationRecoversRealNMPReceiptBeforeIDPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("receipt-crash-window-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storePath = directory.appendingPathComponent("nmp.redb").path
        let secretKey = String(repeating: "0", count: 63) + "1"
        let correlation = "reaction-\(UUID().uuidString.lowercased())"

        let first = try NMPEngine(config: NMPConfig(storePath: storePath))
        let account = try await first.addAccount(secretKey: secretKey)
        try first.setActiveAccount(account.publicKey)
        let journal = DurableReceiptStore(
            rootDirectory: directory,
            storeGeneration: "generation-a",
            scope: .reaction,
            account: account.publicKey,
            host: "wss://one",
            groupID: "room"
        )
        try journal.reserveCorrelation(correlation, maximumCount: 4)
        let receipt = try await first.publish(
            WriteIntent(
                payload: .unsigned(
                    pubkey: account.publicKey,
                    createdAt: 1,
                    kind: 1,
                    tags: [],
                    content: "accepted before receipt-id persistence"
                ),
                durability: .durable,
                routing: .authorOutbox,
                correlation: correlation
            )
        )
        let acceptedID = receipt.id
        receipt.status.cancel()
        first.shutdown()

        let reopenedJournal = DurableReceiptStore(
            rootDirectory: directory,
            storeGeneration: "generation-a",
            scope: .reaction,
            account: account.publicKey,
            host: "wss://one",
            groupID: "room"
        )
        XCTAssertEqual(try reopenedJournal.loadCorrelations(), [correlation])
        XCTAssertEqual(try reopenedJournal.loadReceiptIDs(), [])

        let reopened = try NMPEngine(config: NMPConfig(storePath: storePath))
        defer { reopened.shutdown() }
        guard case .attached(let recovered) = try reopened.reattachReceipt(
            correlation: correlation
        ) else {
            return XCTFail("Expected NMP to recover the accepted receipt by correlation")
        }
        XCTAssertEqual(recovered.id, acceptedID)
        try reopenedJournal.replaceCorrelation(correlation, with: recovered.id)
        XCTAssertEqual(try reopenedJournal.loadCorrelations(), [])
        XCTAssertEqual(try reopenedJournal.loadReceiptIDs(), [acceptedID])
        recovered.status.cancel()
    }
}
