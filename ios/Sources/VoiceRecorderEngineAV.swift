#if os(iOS)
@preconcurrency import AVFoundation
import UIKit

/// AVFoundation-backed capture. Pause/resume use `AVAudioRecorder.pause()` + `record()`
/// on a single file, and active duration comes from `recorder.currentTime`, which does
/// not advance while paused — so paused wall-clock is never counted or stored.
@MainActor
final class AVVoiceRecorderEngine: NSObject, VoiceRecorderEngine, AVAudioRecorderDelegate {
    var onSample: ((Float, TimeInterval) -> Void)?

    private var recorder: AVAudioRecorder?
    private var displayLink: CADisplayLink?

    func start(url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 96_000
        ])
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw VoiceRecorderEngineError.couldNotStart
        }
        self.recorder = recorder
        startMetering()
    }

    func pause() {
        recorder?.pause()
        stopMetering()
    }

    func resume() {
        guard let recorder, recorder.record() else { return }
        startMetering()
    }

    func stop(deliver: Bool) -> VoiceStopResult? {
        stopMetering()
        guard let recorder else {
            deactivateSession()
            return nil
        }
        let url = recorder.url
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        deactivateSession()
        guard deliver else { return nil }
        return VoiceStopResult(url: url, duration: duration)
    }

    // MARK: Metering

    private func startMetering() {
        stopMetering()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 12, maximum: 20, preferred: 15)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopMetering() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard let recorder else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let normalized = max(0, min(1, pow(10, power / 38)))
        onSample?(normalized, recorder.currentTime)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        // Encode errors surface through the coordinator's finish path; nothing to do here.
    }
}

enum VoiceRecorderEngineError: LocalizedError {
    case couldNotStart
    var errorDescription: String? { "The microphone could not start recording." }
}

/// Live microphone authorization backed by `AVAudioApplication`.
@MainActor
final class SystemMicrophoneAuthority: MicrophoneAuthority {
    var status: VoiceMicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .undetermined
        @unknown default: .denied
        }
    }

    func request() async -> VoiceMicPermission {
        await AVAudioApplication.requestRecordPermission() ? .granted : .denied
    }
}

/// UIKit haptics — one generator prepared per boundary, fired once.
@MainActor
final class SystemVoiceHaptics: VoiceHapticsPerforming {
    func perform(_ haptic: VoiceHaptic) {
        switch haptic {
        case .recordingStart, .resume:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .lockArmed, .cancelArmed, .pause:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .lockCommitted:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .cancelCommitted, .discard:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .failure:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .sent:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

/// VoiceOver announcements via UIAccessibility.
@MainActor
final class SystemVoiceAnnouncer: VoiceAnnouncing {
    func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
#endif
