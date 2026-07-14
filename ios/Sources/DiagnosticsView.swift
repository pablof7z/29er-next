import NMP
import SwiftUI

struct DiagnosticsView: View {
    let snapshot: DiagnosticsSnapshot
    let error: String?
    @Environment(\.dismiss) private var dismiss

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
            }
            .navigationTitle("NMP Diagnostics")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension RelayDiagnostics {
    var hostLabel: String {
        URL(string: relay)?.host ?? relay
    }
}
