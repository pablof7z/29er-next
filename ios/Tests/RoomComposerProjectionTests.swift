import XCTest
@testable import TwentyNinerNext

final class RoomComposerProjectionTests: XCTestCase {
    private func activity(pubkey: String, slug: String, busy: Bool = false) -> AgentActivity {
        AgentActivity(
            id: "activity-\(pubkey)",
            eventID: "event-\(pubkey)",
            author: pubkey,
            createdAt: 1,
            title: "",
            activity: "Available",
            isBusy: busy,
            host: "laptop",
            slug: slug
        )
    }

    func testPickerIncludesCompleteRosterAndLiveStatusOnlyPeople() {
        let current = RoomPerson(
            member: nil,
            activity: activity(pubkey: "current", slug: "me"),
            pubkey: "current"
        )
        let zeta = RoomPerson(
            member: nil,
            activity: activity(pubkey: "zeta", slug: "zeta"),
            pubkey: "zeta"
        )
        let alpha = RoomPerson(
            member: nil,
            activity: activity(pubkey: "alpha", slug: "alpha"),
            pubkey: "alpha"
        )
        let inactive = RoomPerson(
            member: RoomMember(id: "human", pubkey: "human"),
            activity: nil,
            pubkey: "human"
        )
        let people = RoomPeople(members: [inactive], activeHere: [zeta, current, alpha])

        let recipients = RoomComposerProjection.recipients(
            from: people,
            profiles: ProfileBook(),
            excluding: "current"
        )

        XCTAssertEqual(recipients.map(\.pubkey), ["alpha", "human", "zeta"])
        XCTAssertEqual(recipients.map(\.mentionLabel), ["@alpha", "@human", "@zeta"])
    }

    func testPickerExcludesBackendIdentities() {
        let backend = RoomPerson(
            member: nil,
            activity: activity(pubkey: "backend", slug: "backend"),
            pubkey: "backend"
        )
        let agent = RoomPerson(
            member: nil,
            activity: activity(pubkey: "agent", slug: "agent1"),
            pubkey: "agent"
        )
        let backendProfile = RoomProfile(
            pubkey: "backend",
            displayName: "tenex-edge",
            pictureURL: nil,
            isBackend: true,
            host: "laptop",
            workspace: nil,
            agents: []
        )

        let recipients = RoomComposerProjection.recipients(
            from: RoomPeople(members: [], activeHere: [backend, agent]),
            profiles: ProfileBook([backendProfile.pubkey: backendProfile]),
            excluding: nil
        )

        XCTAssertEqual(recipients.map(\.pubkey), ["agent"])
    }

    func testReplyTargetsTheTappedAuthorAndKeepsLocalPreview() {
        let author = RoomPerson(
            member: nil,
            activity: activity(pubkey: "agent", slug: "agent1"),
            pubkey: "agent"
        )
        let message = RoomMessage(id: "message", author: "agent", createdAt: 1, content: "Earlier")

        let reply = RoomComposerProjection.reply(
            to: message,
            people: RoomPeople(members: [], activeHere: [author]),
            profiles: ProfileBook()
        )

        XCTAssertEqual(reply.eventID, "message")
        XCTAssertEqual(reply.author.pubkey, "agent")
        XCTAssertEqual(reply.author.mentionLabel, "@agent1")
        XCTAssertEqual(reply.preview, "Earlier")
    }

}
