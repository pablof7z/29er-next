import Foundation

/// How a TTS29 attachment is classified for preview, derived from its media
/// type. Images and text/markdown preview in-app; audio and other files hand
/// off to the system.
enum TTS29AttachmentKind: Sendable, Hashable {
    case image
    case audio
    case text
    case other

    init(mediaType: String) {
        let lower = mediaType.lowercased()
        if lower.hasPrefix("image/") {
            self = .image
        } else if lower.hasPrefix("audio/") {
            self = .audio
        } else if lower.hasPrefix("text/") || lower.contains("markdown") || lower.contains("json") {
            self = .text
        } else {
            self = .other
        }
    }

    var symbolName: String {
        switch self {
        case .image: "photo"
        case .audio: "waveform"
        case .text: "doc.text"
        case .other: "doc"
        }
    }

    /// Images and text/markdown open in an in-app preview; audio and other
    /// files open through the system.
    var opensInApp: Bool { self == .image || self == .text }
}

/// The single audio artifact or one of the file attachments carried by a
/// spoken item. Parsed from an `["audio", url, sha256, mediaType, byteCount]`
/// or `["attachment", url, sha256, mediaType, byteCount, label]` tag.
struct TTS29Artifact: Identifiable, Hashable, Sendable {
    let url: String
    let sha256: String
    let mediaType: String
    let byteCount: UInt64
    let label: String?

    var id: String { sha256.isEmpty ? url : sha256 }
    var resolvedURL: URL? { URL(string: url) }
    var kind: TTS29AttachmentKind { TTS29AttachmentKind(mediaType: mediaType) }

    var displayName: String {
        if let label, !label.isEmpty { return label }
        if let name = resolvedURL?.lastPathComponent, !name.isEmpty { return name }
        return "Attachment"
    }
}

enum TTS29QuestionKind: String, Sendable, Hashable {
    case single
    case multiple
    case freeform
}

struct TTS29QuestionOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String?
}

/// One immutable question definition from a spoken item.
struct TTS29Question: Identifiable, Hashable, Sendable {
    let id: String
    let kind: TTS29QuestionKind
    let title: String
    let shortTitle: String
    let description: String?
    let options: [TTS29QuestionOption]
}

/// One `["answer", questionID, values…]` entry inside an answer bundle.
struct TTS29Answer: Hashable, Sendable {
    let questionID: String
    let values: [String]
}

/// A submitted answer bundle for one spoken item. The deterministic winner per
/// (item, author) is the greatest `(createdAt, eventID)` tuple.
struct TTS29AnswerBundle: Hashable, Sendable {
    let eventID: String
    /// The spoken item this bundle answers, from its root `e` reference.
    let itemID: String
    let author: String
    let createdAt: UInt64
    let answers: [TTS29Answer]

    func values(for questionID: String) -> [String] {
        answers.first { $0.questionID == questionID }?.values ?? []
    }
}

/// A parsed TTS29 spoken item. Its `id` is the source `kind:9` event id, which
/// is also its durable item id. `children` are narrated sub-branches assembled
/// by ``TTS29Catalog`` from the `attach` edges of other messages.
struct TTS29Item: Identifiable, Hashable, Sendable {
    let id: String
    let author: String
    let createdAt: UInt64
    let groupID: String
    let agentName: String
    let title: String
    let summary: String?
    let body: String
    let audio: TTS29Artifact?
    let attachments: [TTS29Artifact]
    let questions: [TTS29Question]
    /// The parent item id when this item is itself a narrated branch.
    let parentID: String?
    var children: [TTS29Item]

    var playableURL: URL? { audio?.resolvedURL }
    var hasAudio: Bool { audio?.resolvedURL != nil }
    var hasAttachments: Bool { !attachments.isEmpty }
    var hasQuestions: Bool { !questions.isEmpty }
    var hasChildren: Bool { !children.isEmpty }
    var createdDate: Date { Date(timeIntervalSince1970: TimeInterval(createdAt)) }

    /// The narrated child referenced by an inline `[title](attachment:)` link,
    /// matched by title equality.
    func child(labeled label: String) -> TTS29Item? {
        children.first { $0.title == label }
    }
}
