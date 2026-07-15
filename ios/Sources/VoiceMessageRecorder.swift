import SwiftUI

#if os(iOS)
@preconcurrency import AVFoundation
import UIKit

@MainActor
final class VoiceMessageRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum Phase: Equatable {
        case idle
        case requestingPermission
        case recording
        case locked
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var samples = Array(repeating: Float.zero, count: 28)
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var completedDraft: CompletedVoiceDraft?
    @Published private(set) var failureMessage: String?

    let store: VoiceDraftStore
    private var audioRecorder: AVAudioRecorder?
    private var displayLink: CADisplayLink?
    private var startedAt: Date?
    private var interruptionReason: String?
    private var pendingEnd: PendingEnd?

    private enum PendingEnd { case send, cancel }

    init(store: VoiceDraftStore) {
        self.store = store
        super.init()
        observeAudioSession()
    }

    deinit {
        displayLink?.invalidate()
    }

    var isActive: Bool {
        switch phase {
        case .requestingPermission, .recording, .locked: true
        case .idle, .failed: false
        }
    }

    var isLocked: Bool { phase == .locked }

    func begin() {
        guard !isActive else { return }
        phase = .requestingPermission
        pendingEnd = nil
        Task { await requestPermissionAndStart() }
    }

    func lock() {
        guard phase == .recording else { return }
        phase = .locked
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func finishAndSend() {
        if phase == .requestingPermission {
            pendingEnd = .send
        } else if phase == .recording || phase == .locked {
            finish(shouldSend: true)
        }
    }

    func cancel() {
        if phase == .requestingPermission {
            pendingEnd = .cancel
            return
        }
        guard let url = audioRecorder?.url else {
            reset()
            return
        }
        audioRecorder?.stop()
        store.remove(url)
        reset()
    }

    func preserveForBackground() {
        guard phase == .recording || phase == .locked else { return }
        interruptionReason = "Recording was safely saved when the app became inactive."
        finish(shouldSend: false)
    }

    func consumeCompletedDraft() {
        completedDraft = nil
        if case .failed = phase { phase = .idle }
        failureMessage = nil
    }

    func recoverPendingAttachments() throws -> [ComposerAttachment] {
        try store.recoverAttachments()
    }

    private func requestPermissionAndStart() async {
        let granted: Bool
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            granted = true
        case .denied:
            granted = false
        case .undetermined:
            granted = await AVAudioApplication.requestRecordPermission()
        @unknown default:
            granted = false
        }
        guard granted else {
            fail("Microphone access is off. Enable it in Settings to record audio.")
            pendingEnd = nil
            return
        }
        do {
            try startRecording()
            switch pendingEnd {
            case .send: finish(shouldSend: true)
            case .cancel: cancel()
            case nil: break
            }
            pendingEnd = nil
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [
            .defaultToSpeaker, .allowBluetoothHFP
        ])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let url = try store.createURL()
        let recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey: 96_000
            ]
        )
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            store.remove(url)
            throw VoiceRecordingError.couldNotStart
        }
        audioRecorder = recorder
        startedAt = Date()
        phase = .recording
        startMetering()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func finish(shouldSend: Bool) {
        guard let recorder = audioRecorder else { return }
        let url = recorder.url
        recorder.stop()
        stopMetering()
        deactivateSession()
        audioRecorder = nil
        guard validDraft(at: url) else {
            store.remove(url)
            fail("No audio was captured. Press and hold the mic to try again.")
            return
        }
        completedDraft = CompletedVoiceDraft(url: url, shouldSend: shouldSend)
        if let interruptionReason {
            fail(interruptionReason)
            self.interruptionReason = nil
        } else {
            phase = .idle
        }
    }

    private func reset() {
        stopMetering()
        deactivateSession()
        audioRecorder = nil
        startedAt = nil
        duration = 0
        level = 0
        samples = Array(repeating: 0, count: 28)
        phase = .idle
    }

    private func startMetering() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(updateMeter))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 12, maximum: 20, preferred: 15)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopMetering() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateMeter() {
        guard let audioRecorder else { return }
        audioRecorder.updateMeters()
        let power = audioRecorder.averagePower(forChannel: 0)
        let normalized = max(0, min(1, pow(10, power / 38)))
        level = normalized
        samples.removeFirst()
        samples.append(normalized)
        duration = Date().timeIntervalSince(startedAt ?? Date())
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard isActive,
              let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        interruptionReason = "Recording was interrupted by the system and safely saved."
        finish(shouldSend: false)
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard isActive,
              let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else {
            return
        }
        interruptionReason = "Recording was safely saved after the microphone changed."
        finish(shouldSend: false)
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.audioRecorder != nil else { return }
            self.interruptionReason = error?.localizedDescription
                ?? "Recording stopped unexpectedly and was safely saved."
            self.finish(shouldSend: false)
        }
    }

    private func validDraft(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return false }
        return (values.fileSize ?? 0) > 0
    }

    private func fail(_ message: String) {
        failureMessage = message
        phase = .failed(message)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

enum VoiceRecordingError: LocalizedError {
    case couldNotStart

    var errorDescription: String? {
        "The microphone could not start recording."
    }
}
#else
@MainActor
final class VoiceMessageRecorder: ObservableObject {
    @Published private(set) var completedDraft: CompletedVoiceDraft?
    @Published private(set) var failureMessage: String?
    let store: VoiceDraftStore
    init(store: VoiceDraftStore) { self.store = store }
    var isActive: Bool { false }
    func preserveForBackground() {}
    func consumeCompletedDraft() { completedDraft = nil }
    func recoverPendingAttachments() throws -> [ComposerAttachment] {
        try store.recoverAttachments()
    }
}
#endif
