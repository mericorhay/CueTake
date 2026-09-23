import DesignSystem
import CloudKit
import Domain
import EditorFeature
import Foundation
import Persistence
import TeamFeature
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
        // Invites opened from Messages or Mail, including one that launched the app.
        ShareInbox.shared.onAccept = { [weak self] metadata in
            Task { await self?.acceptInvite(metadata) }
        }
    }

    private var teamSharing: TeamSharing { TeamSharing(containerIdentifier: Self.teamContainer) }

    func acceptInvite(_ metadata: CKShare.Metadata) async {
        guard let engine = teamSync else { return }
        do {
            let team = try await teamSharing.accept(metadata)
            await engine.adopt(team)
            await engine.refresh()
            teams = await engine.teams()
            show(notice: AppLocalization.string("team.joined \(team.name)"))
        } catch {
            show(notice: AppLocalization.string("team.joinFailed"))
        }
    }

    /// Everything the team screens can do, or nil in a build without teams.
    var teamTools: TeamTools? {
        guard let engine = teamSync else { return nil }
        let sharing = teamSharing
        return TeamTools(
            teams: teams,
            currentProject: projectHasContent ? (id: project.id, title: project.title) : nil,
            container: CKContainer(identifier: Self.teamContainer),
            makeTeam: { name in
                let (team, _) = try await sharing.makeTeam(named: name)
                await engine.adopt(team)
                return team
            },
            share: { team in try await sharing.share(of: team) },
            me: { try await sharing.me().recordName },
            letIn: { name, team in try await sharing.letIn(CKRecord.ID(recordName: name), to: team) },
            join: { url in
                let team = try await sharing.join(url)
                await engine.adopt(team)
                await engine.refresh()
                return team
            },
            addCurrentProject: { [weak self] team in
                guard let self else { return }
                takeEditorEditsIfEditing()
                await engine.add(project, to: team)
                teams = await engine.teams()
            },
            leave: { [weak self] team in
                try await sharing.leave(team)
                await engine.drop(team)
                self?.teams = await engine.teams()
            },
            refresh: { [weak self] in
                await engine.refresh()
                self?.teams = await engine.teams()
            }
        )
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
        show(notice: AppLocalization.string("team.collided \(collisions.count)"))
    }
}
