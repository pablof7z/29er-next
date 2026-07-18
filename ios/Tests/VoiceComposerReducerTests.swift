import SwiftUI
import XCTest
@testable import TwentyNinerNext

/// Exercises the full transition system deterministically: no SwiftUI, no AVFoundation,
/// no microphone. Each test maps to a required behavior from the rework spec.
final class VoiceComposerReducerTests: XCTestCase {
    private let metrics = VoiceGestureMetrics.default
    private let draft = VoiceDraft(url: URL(fileURLWithPath: "/tmp/voice.m4a"), duration: 2, waveform: [])
    private let shortDraft = VoiceDraft(url: URL(fileURLWithPath: "/tmp/short.m4a"), duration: 0.2, waveform: [])

    @discardableResult
    private func reduce(_ state: inout VoiceComposerState, _ event: VoiceEvent) -> [VoiceEffect] {
        VoiceComposerReducer.reduce(&state, event)
    }

    private func recording(_ permission: VoiceMicPermission = .granted) -> VoiceComposerState {
        var state = VoiceComposerState(permission: permission)
        reduce(&state, .touchBegan)
        return state
    }

    private func lockedRecording() -> VoiceComposerState {
        var state = recording()
        reduce(&state, .lockCommitted)
        return state
    }

    // 1. Authorized press starts recording.
    func testAuthorizedPressStartsRecording() {
        var state = VoiceComposerState(permission: .granted)
        let effects = reduce(&state, .touchBegan)
        XCTAssertEqual(state.capture, .recording)
        XCTAssertEqual(state.mode, .held)
        XCTAssertTrue(effects.contains(.startRecorder))
        XCTAssertTrue(effects.contains(.haptic(.recordingStart)))
    }

    // 2 + 3. Neutral release finalizes to send exactly once; sub-minimum never sends.
    func testNeutralReleaseFinalizesSendOnce() {
        var state = recording()
        let ended = reduce(&state, .touchEnded)
        XCTAssertEqual(state.capture, .finalizing(.send))
        XCTAssertEqual(ended, [.stopRecorder(deliver: true)])

        let finished = reduce(&state, .recorderFinished(draft))
        XCTAssertEqual(state.capture, .publishing(draft))
        XCTAssertEqual(finished, [.publish(draft)])
    }

    func testSubMinimumRecordingNeverSends() {
        var state = recording()
        reduce(&state, .touchEnded)
        let finished = reduce(&state, .recorderFinished(shortDraft))
        XCTAssertEqual(state.capture, .idle)
        XCTAssertTrue(finished.contains(.deleteDraft))
        XCTAssertFalse(finished.contains(.publish(shortDraft)))
    }

    // 4 + 5. Upward drag exposes progressive lock values; retreat returns toward neutral.
    func testUpwardDragExposesProgressiveLockThenRetreats() {
        var state = recording()
        reduce(&state, .dragChanged(metrics.reading(translation: CGSize(width: 0, height: -30))))
        guard case .lockProgress(let mid) = state.gesture else { return XCTFail("expected lock progress") }
        XCTAssertGreaterThan(mid, 0)

        reduce(&state, .dragChanged(metrics.reading(translation: CGSize(width: 0, height: -60))))
        guard case .lockProgress(let higher) = state.gesture else { return XCTFail("expected lock progress") }
        XCTAssertGreaterThan(higher, mid)

        reduce(&state, .dragChanged(metrics.reading(translation: .zero)))
        XCTAssertEqual(state.gesture, .neutral)
    }

    // 6 + 7. Lock arms then commits at threshold; release after lock does not send.
    func testLockArmsThenCommitsAndReleaseDoesNotSend() {
        var state = recording()
        reduce(&state, .dragChanged(metrics.reading(translation: CGSize(width: 0, height: -95))))
        XCTAssertEqual(state.gesture, .lockArmed)

        let commit = reduce(&state, .dragChanged(metrics.reading(translation: CGSize(width: 0, height: -140))))
        XCTAssertEqual(state.mode, .locked)
        XCTAssertEqual(state.capture, .recording)
        XCTAssertTrue(commit.contains(.haptic(.lockCommitted)))

        let ended = reduce(&state, .touchEnded)
        XCTAssertEqual(state.capture, .recording)
        XCTAssertEqual(state.mode, .locked)
        XCTAssertFalse(ended.contains(.stopRecorder(deliver: true)))
    }

