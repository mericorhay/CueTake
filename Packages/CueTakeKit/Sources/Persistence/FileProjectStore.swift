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

    // MARK: - Versions

    public func versions(of id: Project.ID) throws -> [ProjectVersion] {
        readIndex(id).sorted { $0.savedAt > $1.savedAt }
    }

    public func saveVersion(of project: Project, name: String, kind: ProjectVersion.Kind) throws -> ProjectVersion {
        let folder = layout.versionsDirectory(for: project.id)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let version = ProjectVersion(of: project, name: name, kind: kind)
        // The list is read before the new document exists: with no index, reading rebuilds one
        // from the files on the disk, and it would count this version twice.
        var index = readIndex(project.id)

        // The document first, the index after: a crash between the two leaves an unlisted file,
        // never a listed version with nothing behind it.
        try ProjectDocumentCoder.encode(project)
            .write(to: document(version.id, in: folder), options: .atomic)

        index.append(version)
        let dropped = Set(ProjectVersion.overflow(in: index))
        index.removeAll { dropped.contains($0.id) }
        do {
            try writeIndex(index, for: project.id)
        } catch {
            // Unlisted, the document could never be opened or cleared out; take it back with the
            // failure rather than leave it on the disk for good.
            try? fileManager.removeItem(at: document(version.id, in: folder))
            throw error
        }
        for id in dropped {
            try? fileManager.removeItem(at: document(id, in: folder))
        }
        return version
    }

    public func loadVersion(_ version: ProjectVersion.ID, of id: Project.ID) throws -> Project {
        let url = document(version, in: layout.versionsDirectory(for: id))
        guard let data = try? Data(contentsOf: url) else { throw ProjectStoreError.notFound(version) }
        let project = try ProjectDocumentCoder.decode(data)
        // A version is a state of this project, never another one: a document that says otherwise
        // was put there by something else and is not restored over the user's work.
        guard project.id == id else { throw ProjectStoreError.notFound(version) }
        return project
    }

    public func deleteVersion(_ version: ProjectVersion.ID, of id: Project.ID) throws {
        var index = readIndex(id)
        index.removeAll { $0.id == version }
        try writeIndex(index, for: id)
        try? fileManager.removeItem(at: document(version, in: layout.versionsDirectory(for: id)))
    }

    private func document(_ version: ProjectVersion.ID, in folder: URL) -> URL {
        folder.appending(path: "\(version.uuidString).json", directoryHint: .notDirectory)
    }

    private func readIndex(_ id: Project.ID) -> [ProjectVersion] {
        let url = layout.versionsDirectory(for: id).appending(path: "index.json", directoryHint: .notDirectory)
        // Dates at full precision, not ISO 8601: that drops the fraction of a second, and two
        // automatic versions taken in the same second would no longer know which is older.
        if let data = try? Data(contentsOf: url),
           let index = try? JSONDecoder().decode([ProjectVersion].self, from: data) {
            return index
        }
        // No index, or one that no longer reads. An empty answer here would be written back by
        // the next save, and every version before it would vanish from the list while its file
        // stayed on the disk. So the list is rebuilt from the documents that are actually there.
        return recoveredIndex(id)
    }

    /// Versions found on the disk with no readable index: named by when they were written, and
    /// kept as the person's own so nothing trims them without being asked.
    private func recoveredIndex(_ id: Project.ID) -> [ProjectVersion] {
        let folder = layout.versionsDirectory(for: id)
        let files = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files.compactMap { file -> ProjectVersion? in
            guard file.pathExtension == "json",
                  let versionID = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: file),
                  let project = try? ProjectDocumentCoder.decode(data),
                  project.id == id
            else { return nil }
            let written = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now
            var version = ProjectVersion(of: project, name: project.title, kind: .manual, savedAt: written)
            version.id = versionID
            return version
        }
    }

    private func writeIndex(_ index: [ProjectVersion], for id: Project.ID) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = layout.versionsDirectory(for: id).appending(path: "index.json", directoryHint: .notDirectory)
        try encoder.encode(index).write(to: url, options: .atomic)
    }

    private func read(_ id: Project.ID) throws -> Project {
        let url = layout.documentURL(for: id)
        guard let data = try? Data(contentsOf: url) else {
            throw ProjectStoreError.notFound(id)
        }
        return try ProjectDocumentCoder.decode(data)
    }
}
