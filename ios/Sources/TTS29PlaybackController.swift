import AVFoundation
import Foundation
import NMP
import Observation

enum TTS29PlaybackPhase: Equatable {
    case idle
    case loading
    case playing
    case paused
    case ended
    case failed(String)
}

/// The room context a presented player needs to publish answers.
struct TTS29SendContext: Equatable {
    let host: String
    let groupID: String
    let activePubkey: String?
}

/// App-level owner of TTS29 spoken playback. It drives one `AVPlayer`, keeps
/// per-item resume offsets and per-agent speed, and holds the presentation
/// state for the docked mini-player and the full player surface so audio keeps
/// playing while the listener navigates elsewhere.
@MainActor
@Observable
final class TTS29PlaybackController {
    private(set) var selectedItem: TTS29Item?
    /// The assembled item rooting the open full-player surface, or nil when only
    /// the mini-player is docked. The player's internal navigation walks this
    /// item's narrated-branch tree.
    var presentedRoot: TTS29Item?
    private(set) var phase = TTS29PlaybackPhase.idle
    private(set) var currentTime = 0.0
    private(set) var duration = 0.0
    private(set) var rate = 1.0
    private(set) var context = TTS29SendContext(host: "", groupID: "", activePubkey: nil)
    var answerState = TTS29AnswerState.idle
    /// The viewer's prior answer for the presented root item, captured from the
    /// room catalog at open time.
    private(set) var presentedAnswer: TTS29AnswerBundle?

