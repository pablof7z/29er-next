import Foundation
import NMPBoundaryCore
import Testing

@Suite("NMP consumer boundary")
struct BoundaryLinterTests {
    private let fixtureRoot = Bundle.module.resourceURL!
        .appendingPathComponent("Fixtures", isDirectory: true)

    @Test(
        "Historical violations fail while supported facade examples pass",
        arguments: 1...8
    )
    func fixturePair(ruleNumber: Int) throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("Policy.json")
        )
        let linter = BoundaryLinter(policy: policy)
        let rule = String(format: "NMP%03d", ruleNumber)
        let negative = try fixture("Negative/\(rule).swift")
        let positive = try fixture("Positive/\(rule).swift")
        let negativePath = rule == "NMP003"
            ? "ios/Sources/BlossomAttachmentUploader.swift"
            : "ios/Sources/Fixture.swift"

        #expect(
            linter.lint(source: negative, path: negativePath).contains {
                $0.rule == rule
            }
        )
        #expect(
            !linter.lint(source: positive, path: "ios/Sources/Fixture.swift").contains {
                $0.rule == rule
            }
        )
    }

    @Test("Exception requires exact path and enclosing symbol")
    func exceptionScope() throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("Policy.json")
        )
        let source = """
        struct ConsentBridge {
            func handle() async throws {
                _ = try await engine.signEvent(event)
            }
            func bypass() async throws {
                _ = try await engine.signEvent(event)
            }
            func handleNested() async throws {
                func nested() async throws { _ = try await engine.signEvent(event) }
                _ = nested
            }
        }
        """
        let violations = BoundaryLinter(policy: policy).lint(
            source: source,
            path: "ios/Sources/ConsentBridge.swift"
        )

        #expect(violations.count == 2)
        #expect(violations.first?.symbol == "ConsentBridge.bypass")
        #expect(violations.last?.symbol == "ConsentBridge.handleNested.nested")
    }

    @Test("GitHub locations point at the offending syntax")
    func sourceLocation() throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("Policy.json")
        )
        let violations = BoundaryLinter(policy: policy).lint(
            source: "\nimport NMPFFI\n",
            path: "ios/Sources/Bad.swift"
        )

        #expect(violations.first?.line == 2)
        #expect(violations.first?.column == 1)
    }

    @Test("Local NIP-19 grammar is rejected independently of row parsing")
    func localEntityGrammar() throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("ProductionPolicy.json")
        )
        let source = """
        let expression = "(?:npub|nprofile|note|nevent|naddr)"
        """

        #expect(
            BoundaryLinter(policy: policy)
                .lint(source: source, path: "ios/Sources/EntityParser.swift")
                .contains { $0.rule == "NMP004" }
        )
    }

    @Test("Inferred unsigned payloads and alternate secret spellings are rejected")
    func inferredUnsignedAndSecretAliases() throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("Policy.json")
        )
        let source = """
        func compose() {
            let payload = .unsigned(event)
            defaults.set(private_key, forKey: "identity")
            _ = payload
        }
        """
        let violations = BoundaryLinter(policy: policy).lint(
            source: source,
            path: "ios/Sources/Fixture.swift"
        )

        #expect(violations.contains { $0.rule == "NMP001" })
        #expect(violations.contains { $0.rule == "NMP007" })
    }

    @Test("Row contexts catch aliases and key paths")
    func rowAliasesAndKeyPaths() throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("Policy.json")
        )
        let source = """
        func parse(rows: [Row]) {
            let raw = rows[0]
            _ = raw.tags
            _ = rows.map(\\.kind)
        }
        """
        let violations = BoundaryLinter(policy: policy).lint(
            source: source, path: "ios/Sources/Parser.swift"
        )
        #expect(violations.filter { $0.rule == "NMP004" }.count == 2)
    }

    @Test("Initializers and presentation storage cannot hide Row protocol inspection")
    func indirectPresentationRowAccess() throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("Policy.json")
        )
        let source = """
        struct BadView {
            let canonical: Row

            init(source: Row) {
                _ = source.kind
                canonical = source
            }

            var body: String {
                _ = canonical.tags
                _ = [canonical].map(\\.kind)
                return ""
            }
        }
        """
        let violations = BoundaryLinter(policy: policy).lint(
            source: source, path: "ios/Sources/BadView.swift"
        )

        #expect(violations.filter { $0.rule == "NMP004" }.count == 3)
    }

    @Test("A presentation helper named Row does not make product models event rows")
    func presentationRowName() throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("Policy.json")
        )
        let source = """
        func configurationRow(_ configuration: VoiceConfiguration) {
            _ = configuration.kind
        }
        """
        let violations = BoundaryLinter(policy: policy).lint(
            source: source, path: "ios/Sources/VoiceProviderListView.swift"
        )

        #expect(!violations.contains { $0.rule == "NMP004" })
    }

    @Test("Raw protocol helpers cannot hide kind and tag parsing behind parameters")
    func rawProtocolHelperSignatures() throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("Policy.json")
        )
        let source = """
        func decode(eventKind: UInt16, tags: [[String]]) -> [[String]] {
            let copy: [[String]] = tags
            return copy
        }
        """
        let violations = BoundaryLinter(policy: policy).lint(
            source: source, path: "ios/Sources/Parser.swift"
        )

        #expect(violations.filter { $0.rule == "NMP004" }.count == 4)
    }

    @Test("Raw tag casts are covered")
    func rawTagCast() throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("Policy.json")
        )
        let source = """
        func decode(_ value: Any) {
            _ = value as? [[String]]
        }
        """
        let violations = BoundaryLinter(policy: policy).lint(
            source: source, path: "ios/Sources/Parser.swift"
        )

        #expect(violations.contains { $0.rule == "NMP004" })
    }

    @Test("Application project source paths are covered by the scan root")
    func projectCoverage() throws {
        let project = fixtureRoot.appendingPathComponent("project.yml")
        #expect(try ProjectSourceCoverage.applicationSourcePaths(project: project) == ["ios/Sources"])
    }

    @Test("An unmatched exact exception fails a production-root scan")
    func staleException() throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("Policy.json")
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sources = root.appendingPathComponent("ios/Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "func harmless() {}".write(
            to: sources.appendingPathComponent("Fixture.swift"), atomically: true, encoding: .utf8
        )
        #expect(throws: BoundaryLintError.self) {
            try BoundaryLinter(policy: policy).lint(root: sources, repositoryRoot: root)
        }
    }

    @Test("A missing production root cannot pass vacuously")
    func missingRoot() throws {
        let policy = try BoundaryPolicy.load(
            from: fixtureRoot.appendingPathComponent("Policy.json")
        )
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        #expect(throws: BoundaryLintError.self) {
            try BoundaryLinter(policy: policy).lint(
                root: missing,
                repositoryRoot: missing.deletingLastPathComponent()
            )
        }
    }

    @Test("Relative CLI paths resolve beneath the working directory")
    func relativePathResolution() {
        let result = BoundaryPathResolution.resolve(
            "ios/Sources",
            relativeTo: "/private/tmp/29er-next"
        )

        #expect(result.path == "/private/tmp/29er-next/ios/Sources")
        #expect(
            BoundaryPathResolution.resolve(
                ".",
                relativeTo: "/private/tmp/29er-next"
            ).path == "/private/tmp/29er-next"
        )
    }

    @Test("Repository-relative paths preserve private filesystem aliases")
    func repositoryRelativePath() {
        let file = URL(
            fileURLWithPath: "/private/tmp/29er-next/ios/Sources/App.swift"
        )
        let root = BoundaryPathResolution.resolve(
            ".",
            relativeTo: "/private/tmp/29er-next"
        )

        #expect(
            BoundaryPathResolution.relativePath(file, repositoryRoot: root)
                == "ios/Sources/App.swift"
        )
    }

    private func fixture(_ path: String) throws -> String {
        try String(
            contentsOf: fixtureRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
