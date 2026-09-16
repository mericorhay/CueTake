import Domain
import Foundation

/// The user's own API keys for generation services, one Keychain item per provider.
///
/// Kept on this phone only (`…ThisDeviceOnly`), never in settings, backups or our server.
public struct ProviderKeyStore: Sendable {
    public init() {}

    private func store(_ provider: GenerationProviderID) -> KeychainStore {
        KeychainStore(account: "provider-key.\(provider.rawValue)")
    }

    public func key(for provider: GenerationProviderID) -> String? {
        guard let value = store(provider).read()?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    public func hasKey(for provider: GenerationProviderID) -> Bool {
        key(for: provider) != nil
    }

    @discardableResult
    public func save(_ key: String, for provider: GenerationProviderID) -> Bool {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        return store(provider).save(clean)
    }

    public func remove(for provider: GenerationProviderID) {
        store(provider).delete()
    }

    /// The last four characters, for showing which key is saved without showing the key.
    public func suffix(for provider: GenerationProviderID) -> String? {
        key(for: provider).map { String($0.suffix(4)) }
    }
}
