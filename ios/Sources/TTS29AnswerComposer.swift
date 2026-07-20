import Foundation
import NMP

/// Builds the tags and write intent for a TTS29 answer event. The event is an
/// ordinary group `kind:9` carrying the answer marker, a root reference to the
/// spoken item, the group `h` tag, and one `answer` tag per question.
enum TTS29AnswerComposer {
    /// The answer tags in canonical order. Only questions with a non-empty
    /// value contribute; single-choice and freeform carry exactly one value.
    static func tags(itemID: String, groupID: String, answers: [TTS29Answer]) -> [[String]] {
        var tags: [[String]] = [
            ["tts29", "answer", "1"],
            ["e", itemID, "", "root"],
            ["h", groupID]
        ]
        for answer in answers where !answer.values.isEmpty {
            tags.append(["answer", answer.questionID] + answer.values)
        }
        return tags
    }

    /// A durable write intent for the answer, or nil when there is nothing to
    /// submit. Published through the generic write path because the group-send
    /// intent cannot carry the answer's custom tags.
    static func intent(
        itemID: String,
        groupID: String,
        questions: [TTS29Question],
        answers: [TTS29Answer],
        activePubkey: String,
        now: UInt64
    ) -> WriteIntent? {
        let bundle = TTS29AnswerBundle(
            eventID: "",
            itemID: itemID,
            author: activePubkey,
            createdAt: now,
            answers: answers
        )
        guard !groupID.isEmpty,
              TTS29ItemParsing.isValidAnswer(bundle, for: questions)
        else { return nil }
        return WriteIntent(
            payload: .unsigned(
                pubkey: activePubkey,
                createdAt: now,
                kind: 9,
                tags: tags(itemID: itemID, groupID: groupID, answers: answers),
                content: ""
            ),
            durability: .durable,
            routing: .authorOutbox
        )
    }
}
