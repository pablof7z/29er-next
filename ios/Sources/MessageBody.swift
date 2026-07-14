import SwiftUI

struct MessageBody: View {
    let raw: String
    let messageID: String
    let onReply: () -> Void

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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            PlatformSupport.performLightImpact()
                            onReply()
                        }
                case .audio(let display, let url):
                    AudioAttachmentView(
                        id: AudioAttachmentID(
                            messageID: messageID,
                            ordinal: index,
                            url: url
                        ),
                        displayURL: display,
                        url: url
                    )
                }
            }
        }
    }
}
