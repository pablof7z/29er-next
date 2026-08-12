import Foundation
import NMP

struct RememberedGroupChoice: Identifiable, Hashable, Sendable {
    let coordinate: GroupCoordinate
    let name: String?

    var id: GroupCoordinate { coordinate }
    var host: String { coordinate.hostRelay }
    var groupID: String { coordinate.localID }
    var displayName: String {
        guard let name, !name.isEmpty else { return groupID }
        return name
    }

    init(host: String, groupID: String, name: String?) {
        coordinate = GroupCoordinate(hostRelay: host, localID: groupID)
        self.name = name
    }

    init(_ group: SimpleGroupEntry) {
        self.init(host: group.hostRelay, groupID: group.groupId, name: group.name)
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

    init(
        groups: [RememberedGroupChoice],
        hosts: [String],
        hasPrivateContent: Bool
    ) {
        var seenGroups = Set<GroupCoordinate>()
        self.groups = groups.filter { seenGroups.insert($0.coordinate).inserted }

        var seenHosts = Set<String>()
        self.hosts = hosts.filter {
            !$0.isEmpty && seenHosts.insert($0).inserted
        }
        self.hasPrivateContent = hasPrivateContent
    }

    init(_ remembered: SimpleGroupsList) {
        self.init(
            groups: remembered.items.map(RememberedGroupChoice.init),
            hosts: remembered.relaysInUse,
            hasPrivateContent: remembered.hasPrivateContent
        )
    }
}

enum HostGroupSelectionPolicy {
    static func reconciledHost(
        availableHosts: [String],
        selectedHost: String?
    ) -> String? {
        if let selectedHost, availableHosts.contains(selectedHost) { return selectedHost }
        return availableHosts.first
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
