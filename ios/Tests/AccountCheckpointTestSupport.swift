import Foundation
import NMP

final class MemoryAccountCheckpoint: NMPLocalAccountCheckpoint, @unchecked Sendable {
    private let lock = NSLock()
    private var secretKey: String?
    private(set) var loadCount = 0
    private(set) var saveCount = 0
    private(set) var clearCount = 0

    init(secretKey: String? = nil) {
        self.secretKey = secretKey
    }

    func loadSecretKey() -> String? {
        lock.withLock {
            loadCount += 1
            return secretKey
        }
    }

    func saveSecretKey(_ secretKey: String) {
        lock.withLock {
            saveCount += 1
            self.secretKey = secretKey
        }
    }

    func clear() {
        lock.withLock {
            clearCount += 1
            secretKey = nil
        }
    }
}
