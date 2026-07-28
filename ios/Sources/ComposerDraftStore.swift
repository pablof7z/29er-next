import Foundation

/// Persists the composer's in-progress text draft per room, the same
/// durability voice drafts already get via `VoiceDraftStore`, so navigating
/// away and back (or relaunching) restores what was being typed.
struct ComposerDraftStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, scope: String) {
        self.defaults = defaults
        key = "composer.textDraft.v1.\(scope)"
    }

    func load() -> String {
        defaults.string(forKey: key) ?? ""
    }

    func save(_ draft: String) {
        if draft.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(draft, forKey: key)
        }
    }
}
