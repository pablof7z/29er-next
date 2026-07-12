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

enum GroupDirectoryProjection {
    static func groups(from rows: [Row], hostRelay: String) -> [GroupSummary] {
        rows.compactMap { row in
            group(hostRelay: hostRelay, kind: row.kind, tags: row.tags)
        }
        .sorted(by: groupNameFirst)
    }

    static func group(
        hostRelay: String,
        kind: UInt16,
        tags: [[String]]
    ) -> GroupSummary? {
        guard kind == 39_000,
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
