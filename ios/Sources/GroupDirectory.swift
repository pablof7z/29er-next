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
/// This is the app's LAST hand-rolled reader of a relay-signed NIP-29 record,
/// and the only remaining place kind:39000 is parsed out of `tags: [[String]]`.
/// The room screen no longer parses anything -- it reads typed
/// `NMPListedSubject`s off `NMPGroupSnapshot` (`roomRecordsObservation`).
///
/// Why this one could not follow: NMP's records door is
/// `NMPRelayScope.observeRecords(engine:matching:records:)`, and every
/// `NMPGroupPredicate` leaf names a group by a membership fact
/// (`memberListIncludes`, `adminListIncludes`) or by id (`anyOf`). This
/// sidebar is a BROWSE -- "public rooms from this relay" -- so it asks no
/// membership question and has no ids until the answer arrives. Closing it
/// needs either a predicate leaf meaning "every group this host advertises",
/// or a public projection from a delivered `Row` to `NMPGroupMetadata`;
/// filed as `pablof7z/nmp#1252`. Delete this whole parse when it lands.
enum GroupDirectoryProjection {
    /// The host's groups, from the authoritative kind:39000 record per group.
    ///
    /// 39000 is ADDRESSABLE: `(kind, pubkey, d)` names one record and a newer
    /// publication replaces the older one. Mapping every delivered row
    /// instead would let a superseded record's fields survive its
    /// replacement.
    static func groups(from rows: [Row], hostRelay: String) -> [GroupSummary] {
        authoritative(kind: RoomKind.groupMetadata, in: rows)
            .compactMap { row in
                group(hostRelay: hostRelay, kind: row.kind, tags: row.tags)
            }
            .sorted(by: groupNameFirst)
    }

    static func group(
        hostRelay: String,
        kind: UInt16,
        tags: [[String]]
    ) -> GroupSummary? {
        guard kind == RoomKind.groupMetadata,
              let localID = firstTag("d", in: tags),
              !localID.isEmpty else {
            return nil
        }

        let name = firstTag("name", in: tags).flatMap { $0.isEmpty ? nil : $0 } ?? localID
        let about = firstTag("about", in: tags).flatMap { $0.isEmpty ? nil : $0 }
        let parentLocalID = authoritativeParent(in: tags, childLocalID: localID)

        return GroupSummary(
            id: GroupCoordinate(hostRelay: hostRelay, localID: localID),
            name: name,
            about: about,
            parentLocalID: parentLocalID
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

    private static func authoritativeParent(
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

    /// The single authoritative record per addressable coordinate.
    private static func authoritative(kind: UInt16, in rows: [Row]) -> [Row] {
        var latest: [Coordinate: Row] = [:]
        for row in rows where row.kind == kind {
            guard let groupID = firstTag("d", in: row.tags), !groupID.isEmpty else { continue }
            let coordinate = Coordinate(kind: row.kind, pubkey: row.pubkey, groupID: groupID)
            guard let held = latest[coordinate] else {
                latest[coordinate] = row
                continue
            }
            if supersedes(row, held) { latest[coordinate] = row }
        }
        return latest.values.sorted { $0.id < $1.id }
    }

    private struct Coordinate: Hashable {
        let kind: UInt16
        let pubkey: String
        let groupID: String
    }

    private static func supersedes(_ candidate: Row, _ held: Row) -> Bool {
        if candidate.createdAt != held.createdAt { return candidate.createdAt > held.createdAt }
        return candidate.id > held.id
    }

    private static func firstTag(_ name: String, in tags: [[String]]) -> String? {
        tags.first { $0.first == name && $0.count > 1 }?[1]
    }

    private static func groupNameFirst(_ lhs: GroupSummary, _ rhs: GroupSummary) -> Bool {
        let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        if lhs.localID != rhs.localID { return lhs.localID < rhs.localID }
        return lhs.hostRelay < rhs.hostRelay
    }
}
