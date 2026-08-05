func publish() async throws {
    _ = try await engine.publish(groupEvent)
}
