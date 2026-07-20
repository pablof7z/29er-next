import Foundation
import NMP

/// Fail-closed parsing of the TTS29 v1 tags delivered by NMP's canonical
/// kind:9 group query. Ordinary chat and malformed typed events remain plain
/// messages instead of entering the spoken-item projection.
enum TTS29ItemParsing {
    static let marker = "tts29"
    static let itemType = "item"
    static let answerType = "answer"
    static let version = "1"
    static let maxAttachments = 12
    static let maxQuestions = 3
    static let maxOptions = 8

    private static let maxArtifactBytes: UInt64 = 250 * 1024 * 1024

    static func item(from row: Row) -> TTS29Item? {
        guard row.kind == 9,
              markerType(in: row.tags) == itemType,
              let groupID = groupID(in: row.tags),
              let title = requiredText("title", max: 80, in: row.tags),
              let summary = optionalText("summary", max: 280, in: row.tags),
              let agent = optionalText("agent", max: 80, in: row.tags),
              let body = bounded(row.content, max: 40_000),
              let audio = audioArtifact(in: row.tags),
              let attachments = attachments(in: row.tags),
              let questions = questions(in: row.tags)
        else { return nil }

        let eventReferences = rows("e", in: row.tags)
        guard eventReferences.count <= 1 else { return nil }
        let parentID: String?
        if let reference = eventReferences.first {
            guard reference.count == 4,
                  reference[2].isEmpty,
                  reference[3] == "attach",
                  isLowerHex(reference[1], length: 64)
            else { return nil }
            parentID = reference[1]
        } else {
            parentID = nil
        }

        return TTS29Item(
            id: row.id,
            author: row.pubkey,
            createdAt: row.createdAt,
            groupID: groupID,
            agentName: agent ?? "",
            title: title,
            summary: summary,
            body: body,
            audio: audio,
            attachments: attachments,
            questions: questions,
            parentID: parentID,
            children: []
        )
    }

    static func answerBundle(from row: Row) -> TTS29AnswerBundle? {
        guard row.kind == 9,
              markerType(in: row.tags) == answerType,
              groupID(in: row.tags) != nil,
              let itemID = rootReference(in: row.tags)
        else { return nil }

        let answerRows = rows("answer", in: row.tags)
        guard (1...maxQuestions).contains(answerRows.count) else { return nil }
        var seen = Set<String>()
        var answers: [TTS29Answer] = []
        for tag in answerRows {
            guard (3...10).contains(tag.count),
                  isValidID(tag[1]),
                  seen.insert(tag[1]).inserted
            else { return nil }
            let values = tag.dropFirst(2).compactMap { bounded($0, max: 4_000) }
            guard values.count == tag.count - 2 else { return nil }
            answers.append(TTS29Answer(questionID: tag[1], values: values))
        }
        return TTS29AnswerBundle(
            eventID: row.id,
            itemID: itemID,
            author: row.pubkey,
            createdAt: row.createdAt,
            answers: answers
        )
    }

    static func isValidAnswer(_ bundle: TTS29AnswerBundle, for questions: [TTS29Question]) -> Bool {
        guard (1...maxQuestions).contains(bundle.answers.count) else { return false }
        let definitions = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        var answered = Set<String>()
        for answer in bundle.answers {
            guard answered.insert(answer.questionID).inserted,
                  let question = definitions[answer.questionID],
                  Set(answer.values).count == answer.values.count,
                  answer.values.allSatisfy({ bounded($0, max: 4_000) != nil })
            else { return false }
            let optionIDs = Set(question.options.map(\.id))
            switch question.kind {
            case .freeform:
                guard answer.values.count == 1 else { return false }
            case .single:
                guard answer.values.count == 1, optionIDs.contains(answer.values[0]) else {
                    return false
                }
            case .multiple:
                guard !answer.values.isEmpty, Set(answer.values).isSubset(of: optionIDs) else {
                    return false
                }
            }
        }
        return true
    }

    // MARK: - Artifacts

    private static func audioArtifact(in tags: [[String]]) -> TTS29Artifact? {
        let matches = rows("audio", in: tags)
        guard matches.count == 1,
              let artifact = artifact(from: matches[0], tagName: "audio", withLabel: false),
              artifact.mediaType.hasPrefix("audio/")
        else { return nil }
        return artifact
    }

    private static func attachments(in tags: [[String]]) -> [TTS29Artifact]? {
        let matches = rows("attachment", in: tags)
        guard matches.count <= maxAttachments else { return nil }
        let artifacts = matches.compactMap {
            artifact(from: $0, tagName: "attachment", withLabel: true)
        }
        return artifacts.count == matches.count ? artifacts : nil
    }

    private static func artifact(
        from tag: [String],
        tagName: String,
        withLabel: Bool
    ) -> TTS29Artifact? {
        guard tag.count == (withLabel ? 6 : 5), tag[0] == tagName,
              let url = bounded(tag[1], max: 2_048), url.hasPrefix("https://"),
              isLowerHex(tag[2], length: 64),
              let mediaType = bounded(tag[3], max: 128), mediaType.contains("/"),
              let byteCount = UInt64(tag[4]),
              byteCount > 0, byteCount <= maxArtifactBytes
        else { return nil }
        let label = withLabel ? bounded(tag[5], max: 120) : nil
        guard !withLabel || label != nil else { return nil }
        return TTS29Artifact(
            url: url,
            sha256: tag[2],
            mediaType: mediaType,
            byteCount: byteCount,
            label: label
        )
    }

