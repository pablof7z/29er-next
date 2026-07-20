import Foundation
import NMP

enum TTS29AnswerState: Equatable {
    case idle
    case submitting
    case submitted
    case failed(String)

    var isSubmitting: Bool { if case .submitting = self { true } else { false } }
    var failureMessage: String? { if case .failed(let message) = self { message } else { nil } }
}

extension TTS29PlaybackController {
    /// Compose and publish an answer bundle for a spoken item's questions.
    ///
    /// The event is a spec-compliant TTS29 answer `kind:9` with the answer
    /// marker, root reference, group `h` tag, and one `answer` tag per
    /// question. It is published through NMP's generic write path because the
    /// group-send intent cannot carry custom tags. NMP owns signing, routing,
    /// and the receipt; this method only reports the outcome.
    func submitAnswer(for item: TTS29Item, answers: [TTS29Answer]) async {
        guard let activePubkey = context.activePubkey else {
            answerState = .failed("Sign in to answer.")
            return
        }
        guard let engine = currentEngine else {
            answerState = .failed("The engine is unavailable.")
            return
        }
        guard let intent = TTS29AnswerComposer.intent(
            itemID: item.id,
            groupID: item.groupID.isEmpty ? context.groupID : item.groupID,
            questions: item.questions,
            answers: answers,
            activePubkey: activePubkey,
            now: UInt64(Date().timeIntervalSince1970)
        ) else {
            answerState = .failed("Choose an answer first.")
            return
        }

        answerState = .submitting
        do {
            let receipt = try await engine.publish(intent)
            var failure: String?
            for await status in receipt.status {
                if let message = Self.failureMessage(for: status) { failure = message }
            }
            answerState = failure.map(TTS29AnswerState.failed) ?? .submitted
        } catch {
            answerState = .failed(Self.publishFailureMessage(error))
        }
    }

    private static func failureMessage(for status: WriteStatus) -> String? {
        switch status {
        case .rejected(_, let reason): "The relay rejected the answer: \(reason)"
        case .gaveUp: "NMP could not deliver the answer to the group relay."
        case .persistenceBlocked, .routePersistenceBlocked: "The answer could not be persisted."
        case .outcomeUnknown: "The answer delivery outcome is unknown."
        case .failed(let reason): "NMP could not publish the answer: \(reason)"
        default: nil
        }
    }

    private static func publishFailureMessage(_ error: Error) -> String {
        switch error as? NMPError {
        case .noActiveAccount, .noActiveSigner: "Sign in to answer."
        case .engineClosed: "The engine closed before the answer could be sent."
        default: "NMP could not start the answer publish."
        }
    }
}
