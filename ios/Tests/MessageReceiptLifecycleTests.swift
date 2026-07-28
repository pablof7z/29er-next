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
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "message-receipts-\(UUID().uuidString)")
        )
        let first = MessageReceiptStore(
            defaults: defaults,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )
        let other = MessageReceiptStore(
            defaults: defaults,
            account: "alice",
            host: "wss://two",
            groupID: "room"
        )

        first.record(9)
        first.record(2)
        first.record(9)

        XCTAssertEqual(first.load(), [2, 9])
        XCTAssertEqual(other.load(), [])
        first.remove(2)
        XCTAssertEqual(first.load(), [9])
        first.remove(9)
        XCTAssertEqual(first.load(), [])
    }

    func testClearingAReplacedNMPStoreRemovesOnlyReceiptCorrelations() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "message-receipts-\(UUID().uuidString)")
        )
        let store = MessageReceiptStore(
            defaults: defaults,
            account: "alice",
            host: "wss://one",
            groupID: "room"
        )
        store.record(1)
        defaults.set("keep", forKey: "presentation.preference")

        MessageReceiptStore.clearAll(defaults: defaults)

        XCTAssertEqual(store.load(), [])
        XCTAssertEqual(defaults.string(forKey: "presentation.preference"), "keep")
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
}