    // MARK: - Questions

    private static func questions(in tags: [[String]]) -> [TTS29Question]? {
        let questionRows = rows("question", in: tags)
        guard questionRows.count <= maxQuestions,
              let labels = keyedText("label", max: 40, in: tags),
              let descriptions = keyedText("description", max: 500, in: tags),
              var options = keyedOptions(in: tags)
        else { return nil }

        var seen = Set<String>()
        var result: [TTS29Question] = []
        for tag in questionRows {
            guard tag.count == 4,
                  isValidID(tag[1]),
                  seen.insert(tag[1]).inserted,
                  let kind = TTS29QuestionKind(rawValue: tag[2]),
                  let title = bounded(tag[3], max: 240)
            else { return nil }
            let questionOptions = options.removeValue(forKey: tag[1]) ?? []
            switch kind {
            case .single, .multiple:
                guard !questionOptions.isEmpty else { return nil }
            case .freeform:
                guard questionOptions.isEmpty else { return nil }
            }
            result.append(
                TTS29Question(
                    id: tag[1],
                    kind: kind,
                    title: title,
                    shortTitle: labels[tag[1]] ?? title,
                    description: descriptions[tag[1]],
                    options: questionOptions
                )
            )
        }
        guard labels.keys.allSatisfy(seen.contains),
              descriptions.keys.allSatisfy(seen.contains),
              options.isEmpty
        else { return nil }
        return result
    }

    private static func keyedText(
        _ name: String,
        max: Int,
        in tags: [[String]]
    ) -> [String: String]? {
        var result: [String: String] = [:]
        for tag in rows(name, in: tags) {
            guard tag.count == 3,
                  isValidID(tag[1]),
                  result[tag[1]] == nil,
                  let value = bounded(tag[2], max: max)
            else { return nil }
            result[tag[1]] = value
        }
        return result
    }

    private static func keyedOptions(in tags: [[String]]) -> [String: [TTS29QuestionOption]]? {
        var result: [String: [TTS29QuestionOption]] = [:]
        var seen = Set<String>()
        for tag in rows("option", in: tags) {
            guard tag.count == 4 || tag.count == 5,
                  isValidID(tag[1]), isValidID(tag[2]),
                  seen.insert("\(tag[1])|\(tag[2])").inserted,
                  (result[tag[1]]?.count ?? 0) < maxOptions,
                  let title = bounded(tag[3], max: 120)
            else { return nil }
            let description: String?
            if tag.count == 5, !tag[4].isEmpty {
                guard let value = bounded(tag[4], max: 300) else { return nil }
                description = value
            } else {
                description = nil
            }
            result[tag[1], default: []].append(
                TTS29QuestionOption(id: tag[2], title: title, description: description)
            )
        }
        return result
    }

    // MARK: - Singular tags

    private static func markerType(in tags: [[String]]) -> String? {
        let matches = rows(marker, in: tags)
        guard matches.count == 1, matches[0].count == 3, matches[0][2] == version else {
            return nil
        }
        return matches[0][1]
    }

    private static func groupID(in tags: [[String]]) -> String? {
        let matches = rows("h", in: tags)
        guard matches.count == 1, matches[0].count == 2 else { return nil }
        return bounded(matches[0][1], max: 4_000)
    }

    private static func requiredText(
        _ name: String,
        max: Int,
        in tags: [[String]]
    ) -> String? {
        let matches = rows(name, in: tags)
        guard matches.count == 1, matches[0].count == 2 else { return nil }
        return bounded(matches[0][1], max: max)
    }

    /// Outer nil means malformed; inner nil means the singular optional tag is absent.
    private static func optionalText(
        _ name: String,
        max: Int,
        in tags: [[String]]
    ) -> String?? {
        let matches = rows(name, in: tags)
        if matches.isEmpty { return .some(nil) }
        guard matches.count == 1, matches[0].count == 2,
              let value = bounded(matches[0][1], max: max)
        else { return nil }
        return .some(value)
    }

    private static func rootReference(in tags: [[String]]) -> String? {
        let matches = rows("e", in: tags)
        guard matches.count == 1, matches[0].count == 4,
              matches[0][2].isEmpty, matches[0][3] == "root",
              isLowerHex(matches[0][1], length: 64)
        else { return nil }
        return matches[0][1]
    }

    private static func rows(_ name: String, in tags: [[String]]) -> [[String]] {
        tags.filter { $0.first == name }
    }

    private static func bounded(_ value: String, max: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= max ? trimmed : nil
    }

    static func isValidID(_ value: String) -> Bool {
        guard (1...64).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90)
                || ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 95
        }
    }

    private static func isLowerHex(_ value: String, length: Int) -> Bool {
        value.utf8.count == length && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }
}
