import SwiftUI

#if os(iOS)
struct VoiceProviderListView: View {
    @Environment(VoiceProviderStore.self) private var store
    @State private var showingAddProvider = false
    @State private var newConfiguration: VoiceProviderConfiguration?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: activeSelection) {
                    ForEach(store.configurations) { configuration in
                        Text(configuration.name)
                            .tag(configuration.id)
                    }
                }
                .accessibilityIdentifier("voice-active-provider")
            } header: {
                Text("Active Configuration")
            } footer: {
                Text("Only one configuration is active. Incomplete configurations cannot be selected.")
            }

            Section("Configurations") {
                ForEach(store.configurations) { configuration in
                    configurationRow(configuration)
                }

                Button {
                    showingAddProvider = true
                } label: {
                    Label("Add Configuration…", systemImage: "plus")
                }
                .accessibilityIdentifier("voice-add-provider")
            }
        }
        .navigationTitle("Provider")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "New Configuration",
            isPresented: $showingAddProvider,
            titleVisibility: .visible
        ) {
            ForEach(VoiceProviderKind.allCases) { kind in
                Button(kind.title) {
                    newConfiguration = .new(kind)
                }
            }
        } message: {
            Text("Choose the speech-to-text provider.")
        }
        .sheet(item: $newConfiguration) { configuration in
            NavigationStack {
                VoiceProviderEditor(configuration: configuration, isNew: true)
            }
        }
        .alert("Provider Configuration", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var activeSelection: Binding<UUID> {
        Binding(
            get: { store.activeConfigurationID },
            set: { id in
                do {
                    try store.activate(id)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func configurationRow(
        _ configuration: VoiceProviderConfiguration
    ) -> some View {
        NavigationLink {
            VoiceProviderEditor(configuration: configuration, isNew: false)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: configuration.kind.systemImage)
                    .frame(width: 24)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(configuration.name)
                    Text(configuration.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if configuration.id == store.activeConfigurationID {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                } else if !store.isReady(configuration) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Needs attention")
                }
            }
            .accessibilityAddTraits(
                configuration.id == store.activeConfigurationID ? .isSelected : []
            )
        }
        .swipeActions {
            if configuration.id != store.activeConfigurationID {
                Button("Delete", role: .destructive) {
                    do {
                        try store.delete(configuration.id)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
#endif
