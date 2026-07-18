import AVFoundation
import Foundation
import SwiftUI

/// Owns the voice composer state machine at runtime: seeds permission, dispatches events
/// through the pure reducer, and performs the resulting effects against injected seams.
/// It contains no transition logic itself — that all lives in `VoiceComposerReducer`.
@MainActor
final class VoiceComposerCoordinator: ObservableObject {
    @Published private(set) var state: VoiceComposerState

    let store: VoiceDraftStore
    private let engine: VoiceRecorderEngine
    private let authority: MicrophoneAuthority
    private let haptics: VoiceHapticsPerforming
    private let announcer: VoiceAnnouncing

    /// Routes a finalized draft through the canonical Blossom + NMP path. Set by the
    /// composer; nil in tests/proof, where publish outcomes are injected as events.
    var publisher: ((VoiceDraft) async -> String?)?

    private var currentURL: URL?
    private var permissionTask: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var didAttemptRecovery = false

    init(
        store: VoiceDraftStore,
        engine: VoiceRecorderEngine,
        authority: MicrophoneAuthority,
        haptics: VoiceHapticsPerforming,
        announcer: VoiceAnnouncing,
        metrics: VoiceGestureMetrics = .default
    ) {
        self.store = store
        self.engine = engine
        self.authority = authority
        self.haptics = haptics
        self.announcer = announcer
        self.state = VoiceComposerState(permission: authority.status, metrics: metrics)
        engine.onSample = { [weak self] level, duration in
            self?.dispatch(.meter(level))
            self?.dispatch(.tick(duration))
        }
        observeAudioSession()
    }

    deinit {
        permissionTask?.cancel()
        publishTask?.cancel()
        recoveryTask?.cancel()
    }

    // MARK: Intent entry points (called by views / accessibility / lifecycle)

    func pressBegan() { dispatch(.touchBegan) }
    func dragChanged(_ reading: VoiceGestureReading) { dispatch(.dragChanged(reading)) }
    func pressEnded() { dispatch(.touchEnded) }
    func pressCancelled() { dispatch(.gestureCancelled) }
    func lock() { dispatch(.lockCommitted) }
    func cancel() { dispatch(.cancelCommitted) }
    func pause() { dispatch(.pause) }
    func resume() { dispatch(.resume) }
    func stopForReview() { dispatch(.stopForReview) }
    func send() { dispatch(.send) }
    func discard() { dispatch(.discard) }
    func sceneBecameInactive() { dispatch(.appBackgrounded) }

    /// VoiceOver / non-gesture entry: start recording and immediately lock hands-free so
    /// the accessible toolbar (pause, delete, send) is available without a held gesture.
    func beginHandsFree() {
        dispatch(.touchBegan)
        if state.isHeldRecording { dispatch(.lockCommitted) }
    }

    /// Pause when recording, resume when paused — one control, two states.
    func togglePause() {
        state.isPaused ? dispatch(.resume) : dispatch(.pause)
    }

    /// Restore the newest durable draft for this room, once, into the review card.
    func restoreDraftIfNeeded() {
        guard !didAttemptRecovery else { return }
        didAttemptRecovery = true
        guard state.capture == .idle, let url = try? store.newestDraftURL() else { return }
        currentURL = url
        recoveryTask = Task { [weak self] in
            let duration = await VoiceComposerCoordinator.loadDuration(of: url)
            guard let self, !Task.isCancelled else { return }
            let draft = VoiceDraft(url: url, duration: duration, waveform: [])
            self.dispatch(.recoveredDraft(draft))
        }
    }

    // MARK: Reducer plumbing

    func dispatch(_ event: VoiceEvent) {
        let effects = VoiceComposerReducer.reduce(&state, event)
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: VoiceEffect) {
        switch effect {
        case .requestPermission: requestPermission()
        case .startRecorder: startRecorder()
        case .pauseRecorder: engine.pause()
        case .resumeRecorder: engine.resume()
        case .stopRecorder(let deliver): finishRecorder(deliver: deliver)
        case .deleteDraft: deleteCurrentDraft()
        case .publish(let draft): runPublish(draft)
        case .haptic(let haptic): haptics.perform(haptic)
        case .announce(let message): announcer.announce(message)
        }
    }

    private func requestPermission() {
        permissionTask?.cancel()
        permissionTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.authority.request()
            guard !Task.isCancelled else { return }
            self.dispatch(result == .granted ? .permissionGranted : .permissionDenied)
        }
    }

    private func startRecorder() {
        do {
            let url = try store.createURL()
            currentURL = url
            try engine.start(url: url)
        } catch {
            dispatch(.recorderStartFailed(error.localizedDescription))
        }
    }

    private func finishRecorder(deliver: Bool) {
        let result = engine.stop(deliver: deliver)
        guard deliver else { return }
        guard let result else {
            dispatch(.recorderFinished(nil))
            return
        }
        let draft = VoiceDraft(url: result.url, duration: result.duration, waveform: state.waveform)
        dispatch(.recorderFinished(draft))
    }

    private func deleteCurrentDraft() {
        if let url = currentURL { store.remove(url) }
        currentURL = nil
    }

    private func runPublish(_ draft: VoiceDraft) {
        guard let publisher else { return }
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            let error = await publisher(draft)
            guard let self, !Task.isCancelled else { return }
            self.dispatch(error == nil ? .sendSucceeded : .publishFailed(error!))
        }
    }

    static func loadDuration(of url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds,
              seconds.isFinite, seconds > 0 else { return 0 }
        return seconds
    }

    #if NMP_DEVICE_PROOF
    /// Inject a deterministic state for the device-proof surface. Never shipped in the app.
    func proofInject(_ newState: VoiceComposerState) {
        didAttemptRecovery = true
        state = newState
    }
    #endif
}
