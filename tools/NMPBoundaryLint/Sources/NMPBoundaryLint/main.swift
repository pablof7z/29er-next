import Foundation
import NMPBoundaryCore

struct Arguments {
    let root: URL
    let policy: URL
    let repositoryRoot: URL
    let project: URL
    let format: Format

    init(_ values: [String]) throws {
        var options: [String: String] = [:]
        var index = 1
        while index < values.count {
            let key = values[index]
            guard index + 1 < values.count else {
                throw CLIError.usage
            }
            options[key] = values[index + 1]
            index += 2
        }
        guard let root = options["--root"],
              let policy = options["--policy"],
              let project = options["--project"] else {
            throw CLIError.usage
        }
        let currentPath = FileManager.default.currentDirectoryPath
        let current = BoundaryPathResolution.resolve(".", relativeTo: currentPath)
        self.root = BoundaryPathResolution.resolve(root, relativeTo: currentPath)
        self.policy = BoundaryPathResolution.resolve(policy, relativeTo: currentPath)
        repositoryRoot = options["--repository-root"].map {
            BoundaryPathResolution.resolve($0, relativeTo: currentPath)
        } ?? current
        self.project = BoundaryPathResolution.resolve(project, relativeTo: currentPath)
        format = Format(options["--format"])
    }

    /// `exceptions` is the regeneration mode: it prints every violation as a
    /// `rule\tpath\tsymbol\tmatcher` row so the policy's exception list can
    /// be rebuilt from what the app actually does, instead of being kept in
    /// sync by hand. It never fails the run -- that is the point.
    enum Format {
        case text
        case githubActions
        case exceptions

        init(_ value: String?) {
            switch value {
            case "github-actions": self = .githubActions
            case "exceptions": self = .exceptions
            default: self = .text
            }
        }
    }
}

enum CLIError: Error, CustomStringConvertible {
    case usage

    var description: String {
        """
        Usage: nmp-boundary-lint --root PATH --policy PATH --project PATH \
        [--repository-root PATH] [--format github-actions|exceptions]
        """
    }
}

do {
    let arguments = try Arguments(CommandLine.arguments)
    let policy = try BoundaryPolicy.load(from: arguments.policy)
    try ProjectSourceCoverage.validate(
        project: arguments.project,
        scanRoot: arguments.root,
        repositoryRoot: arguments.repositoryRoot
    )
    let violations = try BoundaryLinter(policy: policy).lint(
        root: arguments.root,
        repositoryRoot: arguments.repositoryRoot
    )
    if arguments.format == .exceptions {
        for violation in violations {
            print(
                [violation.rule, violation.path, violation.symbol, violation.matcher]
                    .joined(separator: "\t")
            )
        }
        exit(0)
    }
    for violation in violations {
        if arguments.format == .githubActions {
            print(
                "::error file=\(violation.path),line=\(violation.line),"
                    + "col=\(violation.column),title=\(violation.rule)::"
                    + violation.message
            )
        } else {
            print(
                "\(violation.path):\(violation.line):\(violation.column): "
                    + "error: \(violation.rule) [\(violation.symbol)] \(violation.message)"
            )
        }
    }
    if !violations.isEmpty {
        FileHandle.standardError.write(
            Data("NMP boundary: \(violations.count) violation(s).\n".utf8)
        )
        exit(1)
    }
    print("NMP boundary: no violations.")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}
