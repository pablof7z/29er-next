import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
// One state machine owns transport, per-attachment resumes, player observation,
// and audio-session transitions; keeping those invariants together is clearer.
// swiftlint:disable:next type_body_length
final class AudioPlaybackController {
    private(set) var activeID: AudioAttachmentID?
    private(set) var phase = AudioPlaybackPhase.idle
    private(set) var currentTime = 0.0
    private(set) var duration = 0.0
    private(set) var playbackRate = 1.0
    private(set) var scrubTime = 0.0
    private(set) var isScrubbing = false

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var positions: [AudioAttachmentID: Double] = [:]
    private var durations: [AudioAttachmentID: Double] = [:]
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemNotifications: [NSObjectProtocol] = []
    @ObservationIgnored private var sessionNotifications: [NSObjectProtocol] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var readyTask: Task<Void, Never>?
    @ObservationIgnored private var wantsToPlay = false
    @ObservationIgnored private var resumeAfterScrub = false
    @ObservationIgnored private var resumeAfterInterruption = false

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        installPeriodicTimeObserver()
        installAudioSessionObservers()
    }

    func phase(for id: AudioAttachmentID) -> AudioPlaybackPhase {
        activeID == id ? phase : .idle
    }

    func position(for id: AudioAttachmentID) -> Double {
        if activeID == id { return isScrubbing ? scrubTime : currentTime }
        return positions[id] ?? 0
    }

    func duration(for id: AudioAttachmentID) -> Double {
        activeID == id ? duration : durations[id] ?? 0
    }

    func prepareDuration(for id: AudioAttachmentID, url: URL) async {
        guard durations[id] == nil else { return }
        let asset = AVURLAsset(url: url)
        guard let loaded = try? await asset.load(.duration).seconds,
              !Task.isCancelled,
              loaded.isFinite,
              loaded > 0 else { return }
        durations[id] = loaded
        if activeID == id { duration = loaded }
    }

    func toggle(id: AudioAttachmentID, url: URL) {
        guard activeID == id else {
            load(id: id, url: url)
            return
        }
        switch phase {
        case .playing, .buffering:
            pause()
        case .ended:
            restart(playing: true)
        case .failed:
            retry(id: id, url: url)
        case .loading:
            if wantsToPlay { pause() } else { play() }
        case .idle, .paused:
            play()
        }
    }

    func retry(id: AudioAttachmentID, url: URL) {
        positions[id] = 0
        load(id: id, url: url)
    }

    func pause() {
        guard activeID != nil else { return }
        wantsToPlay = false
        player.pause()
        saveActivePosition()
        if phase != .ended, !isFailure { phase = .paused }
    }

    func dismiss() {
        wantsToPlay = false
        resumeAfterScrub = false
        resumeAfterInterruption = false
        isScrubbing = false
        player.pause()
        saveActivePosition()
        clearItemObservers()
        player.replaceCurrentItem(with: nil)
        activeID = nil
        phase = .idle
        currentTime = 0
        duration = 0
        scrubTime = 0
        deactivateAudioSession()
    }

    func restart(playing: Bool? = nil) {
        guard activeID != nil else { return }
        let shouldPlay = playing ?? isActivelyPlaying
        seek(to: 0, resume: shouldPlay)
    }

    func skip(by seconds: Double) {
        guard activeID != nil else { return }
        seek(to: currentTime + seconds, resume: isActivelyPlaying)
    }

    func beginScrubbing() {
        guard duration.isFinite, duration > 0 else { return }
        resumeAfterScrub = isActivelyPlaying
        isScrubbing = true
        scrubTime = currentTime
        wantsToPlay = false
        player.pause()
        phase = .paused
    }

    func updateScrub(to seconds: Double) {
        guard isScrubbing else { return }
        scrubTime = clamped(seconds, duration: duration)
    }

    func endScrubbing() {
        guard isScrubbing else { return }
        let target = scrubTime
        let resume = resumeAfterScrub
        isScrubbing = false
        seek(to: target, resume: resume)
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = min(max(rate, 0.5), 2)
        player.defaultRate = Float(playbackRate)
        if isActivelyPlaying {
            player.rate = Float(playbackRate)
        }
    }

    private var isFailure: Bool { if case .failed = phase { true } else { false } }

    private var isActivelyPlaying: Bool { phase == .playing || phase == .buffering }

    private func load(id: AudioAttachmentID, url: URL) {
        saveActivePosition()
        clearItemObservers()
        player.pause()

        activeID = id
        currentTime = positions[id] ?? 0
        duration = durations[id] ?? 0
        phase = .loading
        wantsToPlay = true

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        observe(item)
    }

    private func observe(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in self?.handleStatus(of: item) }
        }
        timeControlObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] player, _ in
            Task { @MainActor in self?.handleTimeControlStatus(player.timeControlStatus) }
        }
        let center = NotificationCenter.default
        itemNotifications = [
            center.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.didReachEnd() }
            },
            center.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                Task { @MainActor in self?.fail(error) }
            }
        ]
    }

    private func handleStatus(of item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            prepareReadyItem(item)
        case .failed:
            fail(item.error)
        case .unknown:
            phase = .loading
        @unknown default:
            phase = .loading
        }
    }

    private func prepareReadyItem(_ item: AVPlayerItem) {
        readyTask?.cancel()
        let expectedID = activeID
        readyTask = Task { [weak self] in
            guard let self else { return }
            var loadedDuration = item.duration.seconds
            if !loadedDuration.isFinite || loadedDuration <= 0 {
                loadedDuration = (try? await item.asset.load(.duration).seconds) ?? 0
            }
            guard !Task.isCancelled, activeID == expectedID else { return }
            if loadedDuration.isFinite, loadedDuration > 0 {
                duration = loadedDuration
                if let expectedID { durations[expectedID] = loadedDuration }
            }
            let start = clamped(currentTime, duration: duration)
            if start > 0 {
                _ = await player.seek(
                    to: CMTime(seconds: start, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            }
            guard !Task.isCancelled, activeID == expectedID else { return }
            if wantsToPlay { play() } else { phase = .paused }
        }
    }

    private func play() {
        guard player.currentItem != nil else { return }
        wantsToPlay = true
        activateAudioSession()
        player.playImmediately(atRate: Float(playbackRate))
        if player.currentItem?.status == .readyToPlay { phase = .playing }
    }

    private func seek(to seconds: Double, resume: Bool) {
        guard let id = activeID else { return }
        let target = clamped(seconds, duration: duration)
        currentTime = target
        positions[id] = target
        wantsToPlay = resume
        Task { [weak self] in
            guard let self else { return }
            _ = await player.seek(
                to: CMTime(seconds: target, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            guard activeID == id else { return }
            if resume { play() } else { phase = target >= duration && duration > 0 ? .ended : .paused }
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        guard player.currentItem?.status == .readyToPlay, !isFailure else { return }
        switch status {
        case .playing:
            phase = .playing
        case .waitingToPlayAtSpecifiedRate:
            phase = currentTime > 0 ? .buffering : .loading
        case .paused:
            if phase != .ended { phase = wantsToPlay ? .loading : .paused }
        @unknown default:
            break
        }
    }

    private func didReachEnd() {
        updateDurationFromCurrentItem()
        let finalTime = player.currentTime().seconds
        currentTime = duration > 0 ? duration : max(currentTime, finalTime.isFinite ? finalTime : 0)
        saveActivePosition()
        wantsToPlay = false
        phase = .ended
        deactivateAudioSession()
    }

    private func fail(_ error: Error?) {
        wantsToPlay = false
        player.pause()
        phase = .failed(error?.localizedDescription ?? "Couldn’t play audio")
        deactivateAudioSession()
    }

    private func installPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in self?.receive(time: time) }
        }
    }

    private func receive(time: CMTime) {
        guard let id = activeID, !isScrubbing, phase != .ended else { return }
        updateDurationFromCurrentItem()
        let seconds = time.seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        currentTime = seconds
        positions[id] = seconds
    }

    private func updateDurationFromCurrentItem() {
        guard let id = activeID else { return }
        guard let item = player.currentItem else { return }
        let declaredDuration = item.duration.seconds
        let seekableDuration = item.seekableTimeRanges
            .last?
            .timeRangeValue
            .end
            .seconds ?? 0
        let itemDuration = declaredDuration.isFinite && declaredDuration > 0
            ? declaredDuration
            : seekableDuration
        guard itemDuration.isFinite, itemDuration > 0 else { return }
        duration = itemDuration
        durations[id] = itemDuration
    }

    private func saveActivePosition() {
        guard let activeID else { return }
        positions[activeID] = currentTime
        if duration.isFinite, duration > 0 { durations[activeID] = duration }
    }

    private func clearItemObservers() {
        readyTask?.cancel()
        readyTask = nil
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        for token in itemNotifications { NotificationCenter.default.removeObserver(token) }
        itemNotifications.removeAll()
    }

    private func clamped(_ seconds: Double, duration: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        guard duration.isFinite, duration > 0 else { return max(0, seconds) }
        return min(max(0, seconds), duration)
    }

    private func installAudioSessionObservers() {
        #if os(iOS)
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        sessionNotifications = [
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                Task { @MainActor in self?.handleInterruption(type: rawType, options: rawOptions) }
            },
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                Task { @MainActor in self?.handleRouteChange(reason: rawReason) }
            }
        ]
        #endif
    }

    private func activateAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    #if os(iOS)
    private func handleInterruption(type rawType: UInt?, options rawOptions: UInt?) {
        guard let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        if type == .began {
            resumeAfterInterruption = isActivelyPlaying
            pause()
            return
        }
        let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0).contains(.shouldResume)
        if resumeAfterInterruption, shouldResume { play() }
        resumeAfterInterruption = false
    }

    private func handleRouteChange(reason rawReason: UInt?) {
        guard let rawReason,
              AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable else { return }
        pause()
    }
    #endif
}
