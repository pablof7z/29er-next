import NMP

/// The app's one reading of NMP's write vocabulary.
///
/// `WriteStatus` was previously mapped to user text in three places that had
/// drifted apart -- one treated `.cancelled` as a failure, one did not; one
/// reported `.replaceableConflict`, two swallowed it; none of them had been
/// updated for `.superseded`, `.awaitingRoute` or `.authDenied`. Classifying
/// write outcomes is not per-feature policy, so it happens once.
///
/// The switch is exhaustive on purpose: when NMP adds a state, this stops
/// compiling and somebody decides what it means, which is what a `default`
/// arm was quietly preventing.
enum WriteFailureText {
    /// A user-facing failure for a terminal-bad status, or `nil` for anything
    /// that is progress, a retained wait, or success.
    static func message(for status: WriteStatus, subject: String) -> String? {
        switch status {
        case .rejected(_, let reason):
            return "The relay rejected the \(subject): \(reason)"
        case .failed(let reason):
            return reason
        case .gaveUp(let relay):
            return "Could not deliver the \(subject) to \(relay)."
        case .persistenceBlocked(let relay):
            return "Could not persist the \(subject) for \(relay)."
        case .routePersistenceBlocked(let relay):
            return "Could not persist \(subject) routing for \(relay)."
        case .outcomeUnknown(let relay):
            return "The \(subject) delivery outcome for \(relay) is unknown."
        case .authDenied(let relay, _, _, let reason):
            return "\(relay) refused to authenticate this \(subject): \(reason)"
        case .replaceableConflict:
            return "The \(subject) changed while this update was in flight. Review it and try again."
        case .cancelled:
            return "The \(subject) was not sent -- the write was cancelled."

        // Progress and retained waits. `.superseded` means a later write for
        // the same replaceable coordinate took over, which is the intended
        // outcome of editing twice quickly, not a failure to report.
        case .accepted, .superseded, .awaitingCapability, .signed, .awaitingRoute,
             .routed, .awaitingRelay, .awaitingAuth, .retryEligible,
             .handoffAmbiguous, .sent, .acked:
            return nil
        }
    }

    /// A user-facing message for a synchronous refusal from `publish`.
    static func startFailure(_ error: Error, action: String) -> String {
        switch error as? NMPError {
        case .noActiveSigner:
            return "Sign in to \(action)."
        case .engineClosed:
            return "NMP closed before the \(action) could start."
        default:
            return "NMP could not start the \(action)."
        }
    }
}
