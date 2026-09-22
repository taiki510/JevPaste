import Foundation
import Security

final class KeychainStore {
    static let shared = KeychainStore()

    private let service = "local.taikigoto.jevpaste"

    func readAPIKey() -> String? {
        guard let data = read(account: "typesafe-api-key") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func saveAPIKey(_ key: String) -> Bool {
        save(Data(key.utf8), account: "typesafe-api-key")
    }

    @discardableResult
    func removeAPIKey() -> Bool {
        remove(account: "typesafe-api-key")
    }

    func readProfile() -> String? {
        guard let data = read(account: "smart-paste-profile") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func saveProfile(_ profile: String) -> Bool {
        save(Data(profile.utf8), account: "smart-paste-profile")
    }

    @discardableResult
    func removeProfile() -> Bool {
        remove(account: "smart-paste-profile")
    }

    func historyKey() throws -> Data {
        if let existing = read(account: "history-encryption-key"), existing.count == 32 {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecAllocate))
        }
        let data = Data(bytes)
        guard save(data, account: "history-encryption-key") else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecAuthFailed))
        }
        return data
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    private func save(_ data: Data, account: String) -> Bool {
        let query = baseQuery(account: account)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    private func remove(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
