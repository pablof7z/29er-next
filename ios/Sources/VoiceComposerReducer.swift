import Foundation

/// The single source of truth for voice composer transitions. Pure: `(state, event) →
/// effects`, no SwiftUI, AVFoundation, clock, or I/O. Everything the product must never
/// do — auto-send across a permission prompt, send a system-cancelled gesture, send a
/// sub-minimum tap, double-publish — is enforced here and covered by unit tests.
enum VoiceComposerReducer {
    static func reduce(_ state: inout VoiceComposerState, _ event: VoiceEvent) -> [VoiceEffect] {
        switch event {
        case .touchBegan: return touchBegan(&state)
        case .dragChanged(let reading): return VoiceGestureResolver.dragChanged(&state, reading)
        case .touchEnded: return touchEnded(&state)
        case .gestureCancelled: return gestureCancelled(&state)

        case .permissionGranted: return permissionGranted(&state)
        case .permissionDenied: return permissionDenied(&state)

        case .lockCommitted:
            guard state.isHeldRecording else { return [] }
            return commitLock(&state)
        case .cancelCommitted:
            guard state.isHeldRecording else { return [] }
            return commitCancel(&state)
        case .pause: return pause(&state)
        case .resume: return resume(&state)
        case .stopForReview: return stopForReview(&state)
        case .send: return send(&state)
        case .discard: return discard(&state)

        case .recorderStarted: return []
        case .recorderStartFailed(let detail): return recorderStartFailed(&state, detail)
        case .recorderFinished(let draft): return recorderFinished(&state, draft)
        case .recorderFinishFailed(let detail): return recorderStartFailed(&state, detail)
        case .audioInterruption, .routeChange, .appBackgrounded:
            return preserveForSystem(&state)

        case .uploadFailed(let detail), .publishFailed(let detail):
            return publishFailed(&state, detail)
        case .sendSucceeded: return sendSucceeded(&state)
        case .recoveredDraft(let draft): return recoveredDraft(&state, draft)

        case .tick(let elapsed): return tick(&state, elapsed)
        case .meter(let sample): return meter(&state, sample)
        }
    }

    // MARK: Gesture transaction

    private static func touchBegan(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        switch state.permission {
        case .granted:
            state.capture = .recording
            state.mode = .held
            state.gesture = .neutral
            state.resetTelemetry()
            return [.startRecorder, .haptic(.recordingStart)]
        case .denied:
            state.capture = .failed(.permissionDenied)
            return [.announce(VoiceFailure.permissionDenied.message)]
        case .undetermined:
            // Opening the system prompt invalidates this press. We do NOT track a
            // pending send; the grant path requires a fresh gesture.
            state.capture = .requestingPermission
            state.gesture = .inactive
            return [.requestPermission]
        }
    }

    private static func touchEnded(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        guard state.isHeldRecording else { return [] }
        switch state.gesture {
        case .cancelArmed: return commitCancel(&state)
        case .lockArmed: return commitLock(&state)
        default: return beginFinalize(&state, intent: .send)
        }
    }

    private static func gestureCancelled(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        // A system-cancelled gesture must never read as release/send. Preserve capture
        // by locking hands-free so the user keeps a visible, controllable recording.
        guard state.isHeldRecording else { return [] }
        return commitLock(&state)
    }

    static func commitLock(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        state.mode = .locked
        state.gesture = .inactive
        return [.haptic(.lockCommitted), .announce("Recording locked. Hands-free recording.")]
    }

    static func commitCancel(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        state.capture = .idle
        state.mode = .held
        state.gesture = .inactive
        state.resetTelemetry()
        return [
            .stopRecorder(deliver: false),
            .deleteDraft,
            .haptic(.cancelCommitted),
            .announce("Recording cancelled")
        ]
    }

    private static func beginFinalize(
        _ state: inout VoiceComposerState,
        intent: VoiceFinalizeIntent
    ) -> [VoiceEffect] {
        state.capture = .finalizing(intent)
        state.gesture = .inactive
        return [.stopRecorder(deliver: true)]
    }

    // MARK: Permission

    private static func permissionGranted(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        state.permission = .granted
        guard state.capture == .requestingPermission else { return [] }
        // Return to idle: never start or auto-send from the invalidated press.
        state.capture = .idle
        return [.announce("Microphone enabled — hold to record")]
    }

    private static func permissionDenied(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        state.permission = .denied
        if state.capture == .requestingPermission {
            state.capture = .failed(.permissionDenied)
        }
        return [.haptic(.failure), .announce(VoiceFailure.permissionDenied.message)]
    }

    // MARK: Locked-mode commands

    private static func pause(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        guard state.capture == .recording, state.mode == .locked else { return [] }
        state.capture = .paused
        return [.pauseRecorder, .haptic(.pause), .announce("Recording paused")]
    }

