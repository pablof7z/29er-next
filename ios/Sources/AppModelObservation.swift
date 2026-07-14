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
            var demand = try groupDiscoveryDemand(host: host)
            demand.selection.limit = 250
            let query = try await openNMPQuery(engine: engine, demand: demand)
            defer { query.cancel() }

            for await batch in query {
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

            for await batch in query {
                guard !Task.isCancelled, generation == engineGeneration else { return }
                let decoded = batch.rows.first(where: { $0.kind == 10_009 })
                    .map(decodeRememberedGroups)
                applyRememberedGroups(decoded.map(RememberedGroupSnapshot.init) ?? .empty)
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

            for await snapshot in observation {
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
