import Foundation
import NMP
import Observation

/// Persists the newest message timestamp each room was read up to. Unread is
/// defined relative to this baseline: the app owns read state as product state,
/// NMP owns the messages. Stores are namespaced by selected host, then keyed by
/// local group id so identical ids at different hosts never share read state.
struct DirectoryReadStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, hostRelay: String) {
        self.defaults = defaults
        key = "directory.lastRead.v2.\(hostRelay)"
    }

    func load() -> [String: UInt64] {
        guard let stored = defaults.dictionary(forKey: key) as? [String: NSNumber] else { return [:] }
        return stored.mapValues { $0.uint64Value }
    }

    func save(_ baselines: [String: UInt64]) {
        defaults.set(baselines.mapValues { NSNumber(value: $0) }, forKey: key)
    }
}

/// Selected-host projection of the most recent `kind:9` message per room and
/// the unread count since each room's read baseline. Its pinned handle is
/// replaced with the selected-host task, while account-scoped demand remains.
@MainActor
@Observable
final class RoomDirectoryModel {
    private(set) var entries: [String: RoomDirectoryEntry] = [:]
    private(set) var observationError: String?

    private let engine: NMPEngine
    private let hostRelay: String
    private let store: DirectoryReadStore
    private let queryOpening: NMPQueryOpening
    private var baselines: [String: UInt64]
    private var latestByGroup: [String: RoomMessage] = [:]
    private var timesByGroup: [String: [UInt64]] = [:]

    init(
        engine: NMPEngine,
        hostRelay: String,
        store: DirectoryReadStore? = nil,
        queryOpening: NMPQueryOpening = .live
    ) {
        self.engine = engine
        self.hostRelay = hostRelay
        let store = store ?? DirectoryReadStore(hostRelay: hostRelay)
        self.store = store
        self.queryOpening = queryOpening
        let stored = store.load()
        let bounded = RoomDirectoryProjection.prunedBaselines(stored)
        self.baselines = bounded
        if bounded != stored { store.save(bounded) }
    }

    func observe() async {
        do {
            let query = try await queryOpening.demand(
                engine,
                roomDirectoryDemand(host: hostRelay),
                nil
            )
            defer { query.cancel() }

            for await batch in query {
                guard !Task.isCancelled else { return }
                ingest(rows: batch.rows)
                observationError = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            observationError = error.localizedDescription
        }
    }

    /// Clear a room's unread badge by advancing its baseline to the newest
    /// message currently known for it.
    func markRead(_ group: GroupSummary) {
        let key = group.localID
        baselines[key] = RoomDirectoryProjection.readBaseline(
            latest: latestByGroup[key],
            now: UInt64(Date().timeIntervalSince1970)
        )
        baselines = RoomDirectoryProjection.prunedBaselines(baselines)
        store.save(baselines)
        recompute()
    }

    private func ingest(rows: [Row]) {
        let messages = rows.compactMap { row -> ScopedRoomMessage? in
            guard let group = groupID(from: row.tags),
                  let message = NIP29ViewProjection.message(
                      eventID: row.id,
                      pubkey: row.pubkey,
                      createdAt: row.createdAt,
                      kind: row.kind,
                      content: row.content
                  ) else { return nil }
            return ScopedRoomMessage(groupID: group, message: message)
        }

        // First time a room is seen, baseline to the current wall clock so the
        // whole existing backlog (including late-arriving history) reads as read,
        // and only messages that land afterwards count as unread.
        let snapshot = RoomDirectoryProjection.snapshot(
            messages: messages,
            baselines: baselines,
            now: UInt64(Date().timeIntervalSince1970)
        )
        if snapshot.baselines != baselines { store.save(snapshot.baselines) }

        baselines = snapshot.baselines
        latestByGroup = snapshot.latestByGroup
        timesByGroup = snapshot.timesByGroup
        entries = snapshot.entries
    }

    private func recompute() {
        entries = RoomDirectoryProjection.entries(
            latestByGroup: latestByGroup,
            timesByGroup: timesByGroup,
            baselines: baselines
        )
    }

    private func groupID(from tags: [[String]]) -> String? {
        tags.first { $0.first == "h" && $0.count > 1 }?[1].nonEmpty
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
