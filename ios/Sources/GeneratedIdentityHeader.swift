import SwiftUI

struct GeneratedIdentityHeader: View {
    let profile: GeneratedIdentityProfile

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: profile.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.headline)
                Text("Your starter identity").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

extension String {
    var shortIdentity: String {
        guard count > 20 else { return self }
        return "\(prefix(10))…\(suffix(10))"
    }
}
