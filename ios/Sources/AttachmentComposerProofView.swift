#if NMP_DEVICE_PROOF && os(iOS)
import NMP
import SwiftUI

struct AttachmentComposerProofView: View {
    @State private var reply: ComposerReply?
    @State private var uploadProofPubkey: String?
    @State private var uploadProofStatus: String?

    private let runsLiveUploadProof = ProcessInfo.processInfo.arguments
        .contains("--attachment-upload-proof")

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
                send: runUploadProof
            )
            if let uploadProofStatus {
                Text(uploadProofStatus)
                    .font(.caption)
                    .accessibilityIdentifier("attachment-upload-proof-status")
            }
            if let uploadProofPubkey {
                Text(uploadProofPubkey)
                    .font(.caption2)
                    .accessibilityIdentifier("attachment-upload-proof-pubkey")
            }
        }
        .background(PlatformSupport.groupedBackground)
    }

    private func runUploadProof(_ request: ComposerRequest) async -> String? {
        guard runsLiveUploadProof else { return nil }
        let engine: NMPEngine
        do {
            engine = try NMPEngine(
                config: NMPConfig(),
                localAccountStore: NMPKeychainAccountStore(
                    service: "io.f7z.29er-next.device-proof",
                    account: "blossom-live"
                )
            )
        } catch {
            uploadProofStatus = "failed: engine"
            return "NMP could not start the upload proof."
        }
        defer { engine.shutdown() }

        do {
            let publicKey: String
            if let activeAccount = try engine.activeAccount() {
                publicKey = activeAccount
            } else {
                let registration = try await engine.generateAccount()
                try engine.setActiveAccount(registration.publicKey)
                publicKey = registration.publicKey
            }
            uploadProofPubkey = publicKey
            let uploader = BlossomAttachmentUploader(engine: engine)
            for attachment in request.attachments {
                _ = try await uploader.upload(attachment, to: "wss://nip29.f7z.io")
            }
            uploadProofStatus = "succeeded"
            return nil
        } catch {
            uploadProofStatus = "failed: \(error.localizedDescription)"
            return error.localizedDescription
        }
    }

    private static let pixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
#endif
