#if NMP_DEVICE_PROOF && os(iOS)
import SwiftUI

struct MarkdownMessageProofView: View {
    private let sample = """
    # Markdown in chat

    **Bold**, *italic*, ~~strikethrough~~, and `inline code` render without raw markers.

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
