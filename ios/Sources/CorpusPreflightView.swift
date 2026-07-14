#if NMP_DEVICE_PROOF
import CryptoKit
import Foundation
import SwiftUI

struct CorpusPreflightView: View {
    @State private var report = "running"

    var body: some View {
        Text(report)
            .font(.system(.footnote, design: .monospaced))
            .padding()
            .accessibilityIdentifier("nmp-corpus-preflight")
            .task {
                report = await CorpusPreflightReport.make()
            }
    }
}

enum CorpusPreflightReport {
    private static let chunkSize = 4 * 1024 * 1024

    static func make() async -> String {
        await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            do {
                let support = try fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false
                )
                let directory = support.appendingPathComponent("29er-next", isDirectory: true)
                let store = directory.appendingPathComponent("nmp.redb")
                let marker = directory.appendingPathComponent("nmp-store-epoch")
                let size = try fileSize(store)
                let hash = try sha256(store)
                let epoch = try Data(contentsOf: marker)
                return [
                    "complete",
                    "size=\(size)",
                    "sha256=\(hash)",
                    "epochHex=\(epoch.hexString)",
                    "epoch=\(epoch.utf8String)"
                ].joined(separator: " ")
            } catch {
                return "failed error=\(sanitize(error.localizedDescription))"
            }
        }.value
    }

    private static func fileSize(_ url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw CocoaError(.fileReadUnknown)
        }
        return UInt64(size)
    }

    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: chunkSize)
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    var utf8String: String {
        String(decoding: self, as: UTF8.self)
            .trimmingCharacters(in: .newlines)
    }
}
#endif
