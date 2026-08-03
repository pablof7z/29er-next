import NMP

@MainActor
extension AppModel {
    func selectHost(_ host: String) {
        let allowedHosts = activePubkey == nil ? [groupRelay] : remembered.hosts
        guard allowedHosts.contains(host) else { return }
        selectedHost = host
        if selectedGroup?.hostRelay != host { selectedGroup = nil }
    }

    func selectGroup(_ group: RememberedGroupChoice) {
        guard activePubkey != nil, remembered.groups.contains(group) else { return }
        selectedHost = group.host
        selectedGroup = group.coordinate
    }

    func summary(for group: RememberedGroupChoice) -> GroupSummary {
        groups.first { $0.id == group.coordinate } ?? GroupSummary(
            id: group.coordinate,
            name: group.displayName,
            about: nil,
            parentLocalID: nil
        )
    }

    func observeGroups(host: String) async {
        guard let engine else { return }
        let generation = engineGeneration
        groups = []
        hasReceivedGroups = false
        groupsError = nil
        do {
            let query = try await openNMPQuery(
                engine: engine,
                query: groupDirectoryQuery(host: host)
            )
            defer { query.cancel() }

            for try await batch in query {
                guard !Task.isCancelled,
                      generation == engineGeneration,
                      selectedHost == host else { return }
                groups = GroupDirectoryProjection.groups(from: batch.rows, hostRelay: host)
                groupsError = nil
                hasReceivedGroups = true
            }
        } catch {
            guard !Task.isCancelled,
                  generation == engineGeneration,
                  selectedHost == host else { return }
            groupsError = error.localizedDescription
        }
    }

    func observeRememberedGroups(using engine: NMPEngine, generation: Int) async {
        do {
            let query = try await openNMPQuery(engine: engine, demand: activeAccountDemand())
            defer { query.cancel() }

            for try await batch in query {
                guard !Task.isCancelled, generation == engineGeneration else { return }
                // `activeAccountDemand()` selects kind:10009 already, so a
                // second app-side kind check would only re-decide what NMP
                // decided. The parser is kind-agnostic and tolerant by
                // contract.
                let snapshot = batch.rows.first.map {
                    RememberedGroupSnapshot(
                        parseSimpleGroupsListTolerant($0),
                        sourceEvent: FavoriteRelayListEvent($0)
                    )
                } ?? .empty
                applyRememberedGroups(snapshot)
            }
        } catch {
            guard !Task.isCancelled, generation == engineGeneration else { return }
            rememberedGroupsError = error.localizedDescription
        }
    }

    func observeDiagnostics(using engine: NMPEngine, generation: Int) async {
        do {
            let observation = try engine.observeDiagnostics()
            defer { observation.cancel() }

            for try await snapshot in observation {
                guard !Task.isCancelled, generation == engineGeneration else { return }
                diagnostics = snapshot
                diagnosticsError = nil
            }
        } catch {
            guard !Task.isCancelled, generation == engineGeneration else { return }
            diagnosticsError = error.localizedDescription
        }
    }

    private func applyRememberedGroups(_ snapshot: RememberedGroupSnapshot) {
        remembered = snapshot
        hasReceivedRememberedGroups = true
        rememberedGroupsError = nil
        selectedGroup = HostGroupSelectionPolicy.reconciledGroup(
            activePubkey: activePubkey,
            snapshot: snapshot,
            selectedGroup: selectedGroup
        )
        selectedHost = HostGroupSelectionPolicy.reconciledHost(
            activePubkey: activePubkey,
            bootstrapHost: groupRelay,
            snapshot: snapshot,
            selectedHost: selectedHost
        )
    }
}
