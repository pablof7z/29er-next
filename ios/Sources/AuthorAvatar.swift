import Kingfisher
import SwiftUI

struct AuthorAvatar: View {
    let pubkey: String
    let displayName: String
    let pictureURL: URL?
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(pubkey.avatarColor.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            .overlay {
                if let pictureURL {
                    KFImage(pictureURL)
                        .placeholder { Color.clear }
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                }
            }
    }
}
