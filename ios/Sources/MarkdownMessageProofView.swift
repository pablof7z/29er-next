#if NMP_DEVICE_PROOF && os(iOS)
import SwiftUI

struct MarkdownMessageProofView: View {
    private let sample = """
    # Markdown in chat

    **Bold**, *italic*, ~~strikethrough~~, and `inline code` render without raw markers.

    Valid NIP-27: nostr:npub14f8usejl26twx0dhuxjh9cas7keav9vr0v8nvtwtrjqx3vycc76qqh9nsy

    Malformed NIP-27: nostr:npub1notvalid

    - Lists keep their structure
    - [Web links](https://developer.apple.com) remain tappable

    > Quotes are visually distinct.

    ```
    let message = "Markdown"
    ```
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                MessageBody(
                    raw: sample,
                    messageID: "markdown-proof",
                    onOpenLink: { _ in },
                    onReply: {}
                )
                .padding(20)
            }
            .navigationTitle("Markdown Proof")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("markdown-message-proof")
    }
}
#endif
