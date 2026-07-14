import SwiftUI

struct AgentProfileSheet: View {
    let pubkey: String
    let displayName: String
    let pictureURL: URL?
    let profile: RoomProfile?
    let activity: AgentActivity?
    @Environment(\.dismiss) private var dismiss

    private var title: String? {
        nonEmpty(activity?.title)
    }

    private var detail: String? {
        nonEmpty(activity?.activity)
    }

    private var statusLabel: String {
        guard let activity else { return "No current activity" }
        return activity.isBusy ? "Busy" : "Idle"
    }

    private var statusColor: Color {
        guard let activity else { return .secondary }
        return activity.isBusy ? .orange : .green
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if activity != nil {
                        currentWork
                    }
                    details
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Agent")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(spacing: 16) {
            AuthorAvatar(
                pubkey: pubkey,
                displayName: displayName,
                pictureURL: pictureURL,
                size: 72
            )
            VStack(alignment: .leading, spacing: 7) {
                Text(displayName)
                    .font(.title2.weight(.semibold))
                Label(statusLabel, systemImage: "circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var currentWork: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current work")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let title {
                Text(title)
                    .font(.headline)
            }
            if let detail, detail != title {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Details")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let slug = nonEmpty(activity?.slug) {
                detailRow("Agent", value: slug)
            }
            if let host = nonEmpty(activity?.host ?? profile?.host) {
                detailRow("Host", value: host)
            }
            if let workspace = nonEmpty(profile?.workspace) {
                detailRow("Workspace", value: workspace)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Public key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(pubkey)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button {
                    PlatformSupport.copyToPasteboard(pubkey)
                } label: {
                    Label("Copy public key", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
