import XCTest
@testable import TwentyNinerNext

/// Coordinator tests use a fake recorder engine, so pause/resume duration accounting and
/// the "one logical recording" guarantee are verified without a microphone.
@MainActor
final class VoiceComposerCoordinatorTests: XCTestCase {
    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeCoordinator(
        engine: VoiceRecorderEngine,
        permission: VoiceMicPermission = .granted
    ) -> VoiceComposerCoordinator {
        VoiceComposerCoordinator(
            store: VoiceDraftStore(scope: "coordinator-test", rootDirectory: tempRoot()),
            engine: engine,
            authority: FixedMicrophoneAuthority(status: permission),
            haptics: NoopVoiceHaptics(),
            announcer: NoopVoiceAnnouncer()
        )
    }

    // 20 + 19. Resume continues the same recording (no restart) and the finalized duration
    // is the engine's active-only duration, never paused wall-clock.
    func testResumeContinuesSameRecordingWithActiveDuration() {
        let engine = FakeRecorderEngine()
        engine.stopDuration = 3.5 // active seconds the engine reports (excludes pause)
        let coordinator = makeCoordinator(engine: engine)

        coordinator.pressBegan()
        XCTAssertEqual(engine.startCount, 1)
        coordinator.lock()
        engine.emit(0.6, 2.0)
        coordinator.pause()
        XCTAssertEqual(engine.pauseCount, 1)
        coordinator.resume()
        XCTAssertEqual(engine.resumeCount, 1)
        XCTAssertEqual(engine.startCount, 1, "resume must not restart capture")

        coordinator.send()
        XCTAssertEqual(coordinator.state.publishingDraft?.duration, 3.5)
    }

    // 30. Starting a second recording clears prior duration + waveform telemetry.
    func testSecondRecordingHasCleanTelemetry() {
        let engine = FakeRecorderEngine()
        let coordinator = makeCoordinator(engine: engine)
        coordinator.pressBegan()
        engine.emit(0.9, 5.0)
        XCTAssertGreaterThan(coordinator.state.elapsed, 0)
        coordinator.cancel()

        coordinator.pressBegan()
        XCTAssertEqual(coordinator.state.elapsed, 0)
        XCTAssertTrue(coordinator.state.waveform.isEmpty)
    }

    // 18. Pausing stops metering (fake never delivers, but the reducer also freezes).
    func testPauseFreezesElapsedInCoordinator() {
        let engine = FakeRecorderEngine()
        let coordinator = makeCoordinator(engine: engine)
        coordinator.pressBegan()
        coordinator.lock()
        engine.emit(0.5, 4.0)
        let frozen = coordinator.state.elapsed
        coordinator.pause()
        engine.emit(0.5, 8.0)
        XCTAssertEqual(coordinator.state.elapsed, frozen)
    }
}

/// Deterministic stand-in for `AVVoiceRecorderEngine`.
@MainActor
final class FakeRecorderEngine: VoiceRecorderEngine {
    var onSample: ((Float, TimeInterval) -> Void)?
    private(set) var startCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    var stopDuration: TimeInterval = 1.0
    private var url: URL?

    func start(url: URL) throws {
        startCount += 1
        self.url = url
    }

    func pause() { pauseCount += 1 }
    func resume() { resumeCount += 1 }

    func stop(deliver: Bool) -> VoiceStopResult? {
        stopCount += 1
        guard deliver, let url else { return nil }
        return VoiceStopResult(url: url, duration: stopDuration)
    }

    func emit(_ level: Float, _ duration: TimeInterval) {
        onSample?(level, duration)
    }
}
