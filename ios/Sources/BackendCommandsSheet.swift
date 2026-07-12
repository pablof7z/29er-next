import SwiftUI

/// Commands a user can issue to a tenex-edge management backend from the room's
/// People roster. Each action publishes a kind:9 chat message directed at the
/// backend; the backend's reply lands inline in the room timeline. Sending
/// requires a signed-in account that is a channel admin — the relay/backend
/// enforce authority, the app only offers the affordance.
struct BackendCommandsSheet: View {
    let backend: RoomBackend
    let canSend: Bool
    /// Publishes `command` to the backend, returning an error message or nil.
    let send: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if !canSend {
                    Section {
                        Label(
                            "Sign in to send commands to this backend.",
                            systemImage: "person.crop.circle.badge.exclamationmark"
                        )
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    }
                }

                Section {
                    commandRow(
                        title: "List sessions",
                        systemImage: "list.bullet.rectangle",
                        command: "list sessions",
                        identifier: "backend-command-list-sessions"
                    )
                    commandRow(
                        title: "List agents",
                        systemImage: "person.3",
                        command: "list agents",
                        identifier: "backend-command-list-agents"
                    )

                    NavigationLink {
                        AddAgentView(
                            backendLabel: backend.label,
                            agents: backend.agents,
                            canSend: canSend,
                            perform: perform
                        )
                    } label: {
                        Label("Add agent", systemImage: "plus.circle")
                    }
                    .disabled(!canSend || isSending)
                    .accessibilityIdentifier("backend-command-add-agent")
                } header: {
                    Text("Commands")
                } footer: {
                    Text("Replies appear in the room timeline.")
                }
            }
            .navigationTitle(backend.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isSending {
                    ProgressView().controlSize(.large)
                }
            }
            .alert(
                "Command Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                presenting: errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    private func commandRow(
        title: String,
        systemImage: String,
        command: String,
        identifier: String
    ) -> some View {
        Button {
            perform(command)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .disabled(!canSend || isSending)
        .accessibilityIdentifier(identifier)
    }

    private func perform(_ command: String) {
        guard canSend, !isSending else { return }
        isSending = true
        Task {
            let error = await send(command)
            isSending = false
            if let error {
                errorMessage = error
            } else {
                dismiss()
            }
        }
    }
}

/// The agent picker behind "Add agent": the backend's advertised agents from
/// its kind:0 `["agent", slug, description]` tags. Tapping one sends
/// `add <slug>`.
private struct AddAgentView: View {
    let backendLabel: String
    let agents: [BackendAgent]
    let canSend: Bool
    let perform: (String) -> Void

    var body: some View {
        List {
            if agents.isEmpty {
                ContentUnavailableView(
                    "No Agents Advertised",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("\(backendLabel) has not published any agents on its profile.")
                )
            } else {
                ForEach(agents) { agent in
                    Button {
                        perform("add \(agent.slug)")
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(agent.slug)
                                .font(.headline)
                            if !agent.description.isEmpty {
                                Text(agent.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!canSend)
                    .accessibilityIdentifier("backend-add-agent-\(agent.slug)")
                }
            }
        }
        .navigationTitle("Add Agent")
        .navigationBarTitleDisplayMode(.inline)
    }
}
