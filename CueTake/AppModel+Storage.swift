import Domain
import Foundation
import MediaEngine
import Persistence

/// Deleting projects, and keeping what the app stores down to what they use.
extension AppModel {
    /// Removes several projects and their media at once.
    ///
    /// If the open project is among them, the newest one left is opened instead, or an empty one.
    func deleteProjects(ids: [Project.ID]) async {
        let store = dependencies.projectStore
        for id in ids {
            try? await store.delete(id)
        }
        await refreshLibrary()
        await refreshStorage()

        guard ids.contains(project.id) else { return }
        if let next = library.first, let stored = try? await store.load(next.id) {
            adopt(stored)
        } else {
            adopt(Self.blankProject())
        }
    }

    /// Measures what the app takes on the phone, for Settings.
    func refreshStorage() async {
        storageBytes = await Task.detached(priority: .utility) { MediaJanitor.containerBytes() }.value
    }

    var storageLabel: String? {
        storageBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    /// Clears what nothing uses, from every project and the temporary folder. Returns bytes freed.
    ///
    /// Never while something is being imported, recorded or listened to: those write files that no
    /// project points at yet. The open project keeps recordings its clips no longer use, because
    /// the editor's undo can still bring those clips back; only its caches go.
    @discardableResult
    func cleanStorage(temporaryAge: TimeInterval) async -> Int64? {
        guard busy == nil, activity == nil, screen != .studio, screen != .retake else { return nil }
        if screen == .editor { adoptEditorEdits() }

        let store = dependencies.projectStore
        let open = project
        var jobs: [(project: Project, media: URL, keepOriginals: Bool)] = []
        for summary in (try? await store.summaries()) ?? [] {
            guard let media = try? await store.mediaDirectory(for: summary.id) else { continue }
            if summary.id == open.id {
                jobs.append((open, media, true))
            } else if let stored = try? await store.load(summary.id) {
                jobs.append((stored, media, false))
            }
        }
        let work = jobs
        return await Task.detached(priority: .utility) {
            var freed = MediaJanitor.cleanTemporaryFiles(olderThan: temporaryAge)
            for job in work {
                freed += MediaJanitor.clean(project: job.project, mediaDirectory: job.media, keepOriginals: job.keepOriginals)
            }
            return freed
        }.value
    }

    /// The Settings button.
    func cleanStorageNow() async {
        guard let freed = await cleanStorage(temporaryAge: 60) else {
            show(notice: String(localized: "storage.wait"))
            return
        }
        await refreshStorage()
        show(notice: freed > 1_000_000
            ? String(localized: "storage.cleaned \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))")
            : String(localized: "storage.nothing"))
    }

    /// A quiet sweep a little after launch, once the app has settled.
    func cleanStorageAfterLaunch() async {
        try? await Task.sleep(for: .seconds(8))
        await cleanStorage(temporaryAge: 3600)
    }
}
