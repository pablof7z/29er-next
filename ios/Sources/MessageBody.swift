import SwiftUI

struct MessageBody: View {
    let raw: String
    let messageID: String
    let onOpenLink: (URL) -> Void
    let onOpenImage: (URL) -> Void
    let onReply: () -> Void

    init(
        raw: String,
        messageID: String,
        onOpenLink: @escaping (URL) -> Void = { _ in },
        onOpenImage: @escaping (URL) -> Void = { _ in },
        onReply: @escaping () -> Void
    ) {
        self.raw = raw
        self.messageID = messageID
        self.onOpenLink = onOpenLink
        self.onOpenImage = onOpenImage
        self.onReply = onReply
    }

    private var blocks: [MessageContent.Block] {
        MessageContent.blocks(of: raw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .inline(let segments):
                    Text(MessageContent.attributed(segments))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.openURL, OpenURLAction { url in
                            onOpenLink(url)
                            return .handled
                        })
                        .contentShape(Rectangle())
                        .onTapGesture {
                            PlatformSupport.performLightImpact()
                            onReply()
                        }
                case .audio(_, let url):
                    AudioAttachmentView(
                        id: AudioAttachmentID(
                            messageID: messageID,
                            ordinal: index,
                            url: url
                        ),
                        url: url
                    )
                case .image(_, let url):
                    InlineRemoteImage(url: url) { onOpenImage(url) }
                }
            }
        }
    }
}
