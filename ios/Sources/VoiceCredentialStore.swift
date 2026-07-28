import Foundation
import Security

struct VoiceCredentialStore: Sendable {
    private let service: String

    init(service: String = "io.f7z.app29er.next.voice-providers") {
        self.service = service
    }

    func credential(for id: UUID) -> String? {
        var query = baseQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setCredential(_ value: String, for id: UUID) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            removeCredential(for: id)
            return
        }
        let query = baseQuery(id)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw VoiceCredentialError.keychain(addStatus)
            }
        } else if status != errSecSuccess {
            throw VoiceCredentialError.keychain(status)
        }
    }

    func removeCredential(for id: UUID) {
        SecItemDelete(baseQuery(id) as CFDictionary)
    }

    func maskedCredential(for id: UUID) -> String? {
        guard let value = credential(for: id), !value.isEmpty else { return nil }
        return "••••\(value.suffix(4))"
    }

    private func baseQuery(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
}

enum VoiceCredentialError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        "The API key could not be saved securely."
    }
}