    // 8. Locked delete discards and never submits.
    func testLockedDeleteDiscardsWithoutSubmit() {
        var state = lockedRecording()
        let effects = reduce(&state, .discard)
        XCTAssertEqual(state.capture, .idle)
        XCTAssertTrue(effects.contains(.stopRecorder(deliver: false)))
        XCTAssertTrue(effects.contains(.deleteDraft))
        XCTAssertFalse(effects.contains { if case .publish = $0 { return true } else { return false } })
    }

    // 9 + 10 + 11. Leading drag exposes cancel progress; arms at threshold; retreat unarms.
    func testCancelProgressArmsAndUnarms() {
        var state = recording()
        reduce(&state, .dragChanged(metrics.reading(translation: CGSize(width: -40, height: 0))))
        guard case .cancelProgress = state.gesture else { return XCTFail("expected cancel progress") }

        reduce(&state, .dragChanged(metrics.reading(translation: CGSize(width: -140, height: 0))))
        XCTAssertEqual(state.gesture, .cancelArmed)

        reduce(&state, .dragChanged(metrics.reading(translation: CGSize(width: -30, height: 0))))
        XCTAssertNotEqual(state.gesture, .cancelArmed)
    }

    // 12. Release while cancel armed deletes and never emits a draft/send.
    func testReleaseWhileCancelArmedDeletes() {
        var state = recording()
        reduce(&state, .dragChanged(metrics.reading(translation: CGSize(width: -140, height: 0))))
        XCTAssertEqual(state.gesture, .cancelArmed)
        let ended = reduce(&state, .touchEnded)
        XCTAssertEqual(state.capture, .idle)
        XCTAssertTrue(ended.contains(.deleteDraft))
        XCTAssertFalse(ended.contains(.stopRecorder(deliver: true)))
    }

    // 13. Diagonal movement does not trap: ambiguous stays neutral, never commits.
    func testDiagonalDoesNotCommitEitherAction() {
        var state = recording()
        reduce(&state, .dragChanged(metrics.reading(translation: CGSize(width: -60, height: -60))))
        XCTAssertEqual(state.gesture, .neutral)
        XCTAssertEqual(state.mode, .held)
        XCTAssertEqual(state.capture, .recording)
    }

    // 14. System gesture cancellation never sends (preserved by locking).
    func testSystemCancellationPreservesWithoutSending() {
        var state = recording()
        let effects = reduce(&state, .gestureCancelled)
        XCTAssertEqual(state.mode, .locked)
        XCTAssertEqual(state.capture, .recording)
        XCTAssertFalse(effects.contains(.stopRecorder(deliver: true)))
    }

    // 15 + 16. Permission request + release cannot queue a send; grant needs a fresh gesture.
    func testPermissionRequestAndReleaseCannotQueueSend() {
        var state = VoiceComposerState(permission: .undetermined)
        let began = reduce(&state, .touchBegan)
        XCTAssertEqual(state.capture, .requestingPermission)
        XCTAssertEqual(began, [.requestPermission])
        XCTAssertFalse(began.contains(.startRecorder))

        let ended = reduce(&state, .touchEnded)
        XCTAssertTrue(ended.isEmpty)

        let granted = reduce(&state, .permissionGranted)
        XCTAssertEqual(state.capture, .idle)
        XCTAssertFalse(granted.contains(.startRecorder))
        XCTAssertFalse(granted.contains { if case .publish = $0 { return true } else { return false } })
    }

    func testGrantThenFreshPressStartsRecording() {
        var state = VoiceComposerState(permission: .undetermined)
        reduce(&state, .touchBegan)
        reduce(&state, .permissionGranted)
        let effects = reduce(&state, .touchBegan)
        XCTAssertEqual(state.capture, .recording)
        XCTAssertTrue(effects.contains(.startRecorder))
    }

    // 17. Permission denial exposes a recoverable state.
    func testPermissionDenialIsRecoverable() {
        var state = VoiceComposerState(permission: .undetermined)
        reduce(&state, .touchBegan)
        reduce(&state, .permissionDenied)
        XCTAssertEqual(state.failure, .permissionDenied)
        XCTAssertEqual(state.failure?.isPermissionDenied, true)
    }

    // 21 + 22 + 23. Send finalizes once from recording or paused; repeats can't duplicate.
    func testSendWhileLockedRecordingFinalizesOnce() {
        var state = lockedRecording()
        let first = reduce(&state, .send)
        XCTAssertEqual(state.capture, .finalizing(.send))
        XCTAssertEqual(first, [.stopRecorder(deliver: true)])
        let second = reduce(&state, .send)
        XCTAssertTrue(second.isEmpty)
    }

