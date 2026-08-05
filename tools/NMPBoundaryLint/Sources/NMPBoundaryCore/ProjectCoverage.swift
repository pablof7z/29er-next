import Foundation

public enum ProjectSourceCoverage {
    public static func validate(
        project: URL,
        scanRoot: URL,
        repositoryRoot: URL
    ) throws {
        let sourcePaths = try applicationSourcePaths(project: project)
        let normalizedRoot = scanRoot.standardizedFileURL.path
        for sourcePath in sourcePaths {
            let source = repositoryRoot.appendingPathComponent(sourcePath)
                .standardizedFileURL.path
            guard source == normalizedRoot || source.hasPrefix(normalizedRoot + "/") else {
                throw BoundaryLintError.uncoveredApplicationSource(sourcePath, normalizedRoot)
            }
        }
    }

    public static func applicationSourcePaths(project: URL) throws -> [String] {
        let lines = try String(contentsOf: project, encoding: .utf8).split(separator: "\n")
        var targetIsApplication = false
        var sourcesIndent: Int?
        var paths: [String] = []

        for rawLine in lines {
            let line = String(rawLine)
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if indent == 2, trimmed.hasSuffix(":") {
                targetIsApplication = false
                sourcesIndent = nil
                continue
            }
            if trimmed == "type: application" {
                targetIsApplication = true
                continue
            }
            if trimmed == "sources:" {
                sourcesIndent = indent
                continue
            }
            guard let sourcesIndent, indent > sourcesIndent else {
                if sourcesIndent != nil, indent <= (sourcesIndent ?? 0) { sourcesIndent = nil }
                continue
            }
            guard targetIsApplication,
                  trimmed.hasPrefix("- path:") else { continue }
            let value = trimmed.dropFirst("- path:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !value.isEmpty else { throw BoundaryLintError.invalidProjectSource(project.path) }
            paths.append("ios/\(value)")
        }
        guard !paths.isEmpty else { throw BoundaryLintError.invalidProjectSource(project.path) }
        return paths
    }
}
