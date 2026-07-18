import AVFoundation
import Foundation

extension VoiceComposerCoordinator {
    /// Production coordinator: real AVFoundation capture on iOS, inert seams elsewhere.
    static func live(store: VoiceDraftStore) -> VoiceComposerCoordinator {
        #if os(iOS)
        return VoiceComposerCoordinator(
            store: store,
            engine: AVVoiceRecorderEngine(),
            authority: SystemMicrophoneAuthority(),
            haptics: SystemVoiceHaptics(),
            announcer: SystemVoiceAnnouncer()
        )
        #else
        return VoiceComposerCoordinator(
            store: store,
            engine: NoopVoiceRecorderEngine(),
            authority: FixedMicrophoneAuthority(status: .denied),
            haptics: NoopVoiceHaptics(),
            announcer: NoopVoiceAnnouncer()
        )
        #endif
    }

    /// Observe AVAudioSession interruptions and route changes and preserve any live draft.
    func observeAudioSession() {
        #if os(iOS)
        let center = NotificationCenter.default
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard AVAudioSession.InterruptionType(rawValue: raw ?? 0) == .began else { return }
            MainActor.assumeIsolated { self?.dispatch(.audioInterruption) }
        }
        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard AVAudioSession.RouteChangeReason(rawValue: raw ?? 0) == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.dispatch(.routeChange) }
        }
        #endif
    }
}

/// Inert haptics for macOS and unit tests.
@MainActor
final class NoopVoiceHaptics: VoiceHapticsPerforming {
    func perform(_ haptic: VoiceHaptic) {}
}

/// Inert announcer for macOS and unit tests.
@MainActor
final class NoopVoiceAnnouncer: VoiceAnnouncing {
    func announce(_ message: String) {}
}
