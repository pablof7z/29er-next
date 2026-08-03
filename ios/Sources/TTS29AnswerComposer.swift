import Foundation
import NMP

/// Builds the tags for a TTS29 answer event. The event is an ordinary group
/// `kind:9` carrying the answer marker, a root reference to the spoken item,
/// and one `answer` tag per question.
enum TTS29AnswerComposer {
    /// The answer tags in canonical order. Only questions with a non-empty
    /// value contribute; single-choice and freeform carry exactly one value.
    ///
    /// No `h` row: `NMPGroup.publish` appends exactly one, before the
    /// stamp/sign step, so the context tag is inside the signed bytes. An
    /// app-supplied `h` here would be a duplicate and a typed refusal.
    static func tags(itemID: String, answers: [TTS29Answer]) -> [[String]] {
        var tags: [[String]] = [
            ["tts29", "answer", "1"],
            ["e", itemID, "", "root"]
        ]
        for answer in answers where !answer.values.isEmpty {
            tags.append(["answer", answer.questionID] + answer.values)
        }
        return tags
    }

    /// Whether this answer bundle is submittable at all.
    ///
    /// `TTS29ItemParsing.isValidAnswer` reads only the answers and the
    /// question definitions, so nothing else needs to be passed in.
    static func isSubmittable(
        groupID: String,
        questions: [TTS29Question],
        answers: [TTS29Answer]
    ) -> Bool {
        let bundle = TTS29AnswerBundle(
            eventID: "",
            itemID: "",
            author: "",
            createdAt: 0,
            answers: answers
        )
        return !groupID.isEmpty && TTS29ItemParsing.isValidAnswer(bundle, for: questions)
    }
}
