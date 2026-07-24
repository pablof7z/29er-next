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
    private(set) var profiles = ProfileBook()
    private(set) var profileError: String?

    private let engine: NMPEngine
    private let hostRelay: String
    private let store: DirectoryReadStore
    private let queryOpening: NMPQueryOpening
    private var baselines: [String: UInt64]
    private var latestByGroup: [String: RoomMessage] = [:]
    private var timesByGroup: [String: [UInt64]] = [:]
    private let profileAuthorUpdates = ProfileAuthorUpdates()
    private var lastProfileAuthors: [String]?

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
        lastProfileAuthors = nil
        publishProfileAuthors()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in await self?.observeDirectory() }
            group.addTask { [weak self] in await self?.observeProfiles() }
        }
    }

    private func observeDirectory() async {
        do {
            let query = try await queryOpening.demand(
                engine,
                roomDirectoryDemand(host: hostRelay)
            )
            defer { query.cancel() }

            for try await batch in query {
                guard !Task.isCancelled else { return }
                ingest(rows: batch.rows)
                observationError = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            observationError = error.localizedDescription
        }
    }

    /// Kind:0 for every room's most-recent-message author, via the same
    /// reactive derived-author-set pattern as `RoomTimelineModel`'s profile
    /// fetch, so the channel-list preview can resolve a display name the
    /// same way a room's own message header does.
    private func observeProfiles() async {
        var observation: Task<Void, Never>?
        for await authors in profileAuthorUpdates.stream {
            guard !Task.isCancelled else { break }
            if let observation {
                observation.cancel()
                await observation.value
            }
            observation = Task { [weak self] in
                await self?.observeProfiles(authors: authors)
            }
        }
        observation?.cancel()
        await observation?.value
    }

    private func observeProfiles(authors: [String]) async {
        do {
            let query = try await queryOpening.filter(
                engine,
                NMPFilter(kinds: [0], authors: .literal(Set(authors)), limit: 1_000)
            )
            defer { query.cancel() }

            for try await batch in query {
                guard !Task.isCancelled else { return }
                profiles = RoomProfileProjection.profiles(from: batch.rows)
                profileError = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            profileError = error.localizedDescription
            profileAuthorUpdates.continuation.finish()
        }
    }

    private func publishProfileAuthors() {
        let authors = Set(entries.values.compactMap { $0.latest?.author }).sorted()
        guard authors != lastProfileAuthors else { return }
        lastProfileAuthors = authors
        profileAuthorUpdates.continuation.yield(authors)
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
        publishProfileAuthors()
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
