import SwiftUI

/// The read-along transcript. Blocks render from the item's Markdown body;
/// the spoken sentence stays primary while the rest recede. Tapping a block
/// seeks to it. Inline `[label](attachment:)` links open attachments or push
/// narrated children.
struct TTS29TranscriptView: View {
    let transcript: TTS29Transcript
    let item: TTS29Item
    let focus: TTS29Focus?
    let onSeek: (TTS29Block) -> Void
    let onOpenAttachment: (TTS29Artifact) -> Void
    let onOpenChild: (TTS29Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(transcript.blocks) { block in
                TTS29BlockView(
                    block: block,
                    item: item,
                    focus: blockFocus(for: block),
                    onOpenAttachment: onOpenAttachment,
                    onOpenChild: onOpenChild
                )
                .id(block.id)
                .contentShape(Rectangle())
                .onTapGesture { onSeek(block) }
            }
        }
    }

    private func blockFocus(for block: TTS29Block) -> TTS29BlockFocus {
        guard let focus else { return .inactive }
        return focus.block == block.id ? .focused(focus.sentence) : .dimmed
    }
}

enum TTS29BlockFocus: Equatable {
    case inactive
    case focused(Int)
    case dimmed

    var isActive: Bool { self != .dimmed }
    func isSentenceActive(_ index: Int) -> Bool {
        switch self {
        case .inactive: true
        case .focused(let spoken): index == spoken
        case .dimmed: false
        }
    }
}

private struct TTS29BlockView: View {
    let block: TTS29Block
    let item: TTS29Item
    let focus: TTS29BlockFocus
    let onOpenAttachment: (TTS29Artifact) -> Void
    let onOpenChild: (TTS29Item) -> Void

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.35), value: focus)
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .heading(let level):
            text.font(level <= 1 ? .title3.bold() : .headline)
        case .paragraph:
            withImages { text.font(.body) }
        case .bullet:
            marker("•") { withImages { text.font(.body) } }
        case .ordered(let glyph):
            marker(glyph) { withImages { text.font(.body) } }
        case .quote:
            HStack(spacing: 10) {
                Capsule().fill(Color.accentColor).frame(width: 3)
                text.font(.body.italic())
            }
        case .code:
            text.font(.callout.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        }
    }

    private var text: some View {
        Text(styled())
            .tint(.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction(handler: handleURL))
    }

    private func marker(_ glyph: String, @ViewBuilder body: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(glyph)
                .font(.body.monospacedDigit())
                .foregroundStyle(focus.isActive ? .secondary : .tertiary)
            body()
        }
    }

    @ViewBuilder
    private func withImages(@ViewBuilder body: () -> some View) -> some View {
        let images = TTS29AttachmentLink.referencedImages(in: block.text, item: item)
        VStack(alignment: .leading, spacing: 10) {
            body()
            ForEach(images, id: \.index) { entry in
                Button {
                    onOpenAttachment(entry.artifact)
                } label: {
                    TTS29RemoteImage(url: entry.artifact.resolvedURL)
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .opacity(focus.isActive ? 1 : 0.55)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Concatenates the block's sentences, dimming any sentence that is not the
    /// spoken one, while keeping inline link styling intact.
    private func styled() -> AttributedString {
        let sentences = TTS29Transcript.sentences(in: block)
        var result = AttributedString()
        for (index, sentence) in sentences.enumerated() {
            if index > 0 { result.append(AttributedString(" ")) }
            var attributed = inline(sentence)
            if !focus.isSentenceActive(index) {
                attributed.foregroundColor = .secondary
            }
            result.append(attributed)
        }
        return result
    }

    private func inline(_ raw: String) -> AttributedString {
        let rewritten = TTS29AttachmentLink.rewrite(raw, item: item)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: rewritten, options: options)) ?? AttributedString(raw)
    }

    private func handleURL(_ url: URL) -> OpenURLAction.Result {
        if let index = TTS29AttachmentLink.attachmentIndex(from: url),
           item.attachments.indices.contains(index) {
            onOpenAttachment(item.attachments[index])
            return .handled
        }
        if let index = TTS29AttachmentLink.childIndex(from: url),
           item.children.indices.contains(index) {
            onOpenChild(item.children[index])
            return .handled
        }
        return .systemAction
    }
}
