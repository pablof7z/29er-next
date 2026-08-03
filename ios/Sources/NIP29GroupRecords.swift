import NMP

/// PLACEHOLDER: the app's only reader of NIP-29's relay-signed group records
/// -- kind:39000 metadata, kind:39001 admin list, kind:39002 member list.
///
/// NMP does not expose a roster reader yet; that design is in flight. Until
/// it lands, these three kinds are read off raw `Row.tags` here and nowhere
/// else, so the eventual adoption is a deletion of this one file rather than
/// a hunt through the view layer. Do not grow a second app-owned roster model
/// beside it -- a parallel abstraction is exactly what would make the
/// upstream adoption harder.
enum NIP29GroupRecords {
    /// The single authoritative record per addressable coordinate.
    ///
    /// 39000/39001/39002 are ADDRESSABLE: `(kind, pubkey, d)` names one
    /// record, and a newer publication replaces the older one. Folding every
    /// delivered row of a kind together instead -- which is what this app did
    /// for admins and for members -- makes a demotion invisible, because the
    /// removed `p` is still present on the superseded row for as long as both
    /// are in the snapshot. A union can only ever grow; latest-wins per
    /// coordinate is the only reading that can also shrink.
    ///
    /// This also covers the republish case, where the relay's newer record
    /// arrives as `Removed(old id)` + `Added(new id)`: `NMPQuery` folds every
    /// delta of a frame before delivering, so the app only ever sees complete
    /// snapshots, and picking the latest per coordinate from one of those
    /// never renders a momentarily empty list.
    static func authoritative(kind: UInt16, in rows: [Row]) -> [Row] {
        var latest: [Coordinate: Row] = [:]
        for row in rows where row.kind == kind {
            guard let groupID = groupID(of: row) else { continue }
            let coordinate = Coordinate(kind: row.kind, pubkey: row.pubkey, groupID: groupID)
            guard let held = latest[coordinate] else {
                latest[coordinate] = row
                continue
            }
            if supersedes(row, held) { latest[coordinate] = row }
        }
        return latest.values.sorted { $0.id < $1.id }
    }

    /// The `d` value a relay-signed group record keys itself by.
    static func groupID(of row: Row) -> String? {
        firstValue("d", in: row.tags)
    }

    /// The `p` subjects a list record names, in delivery order, deduplicated.
    static func subjects(of row: Row) -> [String] {
        var seen = Set<String>()
        return row.tags.compactMap { tag in
            guard tag.first == "p", tag.count > 1, !tag[1].isEmpty,
                  seen.insert(tag[1]).inserted else { return nil }
            return tag[1]
        }
    }

    /// The first value of the first `name` tag that carries one.
    static func firstValue(_ name: String, in tags: [[String]]) -> String? {
        tags.first { $0.first == name && $0.count > 1 }?[1]
    }

    /// The same, rejecting an empty value.
    static func nonEmptyValue(_ name: String, in tags: [[String]]) -> String? {
        firstValue(name, in: tags).flatMap { $0.isEmpty ? nil : $0 }
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
}
