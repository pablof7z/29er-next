import NMP
import Observation

@MainActor
@Observable
final class RoomTimelineModel {
    enum State: Equatable {
        case loading
        case observing
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var messages: [RoomMessage] = []
    private(set) var activities: [AgentActivity] = []
    private(set) var coverage: Coverage = .unknown

    private let engine: NMPEngine
    private let groupID: String

    init(engine: NMPEngine, groupID: String) {
        self.engine = engine
        self.groupID = groupID
    }

    func observe() async {
        do {
            let query = try engine.observe(
                NMPFilter(
                    kinds: [9, 30_315],
                    tags: ["h": .literal([groupID])],
                    limit: 200
                )
            )
            defer { query.cancel() }
            state = .observing

            for await batch in query {
                guard !Task.isCancelled else { return }
                messages = NIP29ViewProjection.messages(from: batch.rows)
                activities = NIP29ViewProjection.activities(from: batch.rows)
                coverage = batch.coverage
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
