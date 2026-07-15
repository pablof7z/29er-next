#if NMP_DEVICE_PROOF && os(iOS)
import SwiftUI

struct VoiceComposerProofView: View {
    @State private var reply: ComposerReply?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Voice message proof")
                    .font(.title2.bold())
                Text("Press and hold the mic. Slide up to lock or left to cancel.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            Spacer()
            ChatComposer(
                canSend: true,
                recipients: [],
                reply: $reply,
                voiceDraftScope: "device-proof",
                send: { _ in "Proof mode keeps the captured draft local." }
            )
        }
        .background(PlatformSupport.groupedBackground)
    }
}
#endif
