import SwiftUI

/// Pure, testable geometry for the held voice gesture. Constants live here — never
/// inline in a SwiftUI body — so dead-zone handling, dominant-axis hysteresis, and
/// normalized 0→1 progress can be validated without rendering or a microphone.
///
/// Distances are measured on a physical device and tuned there; the defaults are a
/// deliberate starting point (see the PR for rationale), not authoritative pixel law.
struct VoiceGestureMetrics: Equatable, Sendable {
    /// Movement below this (points, per axis) is treated as noise and yields zero progress.
    var deadZone: CGFloat = 12
    /// Upward travel, past the dead zone, that fully commits the lock (progress 1.0).
    var lockCommitTravel: CGFloat = 96
    /// Leading travel, past the dead zone, that fully arms cancellation (progress 1.0).
    var cancelCommitTravel: CGFloat = 130
    /// Fraction of travel at which an axis becomes "armed" (one haptic, shape change).
    var armFraction: Double = 0.82
    /// One axis is only dominant when it exceeds the other by this factor; otherwise the
    /// reading is neutral so a natural diagonal thumb drag cannot silently commit either.
    var axisDominanceRatio: CGFloat = 1.35
    /// Recordings shorter than this (active seconds) are discarded quietly, never sent.
    var minimumDuration: TimeInterval = 0.6
    /// Hard ceiling; capture finalizes into a reviewable draft before crossing it.
    var maximumDuration: TimeInterval = 300

    static let `default` = VoiceGestureMetrics()

    /// Interpret a raw drag translation into normalized affordance progress.
    ///
    /// - Parameters:
    ///   - translation: SwiftUI drag translation (`+x` trailing, `+y` down).
    ///   - layoutDirection: cancel tracks the *leading* edge, so RTL flips the x sign.
    func reading(
        translation: CGSize,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> VoiceGestureReading {
        let up = max(0, -translation.height)
        let leadingRaw = layoutDirection == .rightToLeft ? translation.width : -translation.width
        let leading = max(0, leadingRaw)

        let upTravel = max(0, up - deadZone)
        let leadTravel = max(0, leading - deadZone)

        let lockProgress = min(1, Double(upTravel / lockCommitTravel))
        let cancelProgress = min(1, Double(leadTravel / cancelCommitTravel))

        let axis: VoiceGestureAxis
        if upTravel <= 0, leadTravel <= 0 {
            axis = .neutral
        } else if upTravel >= leadTravel * axisDominanceRatio {
            axis = .lock
        } else if leadTravel >= upTravel * axisDominanceRatio {
            axis = .cancel
        } else {
            axis = .neutral
        }

        return VoiceGestureReading(
            dominantAxis: axis,
            lockProgress: lockProgress,
            cancelProgress: cancelProgress,
            lockTravel: upTravel,
            cancelTravel: leadTravel
        )
    }
}

/// Which affordance a drag is advancing. `.neutral` covers both "inside the dead zone"
/// and "ambiguous diagonal", the two cases that must never commit an action.
enum VoiceGestureAxis: Equatable, Sendable {
    case neutral
    case lock
    case cancel
}

/// A single interpreted drag sample. Progress is clamped 0…1; travel is post-dead-zone
/// points, retained so the reducer can apply axis hysteresis.
struct VoiceGestureReading: Equatable, Sendable {
    var dominantAxis: VoiceGestureAxis
    var lockProgress: Double
    var cancelProgress: Double
    var lockTravel: CGFloat
    var cancelTravel: CGFloat

    static let neutral = VoiceGestureReading(
        dominantAxis: .neutral,
        lockProgress: 0,
        cancelProgress: 0,
        lockTravel: 0,
        cancelTravel: 0
    )
}
