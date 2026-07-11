import XCTest
@testable import TwentyNinerNext

final class GroupDirectoryTests: XCTestCase {
    func testProjectionUsesRelayMetadataAndCompositeIdentity() throws {
        let group = try XCTUnwrap(
            GroupDirectoryProjection.group(
                hostRelay: "wss://groups.example.com",
                kind: 39_000,
                tags: [
                    ["d", "general"],
                    ["name", "General"],
                    ["about", "The main room"],
                    ["picture", "https://example.com/room.png"],
                    ["parent", "workspace"],
                    ["public"],
                    ["open"],
                ]
            )
        )

        XCTAssertEqual(
            group.id,
            GroupCoordinate(hostRelay: "wss://groups.example.com", localID: "general")
        )
        XCTAssertEqual(group.name, "General")
        XCTAssertEqual(group.about, "The main room")
        XCTAssertEqual(group.pictureURL?.absoluteString, "https://example.com/room.png")
        XCTAssertEqual(group.parentLocalID, "workspace")
        XCTAssertTrue(group.isPublic)
        XCTAssertTrue(group.isOpen)
    }

    func testProjectionFallsBackToLocalIdentifier() throws {
        let group = try XCTUnwrap(
            GroupDirectoryProjection.group(
                hostRelay: "wss://groups.example.com",
                kind: 39_000,
                tags: [["d", "ops"]]
            )
        )

        XCTAssertEqual(group.name, "ops")
        XCTAssertEqual(group.initials, "O")
    }

    func testNonMetadataEventIsNotAGroup() {
        XCTAssertNil(
            GroupDirectoryProjection.group(
                hostRelay: "wss://groups.example.com",
                kind: 9,
                tags: [["d", "general"]]
            )
        )
    }

    func testConflictingOrSelfParentTagsOmitHierarchyEdge() throws {
        let conflicting = try XCTUnwrap(
            GroupDirectoryProjection.group(
                hostRelay: "wss://groups.example.com",
                kind: 39_000,
                tags: [
                    ["d", "child"],
                    ["parent", "root-a"],
                    ["parent", "root-b"],
                ]
            )
        )
        let selfLinked = try XCTUnwrap(
            GroupDirectoryProjection.group(
                hostRelay: "wss://groups.example.com",
                kind: 39_000,
                tags: [["d", "child"], ["parent", "child"]]
            )
        )
        let duplicated = try XCTUnwrap(
            GroupDirectoryProjection.group(
                hostRelay: "wss://groups.example.com",
                kind: 39_000,
                tags: [
                    ["d", "child"],
                    ["parent", "root"],
                    ["parent", "root"],
                ]
            )
        )

        XCTAssertNil(conflicting.parentLocalID)
        XCTAssertNil(selfLinked.parentLocalID)
        XCTAssertNil(duplicated.parentLocalID)
    }

    func testHierarchyLinksKnownParentWithinSameHost() {
        let rootA = group(host: "wss://a.example.com", localID: "root")
        let childA = group(host: "wss://a.example.com", localID: "child", parent: "root")
        let orphanA = group(host: "wss://a.example.com", localID: "orphan", parent: "missing")
        let rootB = group(host: "wss://b.example.com", localID: "root")
        let childB = group(host: "wss://b.example.com", localID: "child", parent: "root")
        let groups = [rootA, childA, orphanA, rootB, childB]

        XCTAssertEqual(
            Set(GroupDirectoryProjection.roots(in: groups).map(\.id)),
            Set([rootA.id, orphanA.id, rootB.id])
        )
        XCTAssertEqual(GroupDirectoryProjection.directChildren(of: rootA, in: groups), [childA])
        XCTAssertEqual(GroupDirectoryProjection.directChildren(of: rootB, in: groups), [childB])
    }

    func testParentChildHintDoesNotCreateIndependentEdge() throws {
        let parent = try XCTUnwrap(
            GroupDirectoryProjection.group(
                hostRelay: "wss://groups.example.com",
                kind: 39_000,
                tags: [["d", "root"], ["child", "child"]]
            )
        )
        let child = group(host: "wss://groups.example.com", localID: "child")
        let groups = [parent, child]

        XCTAssertEqual(Set(GroupDirectoryProjection.roots(in: groups).map(\.id)), Set([parent.id, child.id]))
        XCTAssertTrue(GroupDirectoryProjection.directChildren(of: parent, in: groups).isEmpty)
    }

    private func group(
        host: String,
        localID: String,
        parent: String? = nil
    ) -> GroupSummary {
        GroupSummary(
            id: GroupCoordinate(hostRelay: host, localID: localID),
            name: localID,
            about: nil,
            pictureURL: nil,
            isPublic: true,
            isOpen: false,
            parentLocalID: parent
        )
    }
}
