import Domain
import Foundation

// A project is a directory:
//
//     Projects/<project-id>/
//         project.json     versioned Project document (source of truth)
//         media/           recording files, referenced by Recording.relativePath
//         versions/        saved states: index.json plus one project document each
//
// SwiftData only indexes projects for fast listing (see ProjectIndexEntry). It is never the
// domain model: @Model classes are not Sendable and do not keep array order.

public struct ProjectSummary: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var updatedAt: Date
    public var segmentCount: Int

    public init(project: Project) {
        self.id = project.id
        self.title = project.title
        self.updatedAt = project.updatedAt
        self.segmentCount = project.segments.count
    }
}

public enum ProjectStoreError: Error, Hashable, Sendable {
    case notFound(UUID)
    case newerSchema(found: Int, supported: Int)
}

public protocol ProjectStore: Sendable {
    /// Newest first.
    func summaries() async throws -> [ProjectSummary]
    /// Where this project's media files belong. Created if it does not exist yet.
    func mediaDirectory(for id: Project.ID) async throws -> URL
    func load(_ id: Project.ID) async throws -> Project
    func save(_ project: Project) async throws
    func delete(_ id: Project.ID) async throws

    /// Saved states of a project, newest first. See `ProjectVersion`.
    func versions(of id: Project.ID) async throws -> [ProjectVersion]
    /// Keeps `project` as it is now under `name`, throwing away automatic versions past the limit.
    func saveVersion(of project: Project, name: String, kind: ProjectVersion.Kind) async throws -> ProjectVersion
    func loadVersion(_ version: ProjectVersion.ID, of id: Project.ID) async throws -> Project
    func deleteVersion(_ version: ProjectVersion.ID, of id: Project.ID) async throws
}

/// Stores without somewhere to keep versions simply have none; the editor hides the list.
extension ProjectStore {
    public func versions(of id: Project.ID) async throws -> [ProjectVersion] { [] }
    public func saveVersion(of project: Project, name: String, kind: ProjectVersion.Kind) async throws -> ProjectVersion {
        throw ProjectStoreError.notFound(project.id)
    }
    public func loadVersion(_ version: ProjectVersion.ID, of id: Project.ID) async throws -> Project {
        throw ProjectStoreError.notFound(version)
    }
    public func deleteVersion(_ version: ProjectVersion.ID, of id: Project.ID) async throws {}
}

public struct ProjectLayout: Hashable, Sendable {
    public var rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func directory(for projectID: Project.ID) -> URL {
        rootURL.appending(path: projectID.uuidString, directoryHint: .isDirectory)
    }

    public func documentURL(for projectID: Project.ID) -> URL {
        directory(for: projectID).appending(path: "project.json", directoryHint: .notDirectory)
    }

    public func mediaDirectory(for projectID: Project.ID) -> URL {
        directory(for: projectID).appending(path: "media", directoryHint: .isDirectory)
    }

    /// Saved states: `versions/index.json` lists them, `versions/<id>.json` is each document.
    public func versionsDirectory(for projectID: Project.ID) -> URL {
        directory(for: projectID).appending(path: "versions", directoryHint: .isDirectory)
    }

    public func url(for recording: Recording, in projectID: Project.ID) -> URL {
        directory(for: projectID).appending(path: recording.relativePath, directoryHint: .notDirectory)
    }
}

public enum ProjectDocumentCoder {
    public static func encode(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(project)
    }

    public static func decode(_ data: Data) throws -> Project {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(Project.self, from: data)
        guard project.schemaVersion <= Project.currentSchemaVersion else {
            throw ProjectStoreError.newerSchema(found: project.schemaVersion, supported: Project.currentSchemaVersion)
        }
        return project
    }
}

/// For previews, tests and until the file-backed store lands.
public actor InMemoryProjectStore: ProjectStore {
    private var projects: [UUID: Project]

    public init(projects: [Project] = []) {
        self.projects = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    }

    public func summaries() -> [ProjectSummary] {
        projects.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(ProjectSummary.init(project:))
    }

    public func load(_ id: Project.ID) throws -> Project {
        guard let project = projects[id] else { throw ProjectStoreError.notFound(id) }
        return project
    }

    public func save(_ project: Project) {
        projects[project.id] = project
    }

    /// A scratch directory: this store forgets everything on relaunch anyway, so pointing media
    /// at the caches directory keeps the two halves telling the same story.
    public func mediaDirectory(for id: Project.ID) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "CueTake/\(id.uuidString)/media", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    public func delete(_ id: Project.ID) {
        projects[id] = nil
    }
}
