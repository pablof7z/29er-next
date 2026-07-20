import Foundation
import NMP

/// The set of TTS29 spoken items present in a room's chat rows, indexed by
/// event id with their narrated branches assembled. Ordinary chat messages are
/// simply absent from the index.
struct TTS29Catalog: Equatable {
    static let empty = TTS29Catalog(assembled: [:], answers: [:])

    /// Assembled items (children nested) keyed by item id. Every parsed item
    /// appears here, whether it is a root message or a narrated child, so a tap
    /// on any spoken message can open its own player.
    private let assembled: [String: TTS29Item]
    /// Winning answer bundle per `"itemID|author"`.
    private let answers: [String: TTS29AnswerBundle]

    /// The greatest bound depth of narrated nesting and children per node.
    static let maxDepth = 3
    static let maxChildren = 12

    private init(assembled: [String: TTS29Item], answers: [String: TTS29AnswerBundle]) {
        self.assembled = assembled
        self.answers = answers
    }

    init(rows: [Row]) {
        var flat: [String: TTS29Item] = [:]
        var childIDs: [String: [String]] = [:]
        var answers: [String: TTS29AnswerBundle] = [:]

        for row in rows {
            if let item = TTS29ItemParsing.item(from: row) {
                flat[item.id] = item
                if let parent = item.parentID {
                    childIDs[parent, default: []].append(item.id)
                }
            } else if let bundle = TTS29ItemParsing.answerBundle(from: row) {
                let key = Self.answerKey(itemID: bundle.itemID, author: bundle.author)
                if let existing = answers[key], !Self.wins(bundle, over: existing) { continue }
                answers[key] = bundle
            }
        }

        // Order children by ascending (createdAt, id) so branches read in the
        // order they were narrated.
        for (parent, ids) in childIDs {
            childIDs[parent] = ids.sorted { lhs, rhs in
                guard let left = flat[lhs], let right = flat[rhs] else { return lhs < rhs }
                if left.createdAt == right.createdAt { return left.id < right.id }
                return left.createdAt < right.createdAt
            }
        }

        var assembled: [String: TTS29Item] = [:]
        for id in flat.keys {
            assembled[id] = Self.assemble(id, flat: flat, childIDs: childIDs, visited: [], depth: 0)
        }

        self.init(assembled: assembled, answers: answers)
    }

    /// The assembled spoken item for a message id, or nil if the message is not
    /// a TTS29 item.
    func item(id: String) -> TTS29Item? { assembled[id] }

    func isSpokenItem(id: String) -> Bool { assembled[id] != nil }

    var isEmpty: Bool { assembled.isEmpty }

    /// The winning answer bundle a given author submitted for an item.
    func answer(itemID: String, author: String?) -> TTS29AnswerBundle? {
        guard let author else { return nil }
        return answers[Self.answerKey(itemID: itemID, author: author)]
    }

    // MARK: - Assembly

    private static func assemble(
        _ id: String,
        flat: [String: TTS29Item],
        childIDs: [String: [String]],
        visited: Set<String>,
        depth: Int
    ) -> TTS29Item? {
        guard var item = flat[id], !visited.contains(id) else { return nil }
        var branch = visited
        branch.insert(id)

        if depth < maxDepth {
            let children = (childIDs[id] ?? [])
                .prefix(maxChildren)
                .compactMap {
                    assemble($0, flat: flat, childIDs: childIDs, visited: branch, depth: depth + 1)
                }
            item.children = Array(children)
        } else {
            item.children = []
        }
        return item
    }

    private static func answerKey(itemID: String, author: String) -> String {
        "\(itemID)|\(author)"
    }

    private static func wins(_ candidate: TTS29AnswerBundle, over existing: TTS29AnswerBundle) -> Bool {
        if candidate.createdAt != existing.createdAt {
            return candidate.createdAt > existing.createdAt
        }
        return candidate.eventID > existing.eventID
    }
}
