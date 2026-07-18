import SwiftUI
import XCTest
@testable import TwentyNinerNext

/// Geometry is pure, so dead-zone handling, normalized progress, dominant-axis selection,
/// and RTL mapping are validated here with no rendering and no microphone.
final class VoiceGestureMetricsTests: XCTestCase {
    private let metrics = VoiceGestureMetrics.default

    func testMovementInsideDeadZoneYieldsNoProgress() {
        let reading = metrics.reading(translation: CGSize(width: -8, height: -10))
        XCTAssertEqual(reading.lockProgress, 0)
        XCTAssertEqual(reading.cancelProgress, 0)
        XCTAssertEqual(reading.dominantAxis, .neutral)
    }

    func testUpwardDragProducesNormalizedLockProgress() {
        // 60 up − 12 dead zone = 48 of 96 travel → 0.5.
        let reading = metrics.reading(translation: CGSize(width: 0, height: -60))
        XCTAssertEqual(reading.dominantAxis, .lock)
        XCTAssertEqual(reading.lockProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(reading.cancelProgress, 0)
    }

    func testLeadingDragProducesNormalizedCancelProgressLTR() {
        // 70 left − 12 dead zone = 58 of 130 travel.
        let reading = metrics.reading(translation: CGSize(width: -70, height: 0))
        XCTAssertEqual(reading.dominantAxis, .cancel)
        XCTAssertEqual(reading.cancelProgress, 58.0 / 130.0, accuracy: 0.001)
        XCTAssertEqual(reading.lockProgress, 0)
    }

    func testCancelTracksLeadingEdgeUnderRightToLeft() {
        let reading = metrics.reading(
            translation: CGSize(width: 70, height: 0),
            layoutDirection: .rightToLeft
        )
        XCTAssertEqual(reading.dominantAxis, .cancel)
        XCTAssertGreaterThan(reading.cancelProgress, 0)
    }

    func testProgressIsClampedToOne() {
        let reading = metrics.reading(translation: CGSize(width: 0, height: -500))
        XCTAssertEqual(reading.lockProgress, 1)
    }

    func testAmbiguousDiagonalIsNeutralSoNeitherActionCommits() {
        let reading = metrics.reading(translation: CGSize(width: -60, height: -60))
        XCTAssertEqual(reading.dominantAxis, .neutral)
        XCTAssertGreaterThan(reading.lockProgress, 0)
        XCTAssertGreaterThan(reading.cancelProgress, 0)
    }

    func testClearlyVerticalDiagonalResolvesToLock() {
        // Up dominates left beyond the 1.35 ratio.
        let reading = metrics.reading(translation: CGSize(width: -20, height: -110))
        XCTAssertEqual(reading.dominantAxis, .lock)
    }
}
