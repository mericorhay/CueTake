import Domain
import Foundation

/// The real store: one directory per project, `project.json` inside it.
///
/// An actor rather than a struct because writes must not interleave — two saves of the same
/// project racing each other could leave a half-written document on disk, and the document is the
/// source of truth for everything the app knows.
///
/// Listing reads every document rather than keeping an index. That is the honest trade at this
/// size: a handful of small JSON files is faster to read than an index is to keep correct, and
/// `ProjectIndexEntry` exists for when the library outgrows it.
public actor FileProjectStore: ProjectStore {
    private let layout: ProjectLayout
    private let fileManager: FileManager

    public init(layout: ProjectLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    /// Projects live in Application Support, not Documents: they are app data, and the media
    /// beside them would otherwise show up in the Files app as loose recordings.
    public static func inApplicationSupport(fileManager: FileManager = .default) throws -> FileProjectStore {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appending(path: "Projects", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return FileProjectStore(layout: ProjectLayout(rootURL: root))
    }

    public func summaries() throws -> [ProjectSummary] {
        let directories = (try? fileManager.contentsOfDirectory(
            at: layout.rootURL,
            includingPropertiesForKeys: nil
        )) ?? []

        // A directory that fails to read is skipped rather than failing the whole listing: one
        // damaged project should not make the library unopenable.
        return directories
            .compactMap { directory -> Project? in
                guard let id = UUID(uuidString: directory.lastPathComponent) else { return nil }
                return try? read(id)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(ProjectSummary.init(project:))
    }

    public func mediaDirectory(for id: Project.ID) throws -> URL {
        let directory = layout.mediaDirectory(for: id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func load(_ id: Project.ID) throws -> Project {
        try read(id)
    }

    public func save(_ project: Project) throws {
        // Creating the media directory creates the project directory with it.
        try fileManager.createDirectory(
            at: layout.mediaDirectory(for: project.id),
            withIntermediateDirectories: true
        )
        // Atomic: a crash mid-write leaves the previous document intact instead of a truncated one.
        try ProjectDocumentCoder.encode(project)
            .write(to: layout.documentURL(for: project.id), options: .atomic)
    }

    public func delete(_ id: Project.ID) throws {
        try? fileManager.removeItem(at: layout.directory(for: id))
    }

    private func read(_ id: Project.ID) throws -> Project {
        let url = layout.documentURL(for: id)
        guard let data = try? Data(contentsOf: url) else {
            throw ProjectStoreError.notFound(id)
        }
        return try ProjectDocumentCoder.decode(data)
    }
}
