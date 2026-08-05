import Foundation
import NMP
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Debug-only evidence for the physical-device room-open gate. Production
/// query ownership is unchanged: this probe timestamps the existing seams and
/// exposes one accessibility report only when the proof launch flag is set.
@MainActor
@Observable
final class RoomOpenProbe: NSObject {
    enum Query: String, CaseIterable {
        case content
        case activity
        /// One observation for kind:39001 and kind:39002 together -- they
        /// arrive on the same `NMPGroupSnapshot`, so timing them apart would
        /// report two stages that no longer exist.
        case groupRecords
        case profiles

        var observeField: String {
            "\(rawValue)ObserveMs"
        }

        var snapshotFieldPrefix: String {
            self == .activity ? "activityQuery" : rawValue
        }
    }

    struct Snapshot {
        let rows: Int
        let newestID: String
    }

    static let shared = RoomOpenProbe()

    let isEnabled: Bool = {
        #if NMP_DEVICE_PROOF && os(iOS)
        ProcessInfo.processInfo.arguments.contains("--nmp-room-open-proof")
        #else
        false
        #endif
    }()
    let targetGroupID: String? = {
        #if NMP_DEVICE_PROOF && os(iOS)
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flag = arguments.firstIndex(of: "--nmp-room-open-proof-group"),
            arguments.indices.contains(flag + 1)
        else { return nil }
        return arguments[flag + 1]
        #else
        return nil
        #endif
    }()
    let offlineRelay: String? = {
        #if NMP_DEVICE_PROOF && os(iOS)
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flag = arguments.firstIndex(of: "--nmp-room-open-proof-offline-relay"),
            arguments.indices.contains(flag + 1)
        else { return nil }
        return arguments[flag + 1]
        #else
        return nil
        #endif
    }()
    private(set) var groupID: String?
    private(set) var report = "idle"

    private let clock = ContinuousClock()
    private var started: ContinuousClock.Instant?
    private var firstFrameMilliseconds: Double?
    private var observeMilliseconds: [Query: Double] = [:]
    private var snapshots: [Query: Snapshot] = [:]
    private var messageSnapshot: Snapshot?
    private var activitySnapshot: Snapshot?
    private var firstSnapshotMilliseconds: Double?
    private var maximumMainGapMilliseconds = 0.0
    private var previousFrame: ContinuousClock.Instant?
    #if canImport(UIKit)
    private var displayLink: CADisplayLink?
    #endif

    private override init() {
        super.init()
    }

