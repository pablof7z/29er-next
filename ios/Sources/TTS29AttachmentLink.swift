import Foundation

/// Resolves inline `[label](attachment:)` Markdown links against an item's file
/// attachments and narrated children. A matched link is rewritten to a private
/// scheme the transcript's `OpenURLAction` intercepts; unmatched links are left
/// untouched.
enum TTS29AttachmentLink {
    static let attachmentScheme = "ttsattach"
    static let childScheme = "ttschild"

    private static let pattern = try? NSRegularExpression(
        pattern: "\\[([^\\]]+)\\]\\(attachment:\\)",
        options: []
    )

    /// Rewrites every `[label](attachment:)` occurrence in `body` to either
    /// `ttsattach://a/<index>` (a file attachment matched by label) or
    /// `ttschild://c/<index>` (a narrated child matched by title).
    static func rewrite(_ body: String, item: TTS29Item) -> String {
        guard let pattern else { return body }
        let range = NSRange(body.startIndex..., in: body)
        let matches = pattern.matches(in: body, range: range)
        guard !matches.isEmpty else { return body }

        var result = body
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let full = Range(match.range, in: result),
                  let labelRange = Range(match.range(at: 1), in: result) else { continue }
            let label = String(result[labelRange])

            if let index = item.attachments.firstIndex(where: { $0.displayName == label })
                ?? item.attachments.firstIndex(where: { $0.label == label }) {
                result.replaceSubrange(full, with: "[\(label)](\(attachmentScheme)://a/\(index))")
            } else if let index = item.children.firstIndex(where: { $0.title == label }) {
                result.replaceSubrange(full, with: "[\(label)](\(childScheme)://c/\(index))")
            }
        }
        return result
    }

    /// Attachments referenced inline whose kind is `.image`, de-duplicated by
    /// index in first-appearance order. These render beneath the transcript.
    static func referencedImages(in body: String, item: TTS29Item) -> [(index: Int, artifact: TTS29Artifact)] {
        let rewritten = rewrite(body, item: item)
        guard let regex = try? NSRegularExpression(pattern: "\(attachmentScheme)://a/(\\d+)") else {
            return []
        }
        let range = NSRange(rewritten.startIndex..., in: rewritten)
        var seen = Set<Int>()
        var result: [(Int, TTS29Artifact)] = []
        for match in regex.matches(in: rewritten, range: range) {
            guard let indexRange = Range(match.range(at: 1), in: rewritten),
                  let index = Int(rewritten[indexRange]),
                  item.attachments.indices.contains(index),
                  item.attachments[index].kind == .image,
                  seen.insert(index).inserted else { continue }
            result.append((index, item.attachments[index]))
        }
        return result
    }

    /// The attachment index encoded in a `ttsattach://a/<index>` URL.
    static func attachmentIndex(from url: URL) -> Int? {
        guard url.scheme == attachmentScheme else { return nil }
        return Int(url.lastPathComponent)
    }

    /// The child index encoded in a `ttschild://c/<index>` URL.
    static func childIndex(from url: URL) -> Int? {
        guard url.scheme == childScheme else { return nil }
        return Int(url.lastPathComponent)
    }
}
