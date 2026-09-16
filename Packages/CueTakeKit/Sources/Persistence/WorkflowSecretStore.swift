import Foundation

/// The secret each workflow's delivery sends — an API token — one Keychain item per workflow.
///
/// Not in the workflow document: that is shared, pasted into AI conversations and copied between
/// people. A duplicated workflow starts without a secret on purpose.
public struct WorkflowSecretStore: Sendable {
    public init() {}

    private func store(_ workflow: UUID) -> KeychainStore {
        KeychainStore(account: "workflow-api.\(workflow.uuidString)")
    }

    public func secret(for workflow: UUID) -> String? {
        guard let value = store(workflow).read()?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    @discardableResult
    public func save(_ secret: String, for workflow: UUID) -> Bool {
        let clean = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            remove(for: workflow)
            return true
        }
        return store(workflow).save(clean)
    }

    public func remove(for workflow: UUID) {
        store(workflow).delete()
    }

    /// The last four characters, to show which secret is saved without showing it.
    public func suffix(for workflow: UUID) -> String? {
        secret(for: workflow).map { String($0.suffix(4)) }
    }
}
