import Foundation

/// Every input the voice composer reducer understands. Views, gestures, AVFoundation
/// callbacks, permission results, and the send bridge all funnel through these so the
/// transition system can be exercised deterministically in tests.
enum VoiceEvent: Equatable, Sendable {
    // Gesture transaction
    case touchBegan
    case dragChanged(VoiceGestureReading)
    case touchEnded
    case gestureCancelled

    // Permission
    case permissionGranted
    case permissionDenied

    // Explicit (accessibility / button) commands
    case lockCommitted
    case cancelCommitted
    case pause
    case resume
    case stopForReview
    case send
    case discard

    // Recorder + system callbacks
    case recorderStarted
    case recorderStartFailed(String)
    case recorderFinished(VoiceDraft?)
    case recorderFinishFailed(String)
    case audioInterruption
    case routeChange
    case appBackgrounded

    // Publish bridge (canonical send path reports back here)
    case uploadFailed(String)
    case publishFailed(String)
    case sendSucceeded

    // Room reopen restores a durable draft into the voice-specific review card
    case recoveredDraft(VoiceDraft)

    // Telemetry
    case tick(TimeInterval)
    case meter(Float)
}

/// Side effects the coordinator performs. The reducer stays pure and returns these;
/// they are `Equatable` so tests can assert the exact effect list per transition.
enum VoiceEffect: Equatable, Sendable {
    case requestPermission
    case startRecorder
    case pauseRecorder
    case resumeRecorder
    /// Stop capture; `deliver` true asks the engine to finalize a playable file.
    case stopRecorder(deliver: Bool)
    case deleteDraft
    /// Hand the finalized draft to the canonical upload + NMP publication path.
    case publish(VoiceDraft)
    case haptic(VoiceHaptic)
    case announce(String)
}

/// One haptic per state boundary — never a continuous stream.
enum VoiceHaptic: Equatable, Sendable {
    case recordingStart
    case lockArmed
    case lockCommitted
    case cancelArmed
    case cancelCommitted
    case pause
    case resume
    case discard
    case failure
    case sent
}
