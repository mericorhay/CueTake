import Domain
import Foundation
import Persistence
import TeamSync

/// Shared team projects: this app's side of `TeamSyncEngine`.
///
/// Nothing here runs unless the build carries the iCloud entitlement (`isTeamSharingAvailable`);
/// a CloudKit call from a build without it ends the app, so the engine is never even made.
extension AppModel: TeamLibrary {
    static let teamContainer = "iCloud.com.orhay.cuetake"

    /// Starts following the teams this phone belongs to. Called once the library has loaded.
    func startTeams() async {
        guard isTeamSharingAvailable, teamSync == nil else { return }
        let folder = URL.applicationSupportDirectory.appending(path: "TeamSync", directoryHint: .isDirectory)
        let engine = TeamSyncEngine(containerIdentifier: Self.teamContainer, folder: folder, library: self)
        teamSync = engine
        await engine.start()
        teams = await engine.teams()
    }

    /// After a project is saved: if it is shared, the team hears about it.
    func projectWasSaved(_ id: Project.ID) {
        guard let engine = teamSync else { return }
        Task { await engine.projectChanged(id) }
    }

    // MARK: - TeamLibrary

    func teamProject(_ id: Project.ID) async -> Project? {
        if id == project.id {
            takeEditorEditsIfEditing()
            return project
        }
        return try? await dependencies.projectStore.load(id)
    }

    func adoptFromTeam(_ incoming: Project) async {
        if incoming.id == project.id {
            // The open project changed on someone else's phone. It is put in place as it stands —
            // the merge already kept every edit made here — and the editor follows.
            project = incoming
            if screen == .editor { editorModel.project = incoming }
        }
        try? await dependencies.projectStore.save(incoming)
        await refreshLibrary()
    }

    func teamProjectRemoved(_ id: Project.ID) async {
        if id == project.id, screen == .editor || screen == .studio {
            go(to: .home)
        }
        try? await dependencies.projectStore.delete(id)
        await refreshLibrary()
    }

    func teamMediaDirectory(for id: Project.ID) async -> URL? {
        try? await dependencies.projectStore.mediaDirectory(for: id)
    }

    func teamCollided(_ collisions: [ProjectMerge.Collision], in project: Project.ID) async {
        guard !collisions.isEmpty else { return }
        show(notice: String(localized: "team.collided \(collisions.count)"))
    }
}
