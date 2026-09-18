import Domain
import Foundation

/// What the sync engine needs from the app: the projects on this phone, and a way to hand it the
/// ones that changed elsewhere. The app owns its projects; the engine only ever asks and tells.
@MainActor
public protocol TeamLibrary: AnyObject, Sendable {
    /// This phone's copy of a project, with whatever edits are open in the editor.
    func teamProject(_ id: Project.ID) async -> Project?
    /// A project as it now is after someone else's edits. The app shows it and saves it.
    func adoptFromTeam(_ project: Project) async
    /// A project a teammate removed from the team.
    func teamProjectRemoved(_ id: Project.ID) async
    /// Where this project's footage lives on this phone.
    func teamMediaDirectory(for id: Project.ID) async -> URL?
    /// Both sides changed the same things; this phone's changes were kept. For a quiet notice.
    func teamCollided(_ collisions: [ProjectMerge.Collision], in project: Project.ID) async
}

/// A team this phone belongs to.
public struct TeamInfo: Identifiable, Hashable, Sendable, Codable {
    public var id: String { zoneName + "|" + ownerName }
    public var zoneName: String
    public var ownerName: String
    public var name: String
    /// This phone's person made the team, so it lives in their iCloud and they manage who is in it.
    public var isOwner: Bool
    public var projects: [Project.ID]

    public init(zoneName: String, ownerName: String, name: String, isOwner: Bool, projects: [Project.ID] = []) {
        self.zoneName = zoneName
        self.ownerName = ownerName
        self.name = name
        self.isOwner = isOwner
        self.projects = projects
    }
}
