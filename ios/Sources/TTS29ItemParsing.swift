import Foundation
import NMP

/// Parses TTS29 tags out of the `kind:9` events the channel already delivers.
/// Pure presentation: no network, no signing, no protocol validation beyond
/// the shape the spoken-item projection needs. Malformed tags are dropped
/// rather than failing the whole parse, so real relay data renders resiliently.
enum TTS29ItemParsing {
    static let marker = "tts29"
    static let itemType = "item"
    static let answerType = "answer"
    static let version = "1"
    static let maxAttachments = 8
    static let maxQuestions = 3
    static let maxOptions = 8

    /// A parsed item without its narrated children attached. Returns nil for
    /// ordinary chat messages and events missing the item marker.
    static func item(from row: Row) -> TTS29Item? {
        guard row.kind == 9, hasMarker(row.tags, type: itemType) else { return nil }
        guard let title = firstValue("title", in: row.tags)?.nonEmpty else { return nil }

        return TTS29Item(
            id: row.id,
            author: row.pubkey,
            createdAt: row.createdAt,
            groupID: firstValue("h", in: row.tags) ?? "",
            agentName: firstValue("agent", in: row.tags) ?? "",
            title: title,
            summary: firstValue("summary", in: row.tags)?.nonEmpty,
            body: row.content,
            audio: audioArtifact(in: row.tags),
            attachments: attachments(in: row.tags),
            questions: questions(in: row.tags),
            parentID: attachParentID(in: row.tags),
            children: []
        )
    }

    /// A parsed answer bundle, or nil for anything that is not a well-formed
    /// TTS29 answer event.
    static func answerBundle(from row: Row) -> TTS29AnswerBundle? {
        guard row.kind == 9, hasMarker(row.tags, type: answerType) else { return nil }
        guard let itemID = rootReference(in: row.tags) else { return nil }
        let answers = row.tags.compactMap { tag -> TTS29Answer? in
            guard tag.count >= 3, tag[0] == "answer",
                  isValidID(tag[1]) else { return nil }
            let values = Array(tag.dropFirst(2)).filter { !$0.isEmpty }
            guard !values.isEmpty else { return nil }
            return TTS29Answer(questionID: tag[1], values: values)
        }
        guard !answers.isEmpty else { return nil }
        return TTS29AnswerBundle(
            eventID: row.id,
            itemID: itemID,
            author: row.pubkey,
            createdAt: row.createdAt,
            answers: answers
        )
    }

    /// The item id this row references as a narrated child, from an
    /// `["e", parentID, "", "attach"]` edge of exactly four elements.
    static func attachParentID(in tags: [[String]]) -> String? {
        for tag in tags where tag.count == 4 && tag[0] == "e" && tag[3] == "attach" {
            let parent = tag[1]
            if !parent.isEmpty { return parent }
        }
        return nil
    }

    // MARK: - Tag scanning

    private static func hasMarker(_ tags: [[String]], type: String) -> Bool {
        tags.contains { $0.count >= 3 && $0[0] == marker && $0[1] == type && $0[2] == version }
    }

    private static func firstValue(_ name: String, in tags: [[String]]) -> String? {
        tags.first { $0.count >= 2 && $0[0] == name }?[1]
    }

    private static func rootReference(in tags: [[String]]) -> String? {
        for tag in tags where tag.count >= 4 && tag[0] == "e" && tag[3] == "root" {
            if !tag[1].isEmpty { return tag[1] }
        }
        return nil
    }

    private static func audioArtifact(in tags: [[String]]) -> TTS29Artifact? {
        guard let tag = tags.first(where: { $0.count >= 5 && $0[0] == "audio" }) else { return nil }
        return artifact(from: tag, labelIndex: nil)
    }

    private static func attachments(in tags: [[String]]) -> [TTS29Artifact] {
        var result: [TTS29Artifact] = []
        for tag in tags where tag.count >= 5 && tag[0] == "attachment" {
            if let artifact = artifact(from: tag, labelIndex: 5) {
                result.append(artifact)
            }
            if result.count >= maxAttachments { break }
        }
        return result
    }

    private static func artifact(from tag: [String], labelIndex: Int?) -> TTS29Artifact? {
        let url = tag[1]
        guard !url.isEmpty else { return nil }
        let label = labelIndex.flatMap { tag.count > $0 ? tag[$0].nonEmpty : nil }
        return TTS29Artifact(
            url: url,
            sha256: tag[2],
            mediaType: tag[3],
            byteCount: UInt64(tag[4]) ?? 0,
            label: label
        )
    }

    private static func questions(in tags: [[String]]) -> [TTS29Question] {
        var result: [TTS29Question] = []
        for tag in tags where tag.count >= 4 && tag[0] == "question" {
            let qid = tag[1]
            guard isValidID(qid),
                  let kind = TTS29QuestionKind(rawValue: tag[2]),
                  let questionTitle = tag[3].nonEmpty,
                  !result.contains(where: { $0.id == qid }) else { continue }

            let options = kind == .freeform ? [] : options(for: qid, in: tags)
            result.append(
                TTS29Question(
                    id: qid,
                    kind: kind,
                    title: questionTitle,
                    shortTitle: firstValue("label", forID: qid, in: tags) ?? questionTitle,
                    description: firstValue("description", forID: qid, in: tags),
                    options: options
                )
            )
            if result.count >= maxQuestions { break }
        }
        return result
    }

    private static func options(for qid: String, in tags: [[String]]) -> [TTS29QuestionOption] {
        var result: [TTS29QuestionOption] = []
        for tag in tags where tag.count >= 4 && tag[0] == "option" && tag[1] == qid {
            let optID = tag[2]
            guard isValidID(optID),
                  let optTitle = tag[3].nonEmpty,
                  !result.contains(where: { $0.id == optID }) else { continue }
            result.append(
                TTS29QuestionOption(
                    id: optID,
                    title: optTitle,
                    description: tag.count > 4 ? tag[4].nonEmpty : nil
                )
            )
            if result.count >= maxOptions { break }
        }
        return result
    }

    /// A `["label"/"description", questionID, value]` lookup keyed by id.
    private static func firstValue(_ name: String, forID id: String, in tags: [[String]]) -> String? {
        for tag in tags where tag.count >= 3 && tag[0] == name && tag[1] == id {
            if let value = tag[2].nonEmpty { return value }
        }
        return nil
    }

    /// Question and option ids are 1–64 ASCII letters, digits, `_`, or `-`.
    static func isValidID(_ value: String) -> Bool {
        guard (1...64).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar == "_" || scalar == "-"
                || (scalar >= "0" && scalar <= "9")
                || (scalar >= "A" && scalar <= "Z")
                || (scalar >= "a" && scalar <= "z")
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
