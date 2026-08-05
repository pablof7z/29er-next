import Foundation
import SwiftParser

public struct BoundaryViolation: Hashable, Sendable {
    public let rule, message, path, symbol, matcher: String
    public let line, column: Int

    public init(
        rule: String,
        message: String,
        path: String,
        line: Int,
        column: Int,
        symbol: String,
        matcher: String
    ) {
        self.rule = rule; self.message = message; self.path = path
        self.line = line; self.column = column; self.symbol = symbol
        self.matcher = matcher
    }
}

public struct BoundaryLintResult: Sendable {
    public let violations: [BoundaryViolation]
    public let matchedExceptionCounts: [String: Int]
}

public struct BoundaryLinter: Sendable {
    private let policy: BoundaryPolicy
    public init(policy: BoundaryPolicy) { self.policy = policy }

    public func lint(source: String, path: String) -> [BoundaryViolation] {
        detailedLint(source: source, path: path).violations
    }

    public func detailedLint(source: String, path: String) -> BoundaryLintResult {
        let tree = Parser.parse(source: source)
        let rowStorage = RowStorageCollector(viewMode: .sourceAccurate)
        rowStorage.walk(tree)
        let visitor = BoundaryVisitor(
            policy: policy,
            path: normalize(path),
            tree: tree,
            source: source,
            rowStorageNames: rowStorage.names
        )
        visitor.walk(tree)
        return BoundaryLintResult(
            violations: visitor.violations.sorted(by: order),
            matchedExceptionCounts: visitor.matchedExceptionCounts
        )
    }

    public func lint(root: URL, repositoryRoot: URL) throws -> [BoundaryViolation] {
        let files = try swiftFiles(at: root)
        let results = try files.map { file in
            guard let path = BoundaryPathResolution.relativePath(file, repositoryRoot: repositoryRoot) else {
                throw BoundaryLintError.sourceOutsideRepository(file.path, repositoryRoot.path)
            }
            return detailedLint(source: try String(contentsOf: file, encoding: .utf8), path: path)
        }
        var observed: [String: Int] = [:]
        for result in results {
            for (key, count) in result.matchedExceptionCounts {
                observed[key, default: 0] += count
            }
        }
        let mismatched = policy.exceptions.compactMap { exception -> String? in
            let key = exceptionKey(exception)
            let actual = observed[key, default: 0]
            guard actual != exception.expectedOccurrences else { return nil }
            return "\(key) expected \(exception.expectedOccurrences), got \(actual)"
        }
        guard mismatched.isEmpty else {
            throw BoundaryLintError.exceptionOccurrenceMismatch(mismatched)
        }
        return results.flatMap(\.violations)
    }

    private func swiftFiles(at root: URL) throws -> [URL] {
        var directory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else {
            throw BoundaryLintError.missingSourceRoot(root.path)
        }
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        guard !files.isEmpty else { throw BoundaryLintError.noSwiftSources(root.path) }
        return files.sorted { $0.path < $1.path }
    }

    private func normalize(_ path: String) -> String { path.replacingOccurrences(of: "\\", with: "/") }
    private func exceptionKey(_ value: BoundaryException) -> String { "\(value.rule)|\(value.path)|\(value.symbol)|\(value.matcher)" }
    private func order(_ lhs: BoundaryViolation, _ rhs: BoundaryViolation) -> Bool {
        if lhs.path != rhs.path { return lhs.path < rhs.path }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        if lhs.column != rhs.column { return lhs.column < rhs.column }
        return lhs.rule < rhs.rule
    }
}
