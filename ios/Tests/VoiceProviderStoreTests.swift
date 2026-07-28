import XCTest
@testable import TwentyNinerNext

@MainActor
final class VoiceProviderStoreTests: XCTestCase {
    func testStartsWithAppleBuiltInActive() {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let store = harness.makeStore()

        XCTAssertEqual(store.configurations, [.builtInApple])
        XCTAssertEqual(store.activeConfigurationID, VoiceProviderConfiguration.builtInAppleID)
        XCTAssertEqual(try store.snapshot().configuration.kind, .apple)
    }

    func testSupportsMultipleConfigurationsWithExactlyOneActive() throws {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let store = harness.makeStore()
        let secondApple = store.add(.apple)
        try store.activate(secondApple.id)

        XCTAssertEqual(store.configurations.count, 2)
        XCTAssertEqual(store.activeConfigurationID, secondApple.id)
        XCTAssertThrowsError(try store.delete(secondApple.id))

        try store.delete(VoiceProviderConfiguration.builtInAppleID)
        XCTAssertEqual(store.configurations.map(\.id), [secondApple.id])
    }

    func testIncompleteElevenLabsCannotBecomeActive() {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let store = harness.makeStore()
        let elevenLabs = store.add(.elevenLabs)

        XCTAssertFalse(store.isReady(elevenLabs))
        XCTAssertThrowsError(try store.activate(elevenLabs.id)) { error in
            XCTAssertEqual(error as? VoiceProviderConfigurationError, .missingCredential)
        }
        XCTAssertEqual(store.activeConfigurationID, VoiceProviderConfiguration.builtInAppleID)
    }

    func testElevenLabsCredentialLivesOutsideUserDefaults() throws {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let store = harness.makeStore()
        let elevenLabs = store.add(.elevenLabs)
        try store.save(elevenLabs, newCredential: "  secret-key-1234  ")
        try store.activate(elevenLabs.id)

        XCTAssertEqual(try store.snapshot().credential, "secret-key-1234")
        XCTAssertEqual(store.maskedCredential(for: elevenLabs.id), "••••1234")
        let persisted = try XCTUnwrap(
            harness.defaults.data(forKey: "voice.provider.configurations.v1")
        )
        XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains("secret-key"))
    }

    func testActiveSelectionPersistsAcrossInstances() throws {
        let harness = makeHarness()
        defer { harness.cleanUp() }
        let first = harness.makeStore()
        let secondApple = first.add(.apple)
        try first.activate(secondApple.id)

        let relaunched = harness.makeStore()

        XCTAssertEqual(relaunched.activeConfigurationID, secondApple.id)
        XCTAssertEqual(relaunched.configurations.count, 2)
    }

    private func makeHarness() -> ProviderStoreHarness {
        ProviderStoreHarness()
    }
}

@MainActor
private struct ProviderStoreHarness {
    let suite = "VoiceProviderStoreTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let credentials: VoiceCredentialStore

    init() {
        defaults = UserDefaults(suiteName: suite)!
        credentials = VoiceCredentialStore(service: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    func makeStore() -> VoiceProviderStore {
        VoiceProviderStore(defaults: defaults, credentials: credentials)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
    }
}
