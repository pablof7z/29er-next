#if NMP_DEVICE_PROOF && os(iOS)
import SwiftUI

struct AttachmentComposerProofView: View {
    @State private var reply: ComposerReply?

    private let samples = [
        ComposerAttachment(
            filename: "room-photo.png",
            contentType: "image/png",
            data: Data(base64Encoded: Self.pixelPNG) ?? Data()
        ),
        ComposerAttachment(
            filename: "notes.pdf",
            contentType: "application/pdf",
            data: Data("proof document".utf8)
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ChatComposer(
                canSend: true,
                recipients: [],
                reply: $reply,
                initialAttachments: samples,
                send: { _ in nil }
            )
        }
        .background(PlatformSupport.groupedBackground)
    }

    private static let pixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
#endif
