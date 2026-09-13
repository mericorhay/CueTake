import Foundation
import Security

/// A small secret kept in the Keychain rather than in settings.
///
/// Settings are a JSON blob in user defaults — readable in a backup, visible to anything that
/// inspects the app's container. An API key is not a preference, so it does not live there.
public struct KeychainStore: Sendable {
    public let account: String
    private let service = "com.orhay.cuetake"

    public init(account: String) {
        self.account = account
    }

    public func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func save(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]
        if SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) == errSecSuccess {
            return true
        }
        var insert = baseQuery
        insert[kSecValueData as String] = data
        // Never leaves this device, not even in an encrypted backup.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    public func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
