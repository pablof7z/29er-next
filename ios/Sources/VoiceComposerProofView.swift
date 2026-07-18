#if NMP_DEVICE_PROOF && os(iOS)
import SwiftUI

/// Device-proof surface for the voice composer. It does NOT teach the gesture with
/// explanatory copy — it renders the real composer in a deterministic, injected state so
/// each visible affordance can be proven (and asserted by XCUITests). The state to show is
/// chosen by a `--voice-proof-state <case>` launch argument, defaulting to a live idle
/// composer for hands-on validation on a physical device.
struct VoiceComposerProofView: View {
    @State private var reply: ComposerReply?
    private let proofState = VoiceProofState.current

    var body: some View {
        VStack(spacing: 0) {
            Text(proofState.rawValue)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .accessibilityIdentifier("voice-proof-state")
            Spacer()
            ChatComposer(
                canSend: true,
                recipients: [],
                reply: $reply,
                voiceDraftScope: "device-proof",
                voiceCoordinator: proofState.makeCoordinator(),
                send: { _ in nil }
            )
        }
        .background(PlatformSupport.groupedBackground)
    }
}

/// The deterministic states the proof surface can render.
enum VoiceProofState: String {
    case idle
    case neutralHeld
    case lockHalf
    case lockArmed
    case lockedRecording
    case cancelHalf
    case cancelArmed
    case paused
    case finalizing
    case completedDraft
    case permissionDenied
    case publishFailure
    case recoveredDraft

    static var current: VoiceProofState {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--voice-proof-state"),
              index + 1 < arguments.count,
              let state = VoiceProofState(rawValue: arguments[index + 1]) else {
            return .idle
        }
        return state
    }

    @MainActor
    func makeCoordinator() -> VoiceComposerCoordinator {
        let permission: VoiceMicPermission = self == .permissionDenied ? .denied : .granted
        let coordinator = VoiceComposerCoordinator(
            store: VoiceDraftStore(scope: "device-proof"),
            engine: NoopVoiceRecorderEngine(),
            authority: FixedMicrophoneAuthority(status: permission),
            haptics: NoopVoiceHaptics(),
            announcer: NoopVoiceAnnouncer()
        )
        coordinator.proofInject(injectedState(permission: permission))
        return coordinator
    }

    private func injectedState(permission: VoiceMicPermission) -> VoiceComposerState {
        var state = VoiceComposerState(permission: permission)
        state.elapsed = 8
        state.waveform = Self.sampleWaveform
        switch self {
        case .idle:
            state.capture = .idle
            state.resetTelemetry()
        case .neutralHeld:
            state.capture = .recording; state.mode = .held; state.gesture = .neutral
        case .lockHalf:
            state.capture = .recording; state.mode = .held; state.gesture = .lockProgress(0.5)
        case .lockArmed:
            state.capture = .recording; state.mode = .held; state.gesture = .lockArmed
        case .lockedRecording:
            state.capture = .recording; state.mode = .locked
        case .cancelHalf:
            state.capture = .recording; state.mode = .held; state.gesture = .cancelProgress(0.5)
        case .cancelArmed:
            state.capture = .recording; state.mode = .held; state.gesture = .cancelArmed
        case .paused:
            state.capture = .paused; state.mode = .locked
        case .finalizing:
            state.capture = .finalizing(.send); state.mode = .locked
        case .completedDraft, .recoveredDraft:
            state.capture = .review(Self.draft)
        case .permissionDenied:
            state.capture = .failed(.permissionDenied)
        case .publishFailure:
            state.capture = .failed(.publish(Self.draft, "The relay rejected the message."))
        }
        return state
    }

    private static let draft = VoiceDraft(
        url: URL(fileURLWithPath: "/tmp/voice-proof.m4a"),
        duration: 12,
        waveform: sampleWaveform
    )

    private static let sampleWaveform: [Float] = (0..<40).map { index in
        Float(0.2 + 0.6 * abs((Double(index) * 0.7).truncatingRemainder(dividingBy: 2) - 1))
    }
}
#endif
