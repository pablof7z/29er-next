import Darwin
import Foundation

enum CrashSafeFile {
    static func replace(
        _ data: Data,
        at fileURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let directory = fileURL.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.synchronize()
                guard fcntl(handle.fileDescriptor, F_FULLFSYNC) == 0 else {
                    throw posixError()
                }
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            guard Darwin.rename(temporary.path, fileURL.path) == 0 else {
                throw posixError()
            }
            try synchronizeDirectory(directory)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    static func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw posixError() }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
