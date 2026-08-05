import Foundation

public enum BoundaryPathResolution {
    public static func resolve(
        _ path: String,
        relativeTo directoryPath: String
    ) -> URL {
        let resolved = path.hasPrefix("/")
            ? path
            : (directoryPath as NSString).appendingPathComponent(path)
        return URL(fileURLWithPath: (resolved as NSString).standardizingPath)
    }

    public static func relativePath(
        _ file: URL,
        repositoryRoot: URL
    ) -> String? {
        let filePath = (file.path as NSString).standardizingPath
        let rootPath = (repositoryRoot.path as NSString).standardizingPath
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }
}

public enum BoundaryLintError: Error, CustomStringConvertible {
    case missingSourceRoot(String)
    case noSwiftSources(String)
    case sourceOutsideRepository(String, String)
    case uncoveredApplicationSource(String, String)
    case invalidProjectSource(String)
    case exceptionOccurrenceMismatch([String])

    public var description: String {
        switch self {
        case .missingSourceRoot(let path):
            "NMP boundary source root does not exist: \(path)"
        case .noSwiftSources(let path):
            "NMP boundary source root contains no Swift sources: \(path)"
        case .sourceOutsideRepository(let source, let repository):
            "NMP boundary source \(source) is outside repository \(repository)"
        case .uncoveredApplicationSource(let source, let root):
            "Application source \(source) is not covered by scan root \(root)"
        case .invalidProjectSource(let project):
            "Could not find application source paths in \(project)"
        case .exceptionOccurrenceMismatch(let exceptions):
            "NMP boundary exception occurrence mismatch: \(exceptions.joined(separator: ", "))"
        }
    }
}
