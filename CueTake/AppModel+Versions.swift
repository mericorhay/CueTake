import Domain
import EditorFeature
import Foundation
import Persistence

/// Saved states of the open project: taken by hand, or by the app before something big.
extension AppModel {
    /// Shared projects need iCloud on the developer account and in the signing profile. A build
    /// says whether it has them with the `CUETAKE_TEAMS` condition, so switching teams on is a
    /// change of configuration — and a build without it never touches CloudKit.
    var isTeamSharingAvailable: Bool {
        #if CUETAKE_TEAMS
        true
        #else
        false
        #endif
    }

    var versionTools: VersionTools {
        VersionTools(
            versions: projectVersions,
            save: { [weak self] name in Task { await self?.saveVersion(named: name, kind: .manual) } },
            restore: { [weak self] version in Task { await self?.restoreVersion(version) } },
            delete: { [weak self] id in Task { await self?.deleteVersion(id) } },
            refresh: { [weak self] in Task { await self?.refreshVersions() } }
        )
    }

    func refreshVersions() async {
        projectVersions = (try? await dependencies.projectStore.versions(of: project.id)) ?? []
    }

    /// Keeps the project as it is now. The open editor's edits are taken first, or the version
    /// would be of the state before them.
    @discardableResult
    func saveVersion(named name: String, kind: ProjectVersion.Kind) async -> ProjectVersion? {
        takeEditorEditsIfEditing()
        do {
            let version = try await dependencies.projectStore.saveVersion(of: project, name: name, kind: kind)
            if kind == .manual { noteCertifiedVersion() }
            await refreshVersions()
            if kind == .manual {
                show(notice: String(localized: "versions.saved \(version.name)"))
            }
            return version
        } catch {
            if kind == .manual { show(notice: String(localized: "versions.saveFailed")) }
            return nil
        }
    }

    /// A version worth having if something goes wrong later in this session: taken when the editor
    /// opens, at most once an hour.
    func takeAutomaticVersionIfDue() async {
        guard !project.segments.isEmpty else { return }
        let existing = (try? await dependencies.projectStore.versions(of: project.id)) ?? []
        guard ProjectVersion.wantsAutomatic(since: existing) else {
            projectVersions = existing
            return
        }
        await saveVersion(named: String(localized: "versions.auto.opened"), kind: .automatic)
    }

    /// Goes back to a version. What is open now is kept as a version first, so going back is
    /// itself something that can be gone back from — including after the editor has closed and
    /// undo is gone.
    func restoreVersion(_ version: ProjectVersion) async {
        guard screen == .editor else { return }
        let store = dependencies.projectStore
        guard let saved = try? await store.loadVersion(version.id, of: project.id) else {
            show(notice: String(localized: "versions.missing"))
            return
        }
        await saveVersion(named: String(localized: "versions.auto.beforeRestore"), kind: .automatic)
        editorModel.restore(saved)
        adoptEditorEdits()
        scheduleSave()
        show(notice: String(localized: "versions.restored \(version.name)"))
    }

    func deleteVersion(_ id: ProjectVersion.ID) async {
        try? await dependencies.projectStore.deleteVersion(id, of: project.id)
        await refreshVersions()
    }
}
