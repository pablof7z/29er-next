import NMP
import XCTest
@testable import TwentyNinerNext

/// A finite `WriteFact` stream. The app never constructs one in production --
/// NMP hands it a `Receipt`'s own `status` -- so this exists
/// only to feed `WriteReport` the fact orders NMP is contracted to produce.
struct WriteFactSequence: AsyncSequence, Sendable {
    typealias Element = WriteFact

    let facts: [WriteFact]

    init(_ facts: [WriteFact]) {
        self.facts = facts
    }

    struct Iterator: AsyncIteratorProtocol {
        var remaining: ArraySlice<WriteFact>

        mutating func next() async throws -> WriteFact? {
            guard let first = remaining.first else { return nil }
            remaining = remaining.dropFirst()
            return first
        }
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(remaining: facts[...])
    }
}

final class WriteReportTests: XCTestCase {
    private func failure(_ facts: [WriteFact]) async -> String? {
        await WriteReport.failure(draining: WriteFactSequence(facts), subject: "message")
    }

    /// The reason the old per-frame mapping had to go: `GaveUp` is terminal
    /// at ONE relay and nowhere else. A message that reached one relay is a
    /// delivered message, and telling somebody otherwise was a lie the old
    /// switch could not avoid because it never saw the other lanes.
    func testOneRelayPublishedIsDeliveredEvenWhenAnotherGaveUp() async {
        let result = await failure([
            .destinations(relays: ["wss://a.example", "wss://b.example"], complete: true, awaitingAuthorRoutes: []),
            .signing(.signed(eventId: "abc")),
            .relay(relay: "wss://a.example", state: .published),
            .relay(relay: "wss://b.example", state: .gaveUp),
            .outcome(.settled)
        ])
        XCTAssertNil(result)
    }

    func testSettledWithNothingPublishedNamesTheRejection() async {
        let result = await failure([
            .destinations(relays: ["wss://a.example", "wss://b.example"], complete: true, awaitingAuthorRoutes: []),
            .relay(relay: "wss://b.example", state: .rejected(reason: "blocked: not a member")),
            .relay(relay: "wss://a.example", state: .gaveUp),
            .outcome(.settled)
        ])
        XCTAssertEqual(
            result,
            "wss://b.example rejected the message: blocked: not a member"
        )
    }

    /// The fresh-install case. Knowledge is exhausted and it named zero
    /// relays, so the write terminates immediately instead of sitting in
    /// "sending" for ever.
    func testNoDestinationSaysThereIsNowhereToSend() async {
        let result = await failure([
            .destinations(relays: [], complete: true, awaitingAuthorRoutes: []),
            .outcome(.noDestination)
        ])
        XCTAssertEqual(
            result,
            """
            There is nowhere to send this message: no relay is configured for it. \
            Add one under Favorite Relays.
            """
        )
    }

    /// A route that has not resolved yet parks, and no clock ends it. An
    /// unsettled write reports nothing at all -- the app has nothing to say.
    ///
    /// `awaitingAuthorRoutes` names whose routes the resolution is still
    /// waiting on. It is a repair list for a write that is still going, so
    /// naming somebody there must not become a verdict either.
    func testUnresolvedRouteAndAbsentSignerReportNothing() async {
        let author = String(repeating: "a", count: 64)
        let result = await failure([
            .signing(.awaitingSigner(pubkey: author)),
            .destinations(relays: [], complete: false, awaitingAuthorRoutes: [author])
        ])
        XCTAssertNil(result)
    }

    /// The state `awaitingSigner` must never be confused with: a signer that
    /// HAS the request and has not answered yet is every healthy write between
    /// acceptance and signature. Reporting on it would put a verdict on a
    /// signature that is simply still being produced.
    func testSignatureInFlightIsNotAFailure() async {
        let author = String(repeating: "b", count: 64)
        let stillSigning = await failure([.signing(.inFlight(pubkey: author))])
        XCTAssertNil(stillSigning)

        let delivered = await failure([
            .signing(.inFlight(pubkey: author)),
            .signing(.signed(eventId: "abc")),
            .destinations(
                relays: ["wss://a.example"], complete: true, awaitingAuthorRoutes: []
            ),
            .relay(relay: "wss://a.example", state: .published),
            .outcome(.settled)
        ])
        XCTAssertNil(delivered)
    }

    /// A later write for the same replaceable coordinate winning is the
    /// intended outcome of editing twice quickly, not a failure.
    func testSupersededIsNotAFailure() async {
        let result = await failure([.outcome(.notSent(.superseded))])
        XCTAssertNil(result)
    }

    func testCancelledSaysTheWriteWasCancelled() async {
        let result = await failure([.outcome(.notSent(.cancelled))])
        XCTAssertEqual(result, "The message was not sent -- the write was cancelled.")
    }

    /// `AuthDenialSource` exists precisely so this app's own decision not to
    /// authenticate is never shown to somebody as a relay refusing them.
    func testAuthDenialBySourceNeverBlamesTheRelayForAPolicyChoice() async {
        let policy = await failure([
            .relay(
                relay: "wss://a.example",
                state: .authFailed(
                    pubkey: String(repeating: "a", count: 64),
                    source: .policy,
                    reason: "auth not permitted"
                )
            ),
            .outcome(.settled)
        ])
        XCTAssertEqual(
            policy,
            "This app did not authenticate to wss://a.example, so the message was not sent."
        )

        let relay = await failure([
            .relay(
                relay: "wss://a.example",
                state: .authFailed(
                    pubkey: String(repeating: "a", count: 64),
                    source: .relay,
                    reason: "restricted"
                )
            ),
            .outcome(.settled)
        ])
        XCTAssertEqual(relay, "wss://a.example refused to authenticate you: restricted")
    }

    func testSignerRefusalIsAttributedToTheSigner() async {
        let result = await failure([
            .signing(.refused(reason: "user declined")),
            .outcome(.settled)
        ])
        XCTAssertEqual(result, "Your signer refused the message: user declined")
    }

    /// A stalled local write is a wait, not a verdict. It only becomes worth
    /// saying once the write settled and nothing was published.
    func testPersistenceStallOnlySurfacesWhenNothingPublished() async {
        let stalled = await failure([
            .relay(
                relay: "wss://a.example",
                state: .waiting(.persistenceStalled(detail: "disk full"))
            ),
            .outcome(.settled)
        ])
        XCTAssertEqual(
            stalled,
            "This device could not record the message for wss://a.example: disk full"
        )

        let published = await failure([
            .relay(
                relay: "wss://a.example",
                state: .waiting(.persistenceStalled(detail: "disk full"))
            ),
            .relay(relay: "wss://b.example", state: .published),
            .outcome(.settled)
        ])
        XCTAssertNil(published)
    }

    /// Backing off is a fact about a lane, never a deadline, so it is not
    /// something to interrupt anyone with.
    func testBackingOffIsNotReported() async {
        let result = await failure([
            .relay(
                relay: "wss://a.example",
                state: .waiting(.backingOff(
                    attempt: 3,
                    eligibleAt: 1_700_000_000,
                    cause: .relayRateLimited,
                    detail: "slow down"
                ))
            )
        ])
        XCTAssertNil(result)
    }
}
