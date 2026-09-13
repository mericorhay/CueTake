import Domain
import Foundation

/// Workflows on disk: one readable JSON file each.
///
/// Readable is the requirement, not a nicety. The file is the same document the studio's JSON
/// panel shows, the same one a model writes, and the same one someone can AirDrop to a friend —
/// so it is stored exactly as a person would want to open it, pretty-printed and sorted, rather
/// than in whatever form is cheapest to write.
///
/// An actor for the same reason the project store is: two saves of one file must not interleave.
public actor WorkflowStore {
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func inApplicationSupport(fileManager: FileManager = .default) throws -> WorkflowStore {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appending(path: "Workflows", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return WorkflowStore(root: root)
    }

    private func url(for id: UUID) -> URL {
        root.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    }

    /// Every stored workflow, most recently edited first. Seeds the built-ins the first time, and
    /// only the first time — deleting one should stay deleted.
    public func all() -> [WorkflowDefinition] {
        let marker = root.appending(path: ".seeded", directoryHint: .notDirectory)
        if !FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) {
            for workflow in WorkflowDefinition.builtIns {
                try? write(workflow)
            }
            FileManager.default.createFile(atPath: marker.path(percentEncoded: false), contents: Data())
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )) ?? []

        return files
            .filter { $0.pathExtension == "json" }
            // A file that no longer decodes is skipped rather than taking the whole list down with
            // it. One hand-edited workflow with a typo should not empty the screen.
            .compactMap { file in
                (try? String(contentsOf: file, encoding: .utf8)).flatMap { try? WorkflowDefinition.decode(json: $0) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ workflow: WorkflowDefinition) throws {
        var stamped = workflow
        stamped.updatedAt = .now
        try write(stamped)
    }

    public func delete(id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    private func write(_ workflow: WorkflowDefinition) throws {
        let json = try workflow.jsonString()
        try Data(json.utf8).write(to: url(for: workflow.id), options: .atomic)
    }
}
