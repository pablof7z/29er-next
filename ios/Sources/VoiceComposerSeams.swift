import Foundation

/// The finalized output of a recorder stop: the on-disk file and its active duration
/// (paused wall-clock already excluded by the engine).
struct VoiceStopResult: Equatable, Sendable {
    let url: URL
    let duration: TimeInterval
}

/// Microphone-capture engine seam. The AVFoundation implementation lives behind this so
/// the coordinator and its tests never need a real microphone or permission dialog.
@MainActor
protocol VoiceRecorderEngine: AnyObject {
    /// Called on the main actor with a normalized 0…1 power sample and the current
    /// active duration each meter tick.
    var onSample: ((Float, TimeInterval) -> Void)? { get set }
    func start(url: URL) throws
    func pause()
    func resume()
    /// Stop capture. When `deliver` is true, finalize a playable file and report its
    /// active duration; otherwise return nil.
    func stop(deliver: Bool) -> VoiceStopResult?
}

/// Microphone authorization seam.
@MainActor
protocol MicrophoneAuthority: AnyObject {
    var status: VoiceMicPermission { get }
    func request() async -> VoiceMicPermission
}

/// Haptic feedback seam — one call per state boundary.
@MainActor
protocol VoiceHapticsPerforming: AnyObject {
    func perform(_ haptic: VoiceHaptic)
}

/// VoiceOver announcement seam.
@MainActor
protocol VoiceAnnouncing: AnyObject {
    func announce(_ message: String)
}

/// Inert engine for macOS and unit tests: never captures, never meters.
@MainActor
final class NoopVoiceRecorderEngine: VoiceRecorderEngine {
    var onSample: ((Float, TimeInterval) -> Void)?
    private var url: URL?
    func start(url: URL) throws { self.url = url }
    func pause() {}
    func resume() {}
    func stop(deliver: Bool) -> VoiceStopResult? {
        guard deliver, let url else { return nil }
        return VoiceStopResult(url: url, duration: 0)
    }
}

/// Authority that reports a fixed status (macOS default: denied so no capture UI engages).
@MainActor
final class FixedMicrophoneAuthority: MicrophoneAuthority {
    let status: VoiceMicPermission
    init(status: VoiceMicPermission) { self.status = status }
    func request() async -> VoiceMicPermission { status }
}
