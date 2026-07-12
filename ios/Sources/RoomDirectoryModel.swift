import Foundation
import NMP
import Observation

/// Persists the newest message timestamp each room was read up to. Unread is
/// defined relative to this baseline: the app owns read state as product state,
/// NMP owns the messages. Keyed by local group id (one group relay per app).
struct DirectoryReadStore {
    private let defaults: UserDefaults
    private let key = "directory.lastRead.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [String: UInt64] {
        guard let stored = defaults.dictionary(forKey: key) as? [String: NSNumber] else { return [:] }
        return stored.mapValues { $0.uint64Value }
    }

    func save(_ baselines: [String: UInt64]) {
        defaults.set(baselines.mapValues { NSNumber(value: $0) }, forKey: key)
    }
}

/// Directory-wide projection of the most recent `kind:9` message per room and
/// the unread count since each room's read baseline. One live query buckets all
/// rooms by their `h` tag, so newly discovered rooms need no re-subscription.
@MainActor
@Observable
final class RoomDirectoryModel {
    struct Entry: Hashable, Sendable {
        var latest: RoomMessage?
        var unread: Int
    }

    private(set) var entries: [String: Entry] = [:]

    private let engine: NMPEngine
    private let store: DirectoryReadStore
    private var baselines: [String: UInt64]
    private var latestByGroup: [String: RoomMessage] = [:]
    private var timesByGroup: [String: [UInt64]] = [:]

    init(engine: NMPEngine, store: DirectoryReadStore = DirectoryReadStore()) {
        self.engine = engine
        self.store = store
        self.baselines = store.load()
    }

    func observe() async {
        do {
            let query = try await openNMPQuery(
                engine: engine,
                filter: NMPFilter(kinds: [9], limit: 500)
            )
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                ingest(rows: batch.rows)
            }
        } catch {
            // Previews are enrichment; the room list still renders without them.
            return
        }
    }

    /// Clear a room's unread badge by advancing its baseline to the newest
    /// message currently known for it.
    func markRead(_ group: GroupSummary) {
        let key = group.localID
        baselines[key] = latestByGroup[key]?.createdAt ?? UInt64(Date().timeIntervalSince1970)
        store.save(baselines)
        recompute()
    }

    private func ingest(rows: [Row]) {
        var latest: [String: RoomMessage] = [:]
        var times: [String: [UInt64]] = [:]

        for row in rows where row.kind == 9 {
            guard let group = groupID(from: row.tags),
                  let message = NIP29ViewProjection.message(
                      eventID: row.id,
                      pubkey: row.pubkey,
                      createdAt: row.createdAt,
                      kind: row.kind,
                      content: row.content
                  ) else { continue }

            times[group, default: []].append(message.createdAt)
            if let current = latest[group] {
                if message.createdAt > current.createdAt ||
                    (message.createdAt == current.createdAt && message.id > current.id) {
                    latest[group] = message
                }
            } else {
                latest[group] = message
            }
        }

        // First time a room is seen, baseline to the current wall clock so the
        // whole existing backlog (including late-arriving history) reads as read,
        // and only messages that land afterwards count as unread.
        let now = UInt64(Date().timeIntervalSince1970)
        var seededNewBaseline = false
        for group in latest.keys where baselines[group] == nil {
            baselines[group] = now
            seededNewBaseline = true
        }
        if seededNewBaseline { store.save(baselines) }

        latestByGroup = latest
        timesByGroup = times
        recompute()
    }

    private func recompute() {
        var result: [String: Entry] = [:]
        for (group, message) in latestByGroup {
            let baseline = baselines[group] ?? message.createdAt
            let unread = (timesByGroup[group] ?? []).reduce(0) { $0 + ($1 > baseline ? 1 : 0) }
            result[group] = Entry(latest: message, unread: unread)
        }
        entries = result
    }

    private func groupID(from tags: [[String]]) -> String? {
        tags.first { $0.first == "h" && $0.count > 1 }?[1].nonEmpty
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
