import Domain
import Foundation

/// Assistant conversations on disk, one JSON file per session.
///
/// Local only. Conversations are sent to the assistant when a message is sent and are not kept
/// anywhere else by the app, so deleting a session here is deleting it — which is the promise the
/// delete button makes, and the only one worth making.
public actor AssistantStore {
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func inApplicationSupport(fileManager: FileManager = .default) throws -> AssistantStore {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appending(path: "Assistant", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return AssistantStore(root: root)
    }

    private func url(for id: UUID) -> URL {
        root.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    }

    /// Every session, most recent first. A file that does not decode is skipped, not fatal.
    public func all() -> [AssistantSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(AssistantSession.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ session: AssistantSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(session).write(to: url(for: session.id), options: .atomic)
    }

    public func delete(id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    public func deleteAll() {
        for session in all() {
            delete(id: session.id)
        }
    }
}
