import Foundation
import NMPBoundaryCore
import Testing

@Suite("NMP boundary policy integrity")
struct BoundaryPolicyTests {
    private let fixtureRoot = Bundle.module.resourceURL!
        .appendingPathComponent("Fixtures", isDirectory: true)

    @Test("Production policy keeps every required rule")
    func productionPolicyShape() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let policy = try BoundaryPolicy.load(
            from: packageRoot.appendingPathComponent("Policy/nmp-boundary.json")
        )
        #expect(BoundaryPolicy.requiredRuleIDs.isSubset(of: Set(policy.rules.map(\.id))))
        #expect(policy.exceptions.allSatisfy { !$0.matcher.isEmpty })
    }

    @Test("Required matcher names cannot be weakened out of the policy")
    func requiredMatcherNames() throws {
        let source = try productionFixture()
        let weakened = source.replacingOccurrences(
            of: "\"names\":[\"WriteIntent\",\"NMPUnsignedEvent\"]",
            with: "\"names\":[\"HarmlessAlias\"]"
        )
        let file = try temporaryPolicy(weakened)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(throws: BoundaryPolicyError.self) {
            try BoundaryPolicy.load(from: file)
        }
    }

    @Test("Required matchers cannot be disabled with narrower predicates")
    func requiredMatcherScope() throws {
        let source = try productionFixture()
        let weakened = source.replacingOccurrences(
            of: "\"fileContains\":[\"Blossom\"]",
            with: "\"fileContains\":[\"NeverMatches\"]"
        )
        let file = try temporaryPolicy(weakened)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(throws: BoundaryPolicyError.self) {
            try BoundaryPolicy.load(from: file)
        }
    }

    @Test("Contains exceptions use the configured matcher rather than the full literal")
    func containsExceptionMatcherIdentity() throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("Policy.json")
        )
        let source = """
        struct LegacyCleanup {
            func remove() {
                _ = "local-account.nsec"
            }
        }
        """
        let violations = BoundaryLinter(policy: policy).lint(
            source: source,
            path: "ios/Sources/LegacyCleanup.swift"
        )

        #expect(violations.isEmpty)
    }

    @Test("An exception cannot absorb a second forbidden occurrence")
    func exactExceptionOccurrenceCount() throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("Policy.json")
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let sources = root.appendingPathComponent("ios/Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        struct ConsentBridge {
            func handle() async throws {
                _ = try await engine.signEvent(first)
                _ = try await engine.signEvent(second)
            }
        }
        """.write(
            to: sources.appendingPathComponent("ConsentBridge.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        struct LegacyCleanup {
            func remove() { _ = "local-account.nsec" }
        }
        """.write(
            to: sources.appendingPathComponent("LegacyCleanup.swift"),
            atomically: true,
            encoding: .utf8
        )

        do {
            _ = try BoundaryLinter(policy: policy).lint(
                root: sources,
                repositoryRoot: root
            )
            Issue.record("Expected an exception occurrence mismatch")
        } catch let error as BoundaryLintError {
            #expect(error.description.contains("expected 1, got 2"))
        }
    }

    private func productionFixture() throws -> String {
        try String(
            contentsOf: fixtureRoot.appendingPathComponent("ProductionPolicy.json"),
            encoding: .utf8
        )
    }

    private func temporaryPolicy(_ source: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try source.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
