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
            .task { report = await CorpusPreflightReport.make() }
    }
}

enum CorpusPreflightReport {
    private static let chunkSize = 4 * 1024 * 1024

    static func make() async -> String {
        await Task.detached(priority: .userInitiated) {
            do {
                let support = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false
                )
                let store = support
                    .appendingPathComponent("29er-next", isDirectory: true)
                    .appendingPathComponent("nmp.redb")
                return "complete size=\(try fileSize(store)) sha256=\(try sha256(store))"
            } catch {
                let message = error.localizedDescription
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "\n", with: "_")
                return "failed error=\(message)"
            }
        }.value
    }

    private static func fileSize(_ url: URL) throws -> UInt64 {
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
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
}
#endif