    func begin(groupID: String) {
        guard isEnabled else { return }
        #if canImport(UIKit)
        displayLink?.invalidate()
        #endif
        self.groupID = groupID
        started = clock.now
        firstFrameMilliseconds = nil
        observeMilliseconds = [:]
        snapshots = [:]
        messageSnapshot = nil
        activitySnapshot = nil
        firstSnapshotMilliseconds = nil
        maximumMainGapMilliseconds = 0
        previousFrame = clock.now
        report = "running group=\(groupID)"

        #if canImport(UIKit)
        let link = CADisplayLink(target: self, selector: #selector(displayFrame))
        link.add(to: .main, forMode: .common)
        displayLink = link
        #endif
    }

    func recordFirstFrame(groupID: String) {
        guard isEnabled, self.groupID == groupID, firstFrameMilliseconds == nil else { return }
        firstFrameMilliseconds = elapsedMilliseconds()
        publish()
    }

    func recordObserve(_ query: Query, duration: Duration) {
        guard isEnabled, started != nil, observeMilliseconds[query] == nil else { return }
        observeMilliseconds[query] = duration.milliseconds
        publish()
    }

    func recordSnapshot(_ query: Query, rows: [Row]) {
        guard isEnabled, started != nil, snapshots[query] == nil else { return }
        let newestID = rows.sorted(by: newestFirst).first?.id ?? "none"
        snapshots[query] = Snapshot(rows: rows.count, newestID: newestID)
        publish()
    }

    /// The content stage, reported by the model that already holds the two
    /// row sets apart.
    ///
    /// The probe used to re-derive them by reading `Row.kind` back off the
    /// rows it was handed, which is protocol inspection in a diagnostics
    /// type: the room's own queries already select kind:9 and kind:30315
    /// separately, so the split was known before these rows ever arrived and
    /// re-deciding it here could only ever disagree.
    func recordContentSnapshot(messageRows: [Row], activityRows: [Row]) {
        guard isEnabled, started != nil, snapshots[.content] == nil else { return }
        snapshots[.content] = snapshot(for: messageRows + activityRows)
        messageSnapshot = snapshot(for: messageRows)
        activitySnapshot = snapshot(for: activityRows)
        firstSnapshotMilliseconds = elapsedMilliseconds()
        publish()
    }

    /// The group-records stage has no rows to count -- NMP delivers the
    /// folded snapshot, not the rows behind it. `rows` is therefore the
    /// number of listed subjects, and `newest` the member record's own event
    /// id, which is the identity a relay-signed list is superseded by.
    func recordSnapshot(_ query: Query, subjects snapshot: NMPGroupSnapshot) {
        guard isEnabled, started != nil, snapshots[query] == nil else { return }
        snapshots[query] = Snapshot(
            rows: snapshot.admins.count + snapshot.members.count,
            newestID: snapshot.perHost.compactMap { $0.members?.eventID }.sorted().last ?? "none"
        )
        publish()
    }

    #if canImport(UIKit)
    @objc private func displayFrame() {
        let now = clock.now
        if let previousFrame {
            maximumMainGapMilliseconds = max(
                maximumMainGapMilliseconds,
                previousFrame.duration(to: now).milliseconds
            )
        }
        previousFrame = now
    }
    #endif

    private func publish() {
        let complete = firstFrameMilliseconds != nil
            && firstSnapshotMilliseconds != nil
            && Query.allCases.allSatisfy { observeMilliseconds[$0] != nil && snapshots[$0] != nil }
        if complete {
            #if canImport(UIKit)
            displayLink?.invalidate()
            displayLink = nil
            #endif
        }

        let timings = Query.allCases.map { query in
            let observe = observeMilliseconds[query].map(format) ?? "pending"
            return "\(query.observeField)=\(observe)"
        }
        let snapshotEvidence = Query.allCases.map { query in
            let prefix = query.snapshotFieldPrefix
            guard let snapshot = snapshots[query] else {
                return "\(prefix)Rows=pending \(prefix)Newest=pending"
            }
            return "\(prefix)Rows=\(snapshot.rows) \(prefix)Newest=\(snapshot.newestID)"
        }
        report = ([
            complete ? "complete" : "running",
            "group=\(groupID ?? "none")",
            "firstFrameMs=\(firstFrameMilliseconds.map(format) ?? "pending")",
            "firstSnapshotMs=\(firstSnapshotMilliseconds.map(format) ?? "pending")",
            "mainMaxGapMs=\(format(maximumMainGapMilliseconds))"
        ] + timings + snapshotEvidence + [
            evidence(name: "message", snapshot: messageSnapshot),
            evidence(name: "activity", snapshot: activitySnapshot)
        ]).joined(separator: " ")
    }

    private func elapsedMilliseconds() -> Double? {
        started.map { $0.duration(to: clock.now).milliseconds }
    }

    private func newestFirst(_ lhs: Row, _ rhs: Row) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id < rhs.id
    }

    private func snapshot(for rows: [Row]) -> Snapshot {
        Snapshot(rows: rows.count, newestID: rows.sorted(by: newestFirst).first?.id ?? "none")
    }

    private func evidence(name: String, snapshot: Snapshot?) -> String {
        guard let snapshot else { return "\(name)Rows=pending \(name)Newest=pending" }
        return "\(name)Rows=\(snapshot.rows) \(name)Newest=\(snapshot.newestID)"
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

private extension Duration {
    var milliseconds: Double {
        let components = self.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