    func testSendWhilePausedFinalizesOnce() {
        var state = lockedRecording()
        reduce(&state, .pause)
        XCTAssertEqual(state.capture, .paused)
        let effects = reduce(&state, .send)
        XCTAssertEqual(state.capture, .finalizing(.send))
        XCTAssertEqual(effects, [.stopRecorder(deliver: true)])
    }

    func testRepeatedSendWhilePublishingDoesNotDuplicate() {
        var state = lockedRecording()
        reduce(&state, .send)
        reduce(&state, .recorderFinished(draft))
        XCTAssertEqual(state.capture, .publishing(draft))
        let again = reduce(&state, .send)
        XCTAssertTrue(again.isEmpty)
    }

    // 24 + 25 + 26. Interruption / route / background preserve an unsent draft, never send.
    func testSystemEventsPreserveUnsentDraft() {
        for event in [VoiceEvent.audioInterruption, .routeChange, .appBackgrounded] {
            var state = lockedRecording()
            let effects = reduce(&state, event)
            XCTAssertEqual(state.capture, .finalizing(.review), "\(event)")
            XCTAssertEqual(effects, [.stopRecorder(deliver: true)], "\(event)")
            let finished = reduce(&state, .recorderFinished(draft))
            XCTAssertEqual(state.capture, .review(draft), "\(event)")
            XCTAssertFalse(finished.contains(.publish(draft)), "\(event)")
        }
    }

    // 27 + 28. Upload / publish failure retains the draft and exposes retry.
    func testPublishFailureRetainsDraftForRetry() {
        for event in [VoiceEvent.uploadFailed("net"), .publishFailed("relay")] {
            var state = lockedRecording()
            reduce(&state, .send)
            reduce(&state, .recorderFinished(draft))
            reduce(&state, event)
            XCTAssertEqual(state.failure?.draft, draft, "\(event)")
            let retry = reduce(&state, .send)
            XCTAssertEqual(state.capture, .publishing(draft), "\(event)")
            XCTAssertEqual(retry, [.publish(draft)], "\(event)")
        }
    }

    // 29. Successful canonical send removes the local draft.
    func testSuccessfulSendRemovesLocalDraft() {
        var state = lockedRecording()
        reduce(&state, .send)
        reduce(&state, .recorderFinished(draft))
        let effects = reduce(&state, .sendSucceeded)
        XCTAssertEqual(state.capture, .idle)
        XCTAssertTrue(effects.contains(.deleteDraft))
    }

    // 30. A second recording starts with clean telemetry.
    func testSecondRecordingResetsTelemetry() {
        var state = lockedRecording()
        reduce(&state, .tick(4))
        reduce(&state, .meter(0.9))
        reduce(&state, .send)
        reduce(&state, .recorderFinished(draft))
        reduce(&state, .sendSucceeded)
        XCTAssertEqual(state.elapsed, 0)
        XCTAssertTrue(state.waveform.isEmpty)

        reduce(&state, .touchBegan)
        XCTAssertEqual(state.elapsed, 0)
        XCTAssertTrue(state.waveform.isEmpty)
    }

    // 32. Recovered drafts surface through the voice-specific review state.
    func testRecoveredDraftEntersReview() {
        var state = VoiceComposerState(permission: .granted)
        let effects = reduce(&state, .recoveredDraft(draft))
        XCTAssertEqual(state.capture, .review(draft))
        XCTAssertFalse(effects.contains { if case .publish = $0 { return true } else { return false } })
    }

    // 33. Maximum duration preserves captured audio by finalizing for review.
    func testMaximumDurationFinalizesForReview() {
        var state = lockedRecording()
        let effects = reduce(&state, .tick(metrics.maximumDuration + 1))
        XCTAssertEqual(state.capture, .finalizing(.review))
        XCTAssertTrue(effects.contains(.stopRecorder(deliver: true)))
    }

    // 18. Pause freezes active duration and metering (reducer ignores telemetry when paused).
    func testPauseFreezesTelemetry() {
        var state = lockedRecording()
        reduce(&state, .tick(3))
        reduce(&state, .meter(0.5))
        let frozenElapsed = state.elapsed
        let frozenWaveform = state.waveform
        reduce(&state, .pause)
        reduce(&state, .tick(9))
        reduce(&state, .meter(0.9))
        XCTAssertEqual(state.elapsed, frozenElapsed)
        XCTAssertEqual(state.waveform, frozenWaveform)
    }
}
