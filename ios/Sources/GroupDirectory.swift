import Foundation
import NMP

struct GroupCoordinate: Hashable, Sendable {
    let hostRelay: String
    let localID: String
}

struct GroupSummary: Identifiable, Hashable, Sendable {
    let id: GroupCoordinate
    let name: String
    let about: String?
    let parentLocalID: String?

    var hostRelay: String { id.hostRelay }
    var localID: String { id.localID }

    var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let value = words.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "#" : value.uppercased()
    }
}

struct GroupTreeNode: Identifiable, Hashable, Sendable {
    let group: GroupSummary
    let children: [GroupTreeNode]

    var id: GroupCoordinate { group.id }
}

/// The channel sidebar's view of a relay's public rooms.
///
/// The app no longer reads a relay-signed NIP-29 record at all. This used to
/// be the last place kind:39000 was parsed out of `tags: [[String]]`, because
/// every `NMPGroupPredicate` leaf named a group by a membership fact or by id
/// and a BROWSE asks neither -- it has no ids until the answer arrives. NMP
/// #1252 added `NMPGroupPredicate.all`, so the browse is now a predicate like
/// any other and the parse is deleted with it: which record wins its
/// addressable coordinate, and what its NIP-29 fields say, are both NMP's
/// answers now.
///
/// What is left here is the hierarchy, which is NOT NIP-29: the `parent` row is
/// a Mosaico convention carried on the metadata record, so it is read off
/// `NMPGroupMetadata.tags` -- the rows NMP decoded and did not claim.
enum GroupDirectoryProjection {
    /// The host's groups, one per relay-signed record NMP resolved.
    ///
    /// 39000 is ADDRESSABLE, and picking the winner per `(kind, pubkey, d)` is
    /// what this used to do by hand. `NMPGroupSnapshot.metadata` is already
    /// that winner -- "latest `created_at` wins, never a field-wise merge" --
    /// so there is nothing left to decide.
    static func groups(from snapshots: [NMPGroupSnapshot], hostRelay: String) -> [GroupSummary] {
        snapshots
            .compactMap { summary(for: $0, hostRelay: hostRelay) }
            .sorted(by: groupNameFirst)
    }

    static func summary(
        for snapshot: NMPGroupSnapshot,
        hostRelay: String
    ) -> GroupSummary? {
        guard !snapshot.id.isEmpty else { return nil }
        let metadata = snapshot.metadata

        return GroupSummary(
            id: GroupCoordinate(hostRelay: hostRelay, localID: snapshot.id),
            name: metadata?.name.flatMap { $0.isEmpty ? nil : $0 } ?? snapshot.id,
            about: metadata?.about.flatMap { $0.isEmpty ? nil : $0 },
            parentLocalID: metadata.flatMap {
                parentLocalID(in: $0.tags, childLocalID: snapshot.id)
            }
        )
    }

    static func roots(in groups: [GroupSummary]) -> [GroupSummary] {
        let knownCoordinates = Set(groups.map(\.id))
        return groups.filter { group in
            guard let parentLocalID = group.parentLocalID else { return true }
            let parent = GroupCoordinate(hostRelay: group.hostRelay, localID: parentLocalID)
            return !knownCoordinates.contains(parent)
        }
        .sorted(by: groupNameFirst)
    }

    static func directChildren(
        of parent: GroupSummary,
        in groups: [GroupSummary]
    ) -> [GroupSummary] {
        groups.filter { group in
            group.hostRelay == parent.hostRelay && group.parentLocalID == parent.localID
        }
        .sorted(by: groupNameFirst)
    }

    static func tree(in groups: [GroupSummary]) -> [GroupTreeNode] {
        roots(in: groups).map { treeNode(for: $0, in: groups) }
    }

    private static func treeNode(
        for group: GroupSummary,
        in groups: [GroupSummary]
    ) -> GroupTreeNode {
        GroupTreeNode(
            group: group,
            children: directChildren(of: group, in: groups).map {
                treeNode(for: $0, in: groups)
            }
        )
    }

    /// The hierarchy edge, which NIP-29 does not define. Mosaico carries it on
    /// the metadata record as a `parent` row, so it is read off the rows NMP
    /// decoded and did not claim -- never off a raw event. Ambiguity is
    /// resolved by refusing the edge: more than one `parent` row, or a group
    /// naming itself, is not a tree.
    static func parentLocalID(
        in tags: [[String]],
        childLocalID: String
    ) -> String? {
        let parents = tags.compactMap { tag -> String? in
            guard tag.first == "parent", tag.count > 1, !tag[1].isEmpty else { return nil }
            return tag[1]
        }
        guard parents.count == 1, parents[0] != childLocalID else { return nil }
        return parents[0]
    }

    private static func groupNameFirst(_ lhs: GroupSummary, _ rhs: GroupSummary) -> Bool {
        let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        if lhs.localID != rhs.localID { return lhs.localID < rhs.localID }
        return lhs.hostRelay < rhs.hostRelay
    }
}
