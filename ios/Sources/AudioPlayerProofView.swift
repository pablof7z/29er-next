#if NMP_DEVICE_PROOF && os(iOS)
import SwiftUI

struct AudioPlayerProofView: View {
    private let sample = """
    A compact player keeps the message readable while the attachment handles playback.
    https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3?proof=audio
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Audio attachment")
                        .font(.title2.bold())
                    MessageBody(raw: sample, messageID: "audio-proof", onReply: {})
                    Text("The source URL is replaced by the player and remains available from More.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Player Proof")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("audio-player-proof")
    }
}
#endif
