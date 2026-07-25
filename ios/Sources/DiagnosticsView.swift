import NMP
import SwiftUI

struct DiagnosticsView: View {
    let snapshot: DiagnosticsSnapshot
    let error: String?
    let canResetCache: Bool
    let resetCache: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    DegradedStateNotice(
                        title: "Diagnostics unavailable",
                        message: error
                    )
                    .listRowInsets(EdgeInsets())
                }

                Section("Engine") {
                    LabeledContent("Planned relays", value: "\(snapshot.relays.count)")
                    LabeledContent("Uncovered authors", value: "\(snapshot.uncoveredAuthorCount)")
                }

                ForEach(snapshot.relays) { relay in
                    Section(relay.hostLabel) {
                        LabeledContent("Wire subscriptions", value: "\(relay.wireSubCount)")
                        LabeledContent("Authors served", value: "\(relay.authorsServed)")

                        if !relay.eventsByKind.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Received events")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(relay.eventsByKind, id: \.kind) { row in
                                    LabeledContent("kind \(row.kind)", value: "\(row.count)")
                                }
                            }
                        }

                        if !relay.filters.isEmpty {
                            DisclosureGroup("Wire filters") {
                                ForEach(Array(relay.filters.enumerated()), id: \.offset) { _, filter in
                                    Text(filter)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                if snapshot.relays.isEmpty {
                    ContentUnavailableView(
                        "Waiting for Diagnostics",
                        systemImage: "waveform.path.ecg",
                        description: Text("NMP has not emitted a relay plan yet.")
                    )
                }

                if canResetCache {
                    Section {
                        Button("Reset Cache", role: .destructive) {
                            confirmingReset = true
                        }
                        .accessibilityIdentifier("reset-nmp-cache")
                    } header: {
                        Text("Local Storage")
                    } footer: {
                        Text(
                            "Deletes cached events, pending writes, receipts, and sync evidence. "
                            + "Your saved account remains available for automatic sign-in."
                        )
                    }
                }
            }
            .navigationTitle("NMP Diagnostics")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Reset Cache?",
                isPresented: $confirmingReset,
                titleVisibility: .visible
            ) {
                Button("Reset and Reload", role: .destructive) {
                    resetCache()
                    dismiss()
                }
                .accessibilityIdentifier("confirm-reset-nmp-cache")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "29er Next will rebuild its local event cache from relays. "
                    + "Pending writes and their delivery history will be permanently deleted."
                )
            }
        }
    }
}

private extension RelayDiagnostics {
    var hostLabel: String {
        URL(string: relay)?.host ?? relay
    }
}
