import Foundation

/// Persists the preferred playback rate per agent so returning to an agent's
/// spoken updates resumes at the speed the listener last chose.
struct TTS29PlaybackRateStore {
    static let menu: [Double] = [0.8, 0.9, 1.0, 1.2, 1.5, 1.75, 2.0, 2.5]

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(for agent: String) -> String {
        let trimmed = agent.trimmingCharacters(in: .whitespacesAndNewlines)
        return "tts29.rate.\(trimmed.isEmpty ? "default" : trimmed)"
    }

    func rate(for agent: String) -> Double {
        let stored = defaults.double(forKey: key(for: agent))
        return stored > 0 ? stored : 1.0
    }

    func setRate(_ rate: Double, for agent: String) {
        defaults.set(rate, forKey: key(for: agent))
    }
}

extension Double {
    /// A rate label with no trailing zeros, e.g. "1×" or "1.2×".
    var tts29RateLabel: String {
        let text = self == rounded() ? String(Int(self)) : String(format: "%g", self)
        return "\(text)×"
    }
}
