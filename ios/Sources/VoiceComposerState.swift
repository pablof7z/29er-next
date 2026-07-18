import Foundation

/// A finalized, playable local voice recording. Produced only after the recorder
/// stops cleanly; `duration` is *active* seconds (paused wall-clock excluded).
struct VoiceDraft: Equatable, Sendable {
    let url: URL
    let duration: TimeInterval
    let waveform: [Float]

    /// Presentation title that never leaks the generated UUID filename.
    var accessibleTitle: String { "Voice message, \(VoiceDurationText.spoken(duration))" }
}

/// Whether a finalize was requested to publish immediately or to stop for review.
enum VoiceFinalizeIntent: Equatable, Sendable {
    case send
    case review
}

/// Microphone authorization as the reducer understands it — seeded and updated by the
/// coordinator so `touchBegan` can branch without touching AVFoundation.
enum VoiceMicPermission: Equatable, Sendable {
    case undetermined
    case granted
    case denied
}

/// Audio/capture lifecycle. Deliberately independent of interaction mode: "locked" is
/// not a capture phase, it is a composer interaction mode (see `VoiceInteractionMode`).
enum VoiceCapture: Equatable, Sendable {
    case idle
    case requestingPermission
    case recording
    case paused
    case finalizing(VoiceFinalizeIntent)
    case review(VoiceDraft)
    case publishing(VoiceDraft)
    case failed(VoiceFailure)
}

/// Persistent interaction mode while capture is live.
enum VoiceInteractionMode: Equatable, Sendable {
    case held
    case locked
}

/// Transient held-gesture intent, derived from `VoiceGestureReading` under hysteresis.
enum VoiceGesturePhase: Equatable, Sendable {
    case inactive
    case neutral
    case lockProgress(Double)
    case lockArmed
    case cancelProgress(Double)
    case cancelArmed

    /// 0…1 lock-rail fill, whatever the current phase.
    var lockFraction: Double {
        switch self {
        case .lockProgress(let value): value
        case .lockArmed: 1
        default: 0
        }
    }

    /// 0…1 cancel-track fill, whatever the current phase.
    var cancelFraction: Double {
        switch self {
        case .cancelProgress(let value): value
        case .cancelArmed: 1
        default: 0
        }
    }

    var isLockArmed: Bool { self == .lockArmed }
    var isCancelArmed: Bool { self == .cancelArmed }
}

/// Recoverable failure surfaces. Every case is user-visible and offers a way forward.
enum VoiceFailure: Equatable, Sendable {
    case permissionDenied
    case recorder(String)
    case publish(VoiceDraft, String)

    var message: String {
        switch self {
        case .permissionDenied:
            "Microphone access is off. Open Settings to record voice messages."
        case .recorder(let detail):
            detail
        case .publish(_, let detail):
            detail
        }
    }

    /// A draft the user can retry sending or delete, when the failure preserved one.
    var draft: VoiceDraft? {
        if case .publish(let draft, _) = self { return draft }
        return nil
    }

    var isPermissionDenied: Bool { self == .permissionDenied }
}

/// The whole voice composer state: capture lifecycle, interaction mode, transient
/// gesture, and live telemetry. `Equatable` so the reducer can be tested by value.
struct VoiceComposerState: Equatable, Sendable {
    var permission: VoiceMicPermission
    var capture: VoiceCapture = .idle
    var mode: VoiceInteractionMode = .held
    var gesture: VoiceGesturePhase = .inactive
    var elapsed: TimeInterval = 0
    var waveform: [Float] = []
    var metrics: VoiceGestureMetrics

    /// Rolling waveform window kept bounded for the live meter and the review card.
    static let waveformWindow = 48

    init(
        permission: VoiceMicPermission = .undetermined,
        metrics: VoiceGestureMetrics = .default
    ) {
        self.permission = permission
        self.metrics = metrics
    }

    // MARK: Derived presentation flags

    /// The composer is showing any voice surface rather than the text field.
    var isEngaged: Bool {
        switch capture {
        case .idle: false
        case .failed(let failure): !failure.isPermissionDenied || permission == .denied
        default: true
        }
    }

    var isHeldRecording: Bool { capture == .recording && mode == .held }

    var isLockedActive: Bool {
        guard mode == .locked else { return false }
        switch capture {
        case .recording, .paused, .finalizing, .publishing: return true
        default: return false
        }
    }

    var isPaused: Bool { capture == .paused }

    var isFinalizingOrPublishing: Bool {
        switch capture {
        case .finalizing, .publishing: true
        default: false
        }
    }

    var reviewDraft: VoiceDraft? {
        if case .review(let draft) = capture { return draft }
        return nil
    }

    /// The draft currently being pushed through the canonical send path, if any.
    var publishingDraft: VoiceDraft? {
        if case .publishing(let draft) = capture { return draft }
        return nil
    }

    var failure: VoiceFailure? {
        if case .failed(let failure) = capture { return failure }
        return nil
    }

    /// True once elapsed active time is meaningful enough to send.
    var meetsMinimumDuration: Bool { elapsed >= metrics.minimumDuration }

    mutating func resetTelemetry() {
        elapsed = 0
        waveform = []
    }

    mutating func appendWaveform(_ sample: Float) {
        waveform.append(max(0, min(1, sample)))
        if waveform.count > Self.waveformWindow {
            waveform.removeFirst(waveform.count - Self.waveformWindow)
        }
    }
}

/// Duration formatting shared by the timer, review card, and accessibility strings.
enum VoiceDurationText {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func spoken(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let secs = total % 60
        switch (minutes, secs) {
        case (0, let s): return "\(s) second\(s == 1 ? "" : "s")"
        case (let m, 0): return "\(m) minute\(m == 1 ? "" : "s")"
        case (let m, let s):
            return "\(m) minute\(m == 1 ? "" : "s") \(s) second\(s == 1 ? "" : "s")"
        }
    }
}
