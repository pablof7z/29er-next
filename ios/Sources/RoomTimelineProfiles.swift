import NMP

struct ProfileAuthorUpdates {
    let stream: AsyncStream<[String]>
    let continuation: AsyncStream<[String]>.Continuation

    init() {
        var continuation: AsyncStream<[String]>.Continuation!
        stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) {
            continuation = $0
        }
        self.continuation = continuation
    }
}

extension RoomTimelineModel {
    func observeProfiles() async {
        var observation: Task<Void, Never>?
        for await authors in profileAuthorUpdates.stream {
            guard !Task.isCancelled else { break }
            if let observation {
                observation.cancel()
                await observation.value
            }
            observation = Task { [weak self] in
                await self?.observeProfiles(authors: authors)
            }
        }
        observation?.cancel()
        await observation?.value
    }

    private func observeProfiles(authors: [String]) async {
        do {
            let clock = ContinuousClock()
            let started = clock.now
            let query = try await queryOpening.filter(
                engine,
                NMPFilter(
                    kinds: [0],
                    authors: .literal(Set(authors)),
                    limit: 1_000
                )
            )
            RoomOpenProbe.shared.recordObserve(
                .profiles,
                duration: started.duration(to: clock.now)
            )
            defer { query.cancel() }

            for try await batch in query {
                guard !Task.isCancelled else { return }
                RoomOpenProbe.shared.recordSnapshot(.profiles, rows: batch.rows)
                profiles = RoomProfileProjection.profiles(from: batch.rows)
                profileError = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            profileError = error.localizedDescription
            profileAuthorUpdates.continuation.finish()
        }
    }

    func publishProfileAuthors() {
        // Every person the timeline can name. For chat and for self-service
        // membership (9021/9022) that is the row's own author; for moderation
        // (9000/9001) it is additionally the `p` subject, who never authored
        // anything in the room.
        var authors = Set(
            chatRows
                .filter { $0.kind == RoomKind.chat || $0.kind == RoomKind.joinRequest
                    || $0.kind == RoomKind.leaveRequest }
                .map(\.pubkey)
        )
        authors.formUnion(activityRows.map(\.pubkey))
        authors.formUnion(members.map(\.pubkey))
        authors.formUnion(admins.map(\.pubkey))
        for row in chatRows
        where row.kind == RoomKind.putUser || row.kind == RoomKind.removeUser {
            authors.insert(row.pubkey)
            for tag in row.tags where tag.first == "p" && tag.count > 1 && !tag[1].isEmpty {
                authors.insert(tag[1])
            }
        }

        let snapshot = authors.sorted()
        guard snapshot != lastProfileAuthors else { return }
        lastProfileAuthors = snapshot
        profileAuthorUpdates.continuation.yield(snapshot)
    }
}