    @ObservationIgnored private var engine: NMPEngine?
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let rateStore = TTS29PlaybackRateStore()
    @ObservationIgnored private var resumePositions: [String: Double] = [:]
    @ObservationIgnored private var selectedURL: URL?
    @ObservationIgnored private var wantsToPlay = false
    @ObservationIgnored private var pendingResume: Double?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemNotifications: [NSObjectProtocol] = []
    @ObservationIgnored private var timeObserver: Any?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        installPeriodicTimeObserver()
    }

    var isActive: Bool { selectedItem != nil }
    var isPlaying: Bool { phase == .playing || phase == .loading }

    func isActive(_ item: TTS29Item) -> Bool { selectedItem?.id == item.id }

    /// The saved offset to resume an item from, if it was left partway through
    /// (for example a parent left for a narrated branch).
    func resumeOffset(for item: TTS29Item) -> Double? { resumePositions[item.id] }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var statusText: String {
        switch phase {
        case .idle: "Ready"
        case .loading: "Loading audio…"
        case .playing: "Playing"
        case .paused: "Paused"
        case .ended: "Finished"
        case .failed(let message): message
        }
    }

    // MARK: - Presentation

    /// Open an item's full player and start playback. Called from a tapped card
    /// or narrated branch; never from a card merely appearing (no autoplay).
    func open(
        _ item: TTS29Item,
        existingAnswer: TTS29AnswerBundle?,
        context: TTS29SendContext,
        engine: NMPEngine?
    ) {
        self.context = context
        self.engine = engine
        presentedAnswer = existingAnswer
        answerState = .idle
        if !isActive(item) { start(item) }
        presentedRoot = item
    }

    /// The viewer's prior answer for a shown item, when it is the presented
    /// root. Narrated children rarely carry questions and are not prefilled.
    func answer(for item: TTS29Item) -> TTS29AnswerBundle? {
        presentedAnswer?.itemID == item.id ? presentedAnswer : nil
    }

    /// Switch the transport to a narrated child while its player is pushed onto
    /// the surface's internal navigation. The presented root is unchanged.
    func openChild(_ item: TTS29Item) {
        answerState = .idle
        if !isActive(item) { start(item) }
    }

    /// Reopen the currently playing item's full player from the mini-player.
    func presentSelected() {
        presentedRoot = selectedItem
    }

    // MARK: - Transport

    func toggle(_ item: TTS29Item) {
        guard isActive(item) else {
            start(item)
            return
        }
        switch phase {
        case .playing, .loading: pause()
        case .paused, .idle: play()
        case .ended: replay()
        case .failed: start(item)
        }
    }

    func toggleSelected() {
        guard let selectedItem else { return }
        toggle(selectedItem)
    }

    func pause() {
        wantsToPlay = false
        player.pause()
        saveActivePosition()
        if phase != .ended, !isFailure { phase = .paused }
    }

    func play() {
        guard player.currentItem != nil else { return }
        wantsToPlay = true
        activateAudioSession()
        player.playImmediately(atRate: Float(rate))
        if player.currentItem?.status == .readyToPlay { phase = .playing }
    }

    func replay() { seek(to: 0, resume: true) }

    func skip(by seconds: Double) {
        guard isActive else { return }
        seek(to: currentTime + seconds, resume: isPlaying)
    }

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        seek(to: fraction * duration, resume: wantsToPlay || phase == .playing)
    }

    func setRate(_ newRate: Double) {
        rate = min(max(newRate, 0.5), 2.5)
        if phase == .playing { player.rate = Float(rate) }
        rateStore.setRate(rate, for: selectedItem?.agentName ?? "")
    }

    func dismiss() {
        wantsToPlay = false
        player.pause()
        clearItemObservers()
        player.replaceCurrentItem(with: nil)
        selectedItem = nil
        selectedURL = nil
        presentedRoot = nil
        phase = .idle
        currentTime = 0
        duration = 0
        deactivateAudioSession()
    }

    // MARK: - Loading

    private func start(_ item: TTS29Item) {
        guard let url = item.playableURL, url.scheme == "https" || url.isFileURL else {
            selectedItem = item
            phase = .failed("Audio is unavailable.")
            return
        }
        savePreviousPositionBeforeSwitching(to: item)

        clearItemObservers()
        player.pause()
        selectedItem = item
        selectedURL = url
        rate = rateStore.rate(for: item.agentName)
        currentTime = 0
        duration = 0
        phase = .loading
        wantsToPlay = true
        pendingResume = resumePositions[item.id]

        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        observe(playerItem)
    }

    /// Remember where the outgoing item was left so returning to it (for
    /// example, a parent after a narrated branch) resumes in place.
    private func savePreviousPositionBeforeSwitching(to item: TTS29Item) {
        guard let previous = selectedItem, previous.id != item.id else { return }
        if currentTime > 0.5, duration > 0, currentTime < duration - 0.5 {
            resumePositions[previous.id] = currentTime
        }
    }

    private func observe(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in self?.handleStatus(of: item) }
        }
        let center = NotificationCenter.default
        itemNotifications = [
            center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.didReachEnd() }
            },
            center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                Task { @MainActor in self?.fail(error) }
            }
        ]
    }

    private func handleStatus(of item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay: prepareReadyItem(item)
        case .failed: fail(item.error)
        default: break
        }
    }

    private func prepareReadyItem(_ item: AVPlayerItem) {
        var loaded = item.duration.seconds
        if !loaded.isFinite || loaded <= 0 { loaded = 0 }
        if loaded > 0 { duration = loaded }
        if let resume = pendingResume, resume > 0, resume < duration {
            currentTime = resume
            Task { await seekPlayer(to: resume) }
        }
        pendingResume = nil
        if wantsToPlay { play() } else { phase = .paused }
    }

    private func seek(to seconds: Double, resume: Bool) {
        let target = clamp(seconds)
        currentTime = target
        if let id = selectedItem?.id { resumePositions[id] = target }
        wantsToPlay = resume
        Task {
            await seekPlayer(to: target)
            if resume { play() } else { phase = target >= duration && duration > 0 ? .ended : .paused }
        }
    }

    private func seekPlayer(to seconds: Double) async {
        _ = await player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func didReachEnd() {
        currentTime = duration
        saveActivePosition()
        resumePositions[selectedItem?.id ?? ""] = nil
        wantsToPlay = false
        phase = .ended
        deactivateAudioSession()
    }

    private func fail(_ error: Error?) {
        wantsToPlay = false
        player.pause()
        phase = .failed(error?.localizedDescription ?? "Couldn’t play audio.")
        deactivateAudioSession()
    }

    private func installPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in self?.receive(time: time) }
        }
    }

    private func receive(time: CMTime) {
        guard selectedItem != nil, phase != .ended else { return }
        let declared = player.currentItem?.duration.seconds ?? 0
        if declared.isFinite, declared > 0 { duration = declared }
        let seconds = time.seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        currentTime = seconds
        if let id = selectedItem?.id { resumePositions[id] = seconds }
        if phase == .loading, player.timeControlStatus == .playing { phase = .playing }
    }

    private func saveActivePosition() {
        guard let id = selectedItem?.id else { return }
        resumePositions[id] = currentTime
    }

    private func clearItemObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        for token in itemNotifications { NotificationCenter.default.removeObserver(token) }
        itemNotifications.removeAll()
    }

    private var isFailure: Bool { if case .failed = phase { true } else { false } }

    private func clamp(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        guard duration > 0 else { return max(0, seconds) }
        return min(max(0, seconds), duration)
    }

    private func activateAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    var currentEngine: NMPEngine? { engine }
}
