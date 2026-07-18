import AVFoundation
import Foundation

/// Playback for a finalized local voice draft in the review card. Kept separate from the
/// timeline's `AudioPlaybackController` (which is keyed by message identity). Resets its
/// control to "play" when playback reaches the end, and stops cleanly on teardown.
@MainActor
final class VoiceDraftPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    /// 0…1 through the current draft, for the scrubber/waveform tint.
    @Published private(set) var progress = 0.0

    private let player = AVPlayer()
    private var url: URL?
    private var duration = 0.0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.updateProgress(time.seconds) }
        }
    }

    func toggle(url: URL, duration: TimeInterval) {
        if self.url != url { load(url: url, duration: duration) }
        isPlaying ? pause() : play()
    }

    func play() {
        guard url != nil else { return }
        activateSession()
        if progress >= 1 { seekToStart() }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    /// Stop and release — call when the draft is deleted or the card disappears.
    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        isPlaying = false
        progress = 0
        url = nil
    }

    /// Reset the control when playback finishes. Exposed for deterministic testing.
    func markFinished() {
        isPlaying = false
        progress = 0
        player.seek(to: .zero)
    }

    private func load(url: URL, duration: TimeInterval) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        self.url = url
        self.duration = duration
        progress = 0
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.markFinished() }
        }
    }

    private func updateProgress(_ seconds: Double) {
        guard isPlaying, duration > 0, seconds.isFinite else { return }
        progress = min(1, max(0, seconds / duration))
    }

    private func seekToStart() {
        player.seek(to: .zero)
        progress = 0
    }

    private func activateSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
}
