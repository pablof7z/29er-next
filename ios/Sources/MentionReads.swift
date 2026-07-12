import Foundation
import Observation

/// Persists per-mention read state. Read is visibility-driven: a mention only
/// becomes read once its message actually appears on screen in a room, so the
/// read set is a set of event ids rather than a per-room timestamp baseline.
/// `seededAt` is stamped once on first launch; mentions older than it are
/// treated as already read, so a large history never surfaces as unread.
struct MentionReadStore {
    private let defaults: UserDefaults
    private let readKey = "mention.read.v1"
    private let seedKey = "mention.seededAt.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadRead() -> Set<String> {
        Set(defaults.stringArray(forKey: readKey) ?? [])
    }

    func saveRead(_ ids: Set<String>) {
        defaults.set(Array(ids), forKey: readKey)
    }

    func loadSeededAt() -> UInt64? {
        (defaults.object(forKey: seedKey) as? NSNumber)?.uint64Value
    }

    func saveSeededAt(_ timestamp: UInt64) {
        defaults.set(NSNumber(value: timestamp), forKey: seedKey)
    }
}

/// The single source of truth for which mentions are read, shared by the inbox
/// badge and each room's in-timeline tracking so marking a mention read in
/// context clears it everywhere at once. App-owned product state; NMP owns the
/// events.
@MainActor
@Observable
final class MentionReads {
    private(set) var readIDs: Set<String>
    let seededAt: UInt64

    private let store: MentionReadStore

    init(
        store: MentionReadStore = MentionReadStore(),
        now: UInt64 = UInt64(Date().timeIntervalSince1970)
    ) {
        self.store = store
        self.readIDs = store.loadRead()
        if let existing = store.loadSeededAt() {
            self.seededAt = existing
        } else {
            store.saveSeededAt(now)
            self.seededAt = now
        }
    }

    /// A mention is unread only if it arrived after the seed point and has not
    /// yet been seen on screen.
    func isUnread(id: String, createdAt: UInt64) -> Bool {
        createdAt >= seededAt && !readIDs.contains(id)
    }

    func markRead(_ id: String) {
        guard !readIDs.contains(id) else { return }
        readIDs.insert(id)
        store.saveRead(readIDs)
    }
}
