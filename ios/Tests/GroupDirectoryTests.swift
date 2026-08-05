import NMP
import XCTest
@testable import TwentyNinerNext

/// The hierarchy, which is all that is left here.
///
/// The tests that used to live here drove `GroupDirectoryProjection.group`,
/// an app-side kind:39000 parser: which record wins its addressable
/// coordinate, what `d`/`name`/`about` say, and that a kind:9 is not a group.
/// All of that is NMP's answer now (`NMPGroupSnapshot`), so testing it here
/// would only re-assert the library's contract against a fixture this app
/// invented.
///
/// The `parent` row is different. NIP-29 does not define it -- it is a
/// Mosaico convention riding on the metadata record -- so NMP decodes it and
/// declines to interpret it, and deciding what an ambiguous one means stays
/// this app's job.
final class GroupDirectoryTests: XCTestCase {
    func testParentRowNamesTheHierarchyEdge() {
        XCTAssertEqual(
            GroupDirectoryProjection.parentLocalID(
                in: [["d", "general"], ["name", "General"], ["parent", "workspace"]],
                childLocalID: "general"
            ),
            "workspace"
        )
    }

    /// Ambiguity refuses the edge rather than guessing one. A group naming
    /// itself would be a cycle; two rows naming different parents is not a
    /// tree; and two rows naming the same parent is still a record that says
    /// its hierarchy twice, which this app declines to read as agreement.
    func testAmbiguousOrSelfParentOmitsTheEdge() {
        XCTAssertNil(
            GroupDirectoryProjection.parentLocalID(
                in: [["parent", "root-a"], ["parent", "root-b"]],
                childLocalID: "child"
            )
        )
        XCTAssertNil(
            GroupDirectoryProjection.parentLocalID(
                in: [["parent", "child"]],
                childLocalID: "child"
            )
        )
        XCTAssertNil(
            GroupDirectoryProjection.parentLocalID(
                in: [["parent", "root"], ["parent", "root"]],
                childLocalID: "child"
            )
        )
        XCTAssertNil(
            GroupDirectoryProjection.parentLocalID(
                in: [["parent", ""]],
                childLocalID: "child"
            )
        )
    }

    /// A `child` row is not the inverse of a `parent` row. Only the child's
    /// own record may state the edge, so a parent claiming a child creates
    /// nothing.
    func testChildRowIsNotAnEdge() {
        XCTAssertNil(
            GroupDirectoryProjection.parentLocalID(
                in: [["d", "root"], ["child", "child"]],
                childLocalID: "root"
            )
        )
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

    func testTreePreservesNestedHierarchy() {
        let root = group(host: "wss://groups.example.com", localID: "root")
        let child = group(
            host: "wss://groups.example.com",
            localID: "child",
            parent: "root"
        )
        let grandchild = group(
            host: "wss://groups.example.com",
            localID: "grandchild",
            parent: "child"
        )
        let otherRoot = group(host: "wss://groups.example.com", localID: "other")

        let tree = GroupDirectoryProjection.tree(
            in: [grandchild, child, otherRoot, root]
        )

        XCTAssertEqual(tree.map(\.group), [otherRoot, root])
        XCTAssertEqual(tree[1].children.map(\.group), [child])
        XCTAssertEqual(tree[1].children[0].children.map(\.group), [grandchild])
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
            parentLocalID: parent
        )
    }
}
