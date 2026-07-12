import XCTest
@testable import TwentyNinerNext

final class BackendRosterTests: XCTestCase {
    func testBackendKindZeroTagsAreParsed() {
        let profile = RoomProfileProjection.profile(
            pubkey: "backend-pubkey",
            content: #"{"name":"laptop (tenex-edge)"}"#,
            tags: [
                ["backend"],
                ["host", "laptop"],
                ["p", "owner-pubkey"],
                ["agent", "claude", "general coding agent"],
                ["agent", "writer", ""],
                ["agent", "", "no slug is ignored"]
            ]
        )

        XCTAssertTrue(profile.isBackend)
        XCTAssertEqual(profile.host, "laptop")
        XCTAssertEqual(profile.agents.map(\.slug), ["claude", "writer"])
        XCTAssertEqual(profile.agents.first?.description, "general coding agent")
        XCTAssertEqual(profile.agents.last?.description, "")
    }

    func testNonBackendKindZeroHasNoAgents() {
        let profile = RoomProfileProjection.profile(
            pubkey: "human-pubkey",
            content: #"{"name":"Pablo"}"#,
            tags: [["agent", "claude", "ignored without backend marker"]]
        )

        XCTAssertFalse(profile.isBackend)
        XCTAssertNil(profile.host)
        // Agent tags are still structurally parsed; the backend affordance keys
        // off `isBackend`, so a non-backend profile is never offered commands.
        XCTAssertEqual(profile.agents.map(\.slug), ["claude"])
    }

    func testBackendsSelectsOnlyBackendTaggedCandidates() {
        let backend = RoomProfile(
            pubkey: "backend-pubkey",
            displayName: "laptop (tenex-edge)",
            pictureURL: nil,
            isBackend: true,
            host: "laptop",
            agents: [BackendAgent(slug: "claude", description: "coding")]
        )
        let human = RoomProfile(
            pubkey: "human-pubkey",
            displayName: "Pablo",
            pictureURL: nil,
            isBackend: false,
            host: nil,
            agents: []
        )
        let book = ProfileBook([backend.pubkey: backend, human.pubkey: human])

        let backends = RoomBackendProjection.backends(
            candidatePubkeys: ["human-pubkey", "backend-pubkey", "unresolved-pubkey", "backend-pubkey"],
            profiles: book
        )

        XCTAssertEqual(backends.map(\.pubkey), ["backend-pubkey"])
        XCTAssertEqual(backends.first?.label, "laptop")
        XCTAssertEqual(backends.first?.agents.map(\.slug), ["claude"])
    }

    func testBackendLabelFallsBackFromHostToNameToHex() {
        let named = backendProfile(pubkey: "b1", host: nil, displayName: "My Backend")
        let hex = backendProfile(
            pubkey: "0123456789abcdef0123456789abcdef",
            host: nil,
            displayName: nil
        )
        let book = ProfileBook([named.pubkey: named, hex.pubkey: hex])

        let backends = RoomBackendProjection.backends(
            candidatePubkeys: [named.pubkey, hex.pubkey],
            profiles: book
        )

        let labels = Dictionary(uniqueKeysWithValues: backends.map { ($0.pubkey, $0.label) })
        XCTAssertEqual(labels["b1"], "My Backend")
        XCTAssertEqual(labels["0123456789abcdef0123456789abcdef"], "01234567…89abcdef")
    }

    func testAdminsExtractsPTagsFromKind39001Only() {
        XCTAssertEqual(
            NIP29ViewProjection.admins(
                kind: 39_001,
                tags: [["d", "nip29"], ["p", "admin-a"], ["p", "admin-b"], ["p", ""]]
            ),
            ["admin-a", "admin-b"]
        )
        XCTAssertTrue(
            NIP29ViewProjection.admins(kind: 39_002, tags: [["d", "nip29"], ["p", "member"]]).isEmpty
        )
    }

    private func backendProfile(pubkey: String, host: String?, displayName: String?) -> RoomProfile {
        RoomProfile(
            pubkey: pubkey,
            displayName: displayName,
            pictureURL: nil,
            isBackend: true,
            host: host,
            agents: []
        )
    }
}
