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
    private let transcriptionService: VoiceTranscriptionService

    /// Resolved immediately before each transcription so configuration changes are
    /// explicit, while the returned snapshot stays fixed for that in-flight request.
    var providerSnapshot: (() throws -> VoiceProviderSnapshot)?

    private var currentDraft: VoiceDraft?
    private var pendingOriginalText = ""
    private var permissionTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var didAttemptRecovery = false

    init(
        store: VoiceDraftStore,
        engine: VoiceRecorderEngine,
        authority: MicrophoneAuthority,
        haptics: VoiceHapticsPerforming,
        announcer: VoiceAnnouncing,
        transcriptionService: VoiceTranscriptionService = VoiceTranscriptionService(),
        metrics: VoiceGestureMetrics = .default
    ) {
        self.store = store
        self.engine = engine
        self.authority = authority
        self.haptics = haptics
        self.announcer = announcer
        self.transcriptionService = transcriptionService
        self.state = VoiceComposerState(permission: authority.status, metrics: metrics)
        engine.onSample = { [weak self] level, duration in
            self?.dispatch(.meter(level))
            self?.dispatch(.tick(duration))
        }
        engine.onFailure = { [weak self] in
            guard let self else { return }
            self.announcer.announce(
                "Recording was interrupted. Saving everything captured so far."
            )
            self.dispatch(.audioInterruption)
        }
        observeAudioSession()
    }

    deinit {
        permissionTask?.cancel()
        transcriptionTask?.cancel()
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
    func retryTranscription() { dispatch(.retryTranscription) }
    func sceneBecameInactive() { dispatch(.appBackgrounded) }

    /// VoiceOver / non-gesture entry: start recording and immediately lock hands-free so
    /// the accessible cancel, stop, and send controls are available without a held gesture.
    func beginHandsFree(originalText: String = "") {
        pendingOriginalText = originalText
        dispatch(.touchBegan)
        if state.isHeldRecording { dispatch(.lockCommitted) }
    }

    /// Pause when recording, resume when paused — one control, two states.
    func togglePause() {
        state.isPaused ? dispatch(.resume) : dispatch(.pause)
    }

    /// Restore the oldest durable draft for this room, once, into the recovery card.
    func restoreDraftIfNeeded() {
        guard !didAttemptRecovery else { return }
        didAttemptRecovery = true
        guard state.capture == .idle, var draft = try? store.oldestDraft() else { return }
        currentDraft = draft
        recoveryTask = Task { [weak self] in
            if draft.duration <= 0 {
                draft.duration = await VoiceComposerCoordinator.loadDuration(of: draft.url)
            }
            guard let self, !Task.isCancelled else { return }
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
        case .releaseDraft: releaseCurrentDraft()
        case .persistDraft(let draft): persist(draft)
        case .transcribe(let draft): runTranscription(draft)
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
            let draft = try store.prepareDraft(originalText: pendingOriginalText)
            currentDraft = draft
            try engine.start(url: draft.url)
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
        var draft = currentDraft ?? VoiceDraft(
            url: result.url,
            duration: result.duration,
            waveform: state.waveform
        )
        draft.url = result.url
        draft.duration = result.duration
        draft.waveform = state.waveform
        draft.status = .ready
        currentDraft = draft
        persist(draft)
        dispatch(.recorderFinished(draft))
    }

    private func deleteCurrentDraft() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        if let draft = currentDraft { store.remove(draft.url) }
        currentDraft = nil
        pendingOriginalText = ""
    }

    private func releaseCurrentDraft() {
        currentDraft = nil
        pendingOriginalText = ""
    }

    private func persist(_ draft: VoiceDraft) {
        currentDraft = draft
        try? store.save(draft)
    }

    private func runTranscription(_ draft: VoiceDraft) {
        transcriptionTask?.cancel()
        guard let providerSnapshot else {
            dispatch(
                .transcriptionFailed(
                    draft,
                    VoiceProviderConfigurationError.missingConfiguration.localizedDescription
                )
            )
            return
        }
        let snapshot: VoiceProviderSnapshot
        do {
            snapshot = try providerSnapshot()
        } catch {
            dispatch(.transcriptionFailed(draft, error.localizedDescription))
            return
        }

        var working = draft
        working.providerConfigurationID = snapshot.configuration.id
        working.providerName = snapshot.configuration.name
        working.status = .transcribing
        persist(working)

        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let transcript = try await transcriptionService.transcribe(
                    audioURL: working.url,
                    snapshot: snapshot
                )
                guard !Task.isCancelled else { return }
                var completed = working
                completed.transcript = transcript
                completed.status = .transcriptReady
                do {
                    try store.save(completed)
                } catch {
                    self.dispatch(
                        .transcriptionFailed(
                            working,
                            "The transcript could not be saved safely. Your recording is still saved."
                        )
                    )
                    return
                }
                currentDraft = completed
                self.dispatch(.transcriptionSucceeded(completed))
            } catch {
                guard !Task.isCancelled else { return }
                self.dispatch(.transcriptionFailed(working, error.localizedDescription))
            }
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
