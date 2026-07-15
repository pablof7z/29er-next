import Foundation
import NMP

struct RememberedGroupChoice: Identifiable, Hashable, Sendable {
    let coordinate: GroupCoordinate
    let name: String?

    var id: GroupCoordinate { coordinate }
    var host: String { coordinate.hostRelay }
    var groupID: String { coordinate.localID }
    var displayName: String { name?.nonEmpty ?? groupID }

    init(host: String, groupID: String, name: String?) {
        coordinate = GroupCoordinate(hostRelay: host, localID: groupID)
        self.name = name
    }

    init(_ group: GroupRef) {
        self.init(host: group.host, groupID: group.groupId, name: group.name)
    }
}

struct RememberedGroupSnapshot: Equatable, Sendable {
    let groups: [RememberedGroupChoice]
    let hosts: [String]
    let hasPrivateContent: Bool

    static let empty = RememberedGroupSnapshot(
        groups: [],
        hosts: [],
        hasPrivateContent: false
    )

    init(groups: [RememberedGroupChoice], hosts: [String], hasPrivateContent: Bool) {
        var seenGroups = Set<GroupCoordinate>()
        self.groups = groups.filter { seenGroups.insert($0.coordinate).inserted }

        var seenHosts = Set<String>()
        self.hosts = hosts.filter {
            !$0.isEmpty && seenHosts.insert($0).inserted
        }
        self.hasPrivateContent = hasPrivateContent
    }

    init(_ remembered: RememberedGroups) {
        self.init(
            groups: remembered.groups.map(RememberedGroupChoice.init),
            hosts: remembered.hostsInUse,
            hasPrivateContent: remembered.hasPrivateContent
        )
    }
}

enum HostGroupSelectionPolicy {
    static func reconciledHost(
        activePubkey: String?,
        bootstrapHost: String,
        snapshot: RememberedGroupSnapshot,
        selectedHost: String?
    ) -> String? {
        guard activePubkey != nil else { return bootstrapHost.nonEmpty }
        if let selectedHost, snapshot.hosts.contains(selectedHost) { return selectedHost }
        return snapshot.hosts.first
    }

    static func reconciledGroup(
        activePubkey: String?,
        snapshot: RememberedGroupSnapshot,
        selectedGroup: GroupCoordinate?
    ) -> GroupCoordinate? {
        guard activePubkey != nil,
              let selectedGroup,
              snapshot.groups.contains(where: { $0.coordinate == selectedGroup }) else {
            return nil
        }
        return selectedGroup
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
