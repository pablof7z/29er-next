import NMP

/// One write's facts, reduced to the single thing a person needs to be told.
///
/// A write is judged on SETTLEMENT, never on the first unhappy frame. NMP's
/// per-relay facts are terminal for one relay and nothing else, so a write
/// that published at one relay and gave up at another is delivered with a
/// footnote, not a failure to report. That is why there is no per-fact
/// `message(for:)` here any more: the old one answered a question about the
/// whole write using evidence about one lane.
///
/// Exactly one `WriteFact.outcome` ends every stream, so a settled write can
/// never end in silence -- the app no longer needs a sentence for "the
/// stream stopped and we do not know why".
struct WriteReport {
    let subject: String
    private var relays: [String: RelayState] = [:]
    private var signerRefusal: String?

    /// The one failure worth showing, or `nil` while the write is still open
    /// or once it ended well.
    private(set) var failure: String?

    init(subject: String) {
        self.subject = subject
    }

    mutating func record(_ fact: WriteFact) {
        switch fact {
        case .signing(.refused(let reason)):
            signerRefusal = reason
        // A write parked on an absent signer is not a failed write, and no
        // clock ever makes it one.
        case .signing(.awaitingSigner), .signing(.signed):
            break
        case .relay(let relay, let state):
            relays[relay] = state
        // The intended relay set is the settlement denominator, not a
        // verdict: `complete` flips on resolution, never on delivery.
        case .destinations:
            break
        case .outcome(let outcome):
            failure = message(for: outcome)
        }
    }

    private func message(for outcome: WriteOutcome) -> String? {
        switch outcome {
        case .settled:
            return relays.values.contains(.published) ? nil : undelivered()
        case .noDestination:
            return """
                There is nowhere to send this \(subject): no relay is configured for it. \
                Add one under Favorite Relays.
                """
        // A later write for the same replaceable coordinate took over, which
        // is what editing twice quickly is supposed to do.
        case .notSent(.superseded):
            return nil
        case .notSent(.cancelled):
            return "The \(subject) was not sent -- the write was cancelled."
        case .refused(let reason):
            return message(for: reason)
        }
    }

    /// The destination set is closed, every relay in it is terminal, and none
    /// of them took the write. Name the most actionable reason rather than
    /// counting relays.
    private func undelivered() -> String {
        if let signerRefusal {
            return "Your signer refused the \(subject): \(signerRefusal)"
        }
        let ordered = relays.sorted { $0.key < $1.key }
        for (relay, state) in ordered {
            if case .rejected(let reason) = state {
                return "\(relay) rejected the \(subject): \(reason)"
            }
        }
        for (relay, state) in ordered {
            if case .authFailed(_, let source, let reason) = state {
                return authFailure(relay: relay, source: source, reason: reason)
            }
        }
        for (relay, state) in ordered {
            if case .waiting(.persistenceStalled(let detail)) = state {
                return "This device could not record the \(subject) for \(relay): \(detail)"
            }
        }
        for (relay, state) in ordered {
            if case .gaveUp = state {
                return "Could not deliver the \(subject) to \(relay)."
            }
        }
        return "The \(subject) reached no relay."
    }

    /// `source` is the whole reason authentication is not folded into a
    /// rejection: this app declining to authenticate must never be shown to
    /// somebody as a relay refusing them.
    private func authFailure(relay: String, source: AuthDenialSource, reason: String) -> String {
        switch source {
        case .policy:
            return "This app did not authenticate to \(relay), so the \(subject) was not sent."
        case .signer:
            return "Your signer could not authenticate to \(relay): \(reason)"
        case .relay:
            return "\(relay) refused to authenticate you: \(reason)"
        }
    }

    private func message(for reason: RefuseReason) -> String {
        switch reason {
        // NMP keeps `expected` and `actual` so a caller can fetch what is
        // actually stored, reapply the change and resubmit. This app does not
        // do that itself: AGENTS.md puts retry on NMP's side of the boundary,
        // so the person decides whether their edit still applies.
        case .replaceableBaseChanged:
            return "The \(subject) changed while this update was in flight. Review it and try again."
        case .alreadyExpired:
            return "The \(subject) had already expired when NMP took it."
        case .tombstoned:
            return "The \(subject) refers to something that has been deleted."
        case .replaceableBaseOnRegularEvent:
            return "The \(subject) named a replaceable base on an event that cannot have one."
        }
    }
}

extension WriteReport {
    /// Drain a settled write's facts and answer with the one failure worth
    /// showing.
    ///
    /// Never called on a path a person is waiting on. `publish` returning is
    /// acceptance, and an accepted write is already in the app's own live
    /// query reporting cache with zero relays, so this only ever reports
    /// something after the fact.
    static func failure<Facts: AsyncSequence & Sendable>(
        draining facts: Facts,
        subject: String
    ) async -> String? where Facts.Element == WriteFact {
        var report = WriteReport(subject: subject)
        do {
            for try await fact in facts {
                report.record(fact)
            }
        } catch is CancellationError {
            return nil
        } catch {
            return error.localizedDescription
        }
        return report.failure
    }
}

/// Text for the two, and only two, ways `publish` itself says no.
enum WriteFailureText {
    /// NMP could not write anything down, or the instruction could not
    /// resolve. Everything else takes custody and fails on the facts stream,
    /// where `WriteReport` reads it.
    static func startFailure(_ error: Error, action: String) -> String {
        switch error as? NMPError {
        case .noActiveSigner:
            return "Sign in to \(action)."
        case .publishRefused(let reason):
            return "NMP would not take the \(action): \(reason)"
        case .engineClosed:
            return "NMP closed before the \(action) could start."
        default:
            return "NMP could not start the \(action)."
        }
    }
}