    private static func resume(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        guard state.capture == .paused else { return [] }
        state.capture = .recording
        return [.resumeRecorder, .haptic(.resume), .announce("Recording resumed")]
    }

    private static func stopForReview(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        guard canFinalizeFromLocked(state) else { return [] }
        return beginFinalize(&state, intent: .review)
    }

    private static func send(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        switch state.capture {
        case .recording where state.mode == .locked, .paused:
            return beginFinalize(&state, intent: .send)
        case .review(let draft):
            state.capture = .publishing(draft)
            return [.publish(draft)]
        case .failed(let failure):
            guard let draft = failure.draft else { return [] }
            state.capture = .publishing(draft)
            return [.publish(draft)]
        default:
            // finalizing / publishing / held / idle: ignore so repeated taps cannot
            // duplicate finalization or publication.
            return []
        }
    }

    private static func discard(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        switch state.capture {
        case .idle, .requestingPermission:
            return []
        default:
            state.capture = .idle
            state.mode = .held
            state.gesture = .inactive
            state.resetTelemetry()
            return [
                .stopRecorder(deliver: false),
                .deleteDraft,
                .haptic(.discard),
                .announce("Recording deleted")
            ]
        }
    }

    private static func canFinalizeFromLocked(_ state: VoiceComposerState) -> Bool {
        (state.capture == .recording && state.mode == .locked) || state.capture == .paused
    }

    // MARK: Recorder + system callbacks

    private static func recorderStartFailed(
        _ state: inout VoiceComposerState,
        _ detail: String
    ) -> [VoiceEffect] {
        state.capture = .failed(.recorder(detail))
        state.mode = .held
        state.gesture = .inactive
        state.resetTelemetry()
        return [.haptic(.failure), .announce(detail)]
    }

    private static func recorderFinished(
        _ state: inout VoiceComposerState,
        _ draft: VoiceDraft?
    ) -> [VoiceEffect] {
        guard case .finalizing(let intent) = state.capture else { return [] }
        guard let draft, draft.duration >= state.metrics.minimumDuration else {
            // Undersized recording: discard quietly, never surface as an upload error.
            state.capture = .idle
            state.mode = .held
            state.gesture = .inactive
            state.resetTelemetry()
            return [.deleteDraft, .announce("Recording too short to send")]
        }
        switch intent {
        case .review:
            state.capture = .review(draft)
            return [.announce("Voice message ready to review")]
        case .send:
            state.capture = .publishing(draft)
            return [.publish(draft)]
        }
    }

    private static func preserveForSystem(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        switch state.capture {
        case .recording, .paused:
            // Finalize into a visible, unsent, reviewable draft. Never auto-send.
            state.capture = .finalizing(.review)
            state.gesture = .inactive
            return [.stopRecorder(deliver: true)]
        default:
            return []
        }
    }

    // MARK: Publish outcome

    private static func sendSucceeded(_ state: inout VoiceComposerState) -> [VoiceEffect] {
        guard case .publishing = state.capture else { return [] }
        state.capture = .idle
        state.mode = .held
        state.gesture = .inactive
        state.resetTelemetry()
        // Local draft removed only after the canonical send path succeeds.
        return [.deleteDraft, .haptic(.sent), .announce("Voice message sent")]
    }

    private static func publishFailed(
        _ state: inout VoiceComposerState,
        _ detail: String
    ) -> [VoiceEffect] {
        guard case .publishing(let draft) = state.capture else { return [] }
        state.capture = .failed(.publish(draft, detail))
        return [.haptic(.failure), .announce("Sending failed. \(detail)")]
    }

    private static func recoveredDraft(
        _ state: inout VoiceComposerState,
        _ draft: VoiceDraft
    ) -> [VoiceEffect] {
        // Only surface a recovered draft over a clean composer; never clobber live capture.
        guard state.capture == .idle else { return [] }
        state.capture = .review(draft)
        state.mode = .held
        return [.announce("Recovered an unsent voice message")]
    }

    // MARK: Telemetry

    private static func tick(
        _ state: inout VoiceComposerState,
        _ elapsed: TimeInterval
    ) -> [VoiceEffect] {
        guard state.capture == .recording else { return [] }
        state.elapsed = elapsed
        guard elapsed >= state.metrics.maximumDuration else { return [] }
        // Ceiling reached: finalize into review so captured audio is preserved safely.
        return beginFinalize(&state, intent: .review)
            + [.announce("Maximum length reached. Review your voice message.")]
    }

    private static func meter(
        _ state: inout VoiceComposerState,
        _ sample: Float
    ) -> [VoiceEffect] {
        guard state.capture == .recording else { return [] }
        state.appendWaveform(sample)
        return []
    }
}
