import CloudKit
import Foundation
import TeamSync

/// What the team screens can do. The app owns the sync engine and the store; the screens ask.
public struct TeamTools {
    public var teams: [TeamInfo]
    /// The project open right now, if there is one to put in a team.
    public var currentProject: (id: UUID, title: String)?
    public var container: CKContainer

    public var makeTeam: (String) async throws -> TeamInfo
    public var share: (TeamInfo) async throws -> CKShare
    /// This phone's person, as CloudKit names them, for the other phone to let in.
    public var me: () async throws -> String
    /// Lets the person named in by the inviter's phone. Returns the way in to hand over.
    public var letIn: (String, TeamInfo) async throws -> URL?
    public var join: (URL) async throws -> TeamInfo
    public var addCurrentProject: (TeamInfo) async -> Void
    public var leave: (TeamInfo) async throws -> Void
    public var refresh: () async -> Void

    public init(
        teams: [TeamInfo],
        currentProject: (id: UUID, title: String)?,
        container: CKContainer,
        makeTeam: @escaping (String) async throws -> TeamInfo,
        share: @escaping (TeamInfo) async throws -> CKShare,
        me: @escaping () async throws -> String,
        letIn: @escaping (String, TeamInfo) async throws -> URL?,
        join: @escaping (URL) async throws -> TeamInfo,
        addCurrentProject: @escaping (TeamInfo) async -> Void,
        leave: @escaping (TeamInfo) async throws -> Void,
        refresh: @escaping () async -> Void
    ) {
        self.teams = teams
        self.currentProject = currentProject
        self.container = container
        self.makeTeam = makeTeam
        self.share = share
        self.me = me
        self.letIn = letIn
        self.join = join
        self.addCurrentProject = addCurrentProject
        self.leave = leave
        self.refresh = refresh
    }
}
