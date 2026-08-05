import Foundation
import NMP

enum TTS29AnswerState: Equatable {
    case idle
    case submitted
    case failed(String)

    var failureMessage: String? { if case .failed(let message) = self { message } else { nil } }
}

extension TTS29PlaybackController {
    /// Compose and publish an answer bundle for a spoken item's questions.
    ///
    /// The event is a spec-compliant TTS29 answer `kind:9` with the answer
    /// marker, root reference, and one `answer` tag per question, published
    /// through NMP's NIP-29 publication gate. NMP owns the `h` row, the
    /// routing to the group's host, signing, and the receipt; this method
    /// only reports the outcome.
    ///
    /// The answer is submitted the moment NMP takes it -- `publish` returning
    /// IS acceptance -- so there is no submitting state to sit in and no
    /// stream to drain before the sheet can move on. A write that later
    /// settles badly flips the state to `.failed` where the reader can see
    /// it.
    func submitAnswer(for item: TTS29Item, answers: [TTS29Answer]) {
        guard let activePubkey = context.activePubkey else {
            answerState = .failed("Sign in to answer.")
            return
        }
        guard let engine = currentEngine else {
            answerState = .failed("The engine is unavailable.")
            return
        }
        let groupID = item.groupID.isEmpty ? context.groupID : item.groupID
        guard TTS29AnswerComposer.isSubmittable(
            groupID: groupID,
            questions: item.questions,
            answers: answers
        ) else {
            answerState = .failed("Choose an answer first.")
            return
        }

        do {
            let facts = try roomGroup(host: context.host, groupID: groupID).publish(
                engine: engine,
                authorPubkeyHex: activePubkey,
                kind: RoomKind.chat,
                tags: TTS29AnswerComposer.tags(itemID: item.id, answers: answers),
                content: ""
            )
            answerState = .submitted
            Task { [weak self] in
                guard let failure = await WriteReport.failure(draining: facts, subject: "answer"),
                      let self, !Task.isCancelled else { return }
                self.answerState = .failed(failure)
            }
        } catch {
            answerState = .failed(WriteFailureText.startFailure(error, action: "answer"))
        }
    }
}
