import Foundation

/// Turns a `VoiceGestureReading` into a transient `VoiceGesturePhase` under hysteresis,
/// so a natural diagonal thumb drag can neither flip between affordances nor commit one
/// accidentally. Pure and unit-tested independently of the metrics geometry.
enum VoiceGestureResolver {
    static func dragChanged(
        _ state: inout VoiceComposerState,
        _ reading: VoiceGestureReading
    ) -> [VoiceEffect] {
        // Only the finger-held recording state interprets drags. Locked/paused capture
        // is driven by explicit controls, so a stray drag there is inert.
        guard state.isHeldRecording else { return [] }

        let axis = resolvedAxis(current: state.gesture, reading: reading)
        switch axis {
        case .lock:
            // Fully reaching the destination auto-commits the lock while still holding.
            if reading.lockProgress >= 1 {
                return VoiceComposerReducer.commitLock(&state)
            }
            let armed = reading.lockProgress >= state.metrics.armFraction
            let effects = armEffects(armed: armed, wasArmed: state.gesture.isLockArmed, haptic: .lockArmed)
            state.gesture = armed ? .lockArmed : .lockProgress(reading.lockProgress)
            return effects
        case .cancel:
            let armed = reading.cancelProgress >= state.metrics.armFraction
            let effects = armEffects(armed: armed, wasArmed: state.gesture.isCancelArmed, haptic: .cancelArmed)
            state.gesture = armed ? .cancelArmed : .cancelProgress(reading.cancelProgress)
            return effects
        case .neutral:
            state.gesture = .neutral
            return []
        }
    }

    /// Resolve which affordance the drag advances, preserving the engaged axis when the
    /// reading is ambiguous and refusing to switch away from an armed axis until the
    /// finger retreats off it.
    private static func resolvedAxis(
        current: VoiceGesturePhase,
        reading: VoiceGestureReading
    ) -> VoiceGestureAxis {
        // An armed axis holds until the finger fully retreats off it.
        if current.isLockArmed, reading.lockTravel > 0 { return .lock }
        if current.isCancelArmed, reading.cancelTravel > 0 { return .cancel }

        if reading.dominantAxis != .neutral { return reading.dominantAxis }

        // Ambiguous (diagonal or dead zone): keep advancing the already-engaged axis if
        // it still has travel, otherwise fall back to neutral. Never silently switches.
        switch current {
        case .lockProgress, .lockArmed:
            return reading.lockTravel > 0 ? .lock : .neutral
        case .cancelProgress, .cancelArmed:
            return reading.cancelTravel > 0 ? .cancel : .neutral
        default:
            return .neutral
        }
    }

    private static func armEffects(
        armed: Bool,
        wasArmed: Bool,
        haptic: VoiceHaptic
    ) -> [VoiceEffect] {
        armed && !wasArmed ? [.haptic(haptic)] : []
    }
}
