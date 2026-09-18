import CloudKit
import Domain
import Foundation
import os

/// Keeps a team's shared projects the same on every phone in it.
///
/// Built on `CKSyncEngine`, which does the parts that are easy to get wrong — batching, retrying,
/// waking on a push when a teammate saves, pausing without a network — and asks this class two
/// things: what to send, and what to do with what arrived. The answer to the second is always
/// the same: merge (`ProjectMerge`) against the last agreed version, keep the result, and send it
/// back if it contains anything the server does not have yet.
///
/// Two engines run: one for teams this phone's person made (their private database, where the
/// team zones live) and one for teams they joined (the shared database, the owners' zones as
/// CloudKit shows them to members).
public actor TeamSyncEngine: CKSyncEngineDelegate {
    private let container: CKContainer
    private let ledger: TeamLedger
    private weak var library: (any TeamLibrary)?
    private var engines: [CKDatabase.Scope: CKSyncEngine] = [:]
    /// What each save in flight contained, so the version the server accepted becomes the new base.
    private var inFlight: [CKRecord.ID: Project] = [:]
    private let log = Logger(subsystem: "com.orhay.cuetake", category: "team-sync")

    public init(containerIdentifier: String, folder: URL, library: any TeamLibrary) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.ledger = TeamLedger(folder: folder)
        self.library = library
    }

    /// Starts both engines. Safe to call more than once.
    public func start() async {
        for scope in [CKDatabase.Scope.private, .shared] where engines[scope] == nil {
            let database = scope == .private ? container.privateCloudDatabase : container.sharedCloudDatabase
            let saved = await ledger.engineState(for: scope)
            var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: saved, delegate: self)
            configuration.automaticallySync = true
            engines[scope] = CKSyncEngine(configuration)
        }
    }

    public func teams() async -> [TeamInfo] {
        await ledger.teams()
    }

    /// Asks both engines for what changed now, rather than waiting for the next push.
    public func refresh() async {
        for engine in engines.values {
            try? await engine.fetchChanges()
        }
    }

    // MARK: - Local changes going out

    /// A shared project was edited on this phone. It goes out with the next send.
    public func projectChanged(_ id: Project.ID) async {
        guard let (team, scope) = await team(containing: id) else { return }
        // A save of what just arrived is not a change. Without this, two phones would hand the
        // same project back and forth for ever: each saving what the other sent, each sending it.
        if let current = await library?.teamProject(id), let agreed = await ledger.base(of: id), current == agreed {
            return
        }
        let zone = zoneID(for: team)
        engines[scope]?.state.add(pendingRecordZoneChanges: [.saveRecord(TeamRecords.recordID(for: id, in: zone))])
        await queueMedia(for: id, in: zone, scope: scope)
    }

    /// Puts a project in a team: the document and every file it needs.
    public func add(_ project: Project, to team: TeamInfo) async {
        let scope: CKDatabase.Scope = team.isOwner ? .private : .shared
        var teams = await ledger.teams()
        if let index = teams.firstIndex(where: { $0.id == team.id }), !teams[index].projects.contains(project.id) {
            teams[index].projects.append(project.id)
            await ledger.saveTeams(teams)
        }
        let zone = zoneID(for: team)
        engines[scope]?.state.add(pendingRecordZoneChanges: [.saveRecord(TeamRecords.recordID(for: project.id, in: zone))])
        await queueMedia(for: project.id, in: zone, scope: scope)
    }

    private func queueMedia(for id: Project.ID, in zone: CKRecordZone.ID, scope: CKDatabase.Scope) async {
        guard let project = await library?.teamProject(id) else { return }
        let done = await ledger.uploaded(for: id)
        let pending = TeamRecords.mediaFiles(of: project).filter { !done.contains($0) }
        guard !pending.isEmpty else { return }
        engines[scope]?.state.add(pendingRecordZoneChanges: pending.map {
            .saveRecord(TeamRecords.mediaID(project: id, file: $0, in: zone))
        })
    }

    public nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await batch(context, syncEngine: syncEngine)
    }

    private func batch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        var records: [CKRecord.ID: CKRecord] = [:]
        for change in pending {
            guard case .saveRecord(let id) = change else { continue }
            if let record = await record(for: id) { records[id] = record }
        }
        let ready = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in ready[id] }
    }

    /// The record to send for an id: a project's document written into the last record the
    /// server gave (so the save carries its change tag), or a file.
    private func record(for id: CKRecord.ID) async -> CKRecord? {
        let name = id.recordName
        if let slash = name.firstIndex(of: "/"), let projectID = UUID(uuidString: String(name[..<slash])) {
            let file = String(name[name.index(after: slash)...])
            guard let folder = await library?.teamMediaDirectory(for: projectID) else { return nil }
            let url = folder.appending(path: file, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            return TeamRecords.mediaRecord(project: projectID, file: url, in: id.zoneID)
        }
        guard let projectID = UUID(uuidString: name), let project = await library?.teamProject(projectID) else { return nil }
        // Already what the server has: nothing to send (the engine drops the pending change).
        if let agreed = await ledger.base(of: projectID), agreed == project, await ledger.lastRecord(of: projectID) != nil {
            return nil
        }
        let record = await ledger.lastRecord(of: projectID) ?? CKRecord(recordType: TeamRecords.projectType, recordID: id)
        do {
            try TeamRecords.write(project, into: record)
        } catch {
            log.error("could not write project \(projectID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        inFlight[id] = project
        return record
    }

    // MARK: - Events

    public nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handle(event, syncEngine: syncEngine)
    }

    private func handle(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            await ledger.saveEngineState(update.stateSerialization, for: syncEngine.database.databaseScope)

        case .fetchedDatabaseChanges(let changes):
            await zonesChanged(changes, scope: syncEngine.database.databaseScope)

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                await arrived(modification.record, syncEngine: syncEngine)
            }
            for deletion in changes.deletions {
                if let id = UUID(uuidString: deletion.recordID.recordName) {
                    await ledger.forget(id)
                    await library?.teamProjectRemoved(id)
                }
            }

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                await saved(record)
            }
            for failure in sent.failedRecordSaves {
                await failed(failure.record, error: failure.error, syncEngine: syncEngine)
            }

        case .accountChange(let change):
            // Signed out, or into another Apple ID: another person's teams must not stay on the
            // phone — not the list, not the projects, not what was agreed with their server.
            if case .signIn = change.changeType { break }
            for team in await ledger.teams() {
                for project in team.projects { await library?.teamProjectRemoved(project) }
            }
            // The engine resets its own state for the new account; only what this code kept goes.
            await ledger.wipe()

        default:
            break
        }
    }

    private func zonesChanged(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges, scope: CKDatabase.Scope) async {
        var teams = await ledger.teams()
        for deletion in changes.deletions {
            teams.removeAll { $0.zoneName == deletion.zoneID.zoneName && $0.ownerName == deletion.zoneID.ownerName }
        }
        for modification in changes.modifications {
            let zone = modification.zoneID
            guard zone.zoneName.hasPrefix(TeamSharing.zonePrefix),
                  !teams.contains(where: { $0.zoneName == zone.zoneName && $0.ownerName == zone.ownerName })
            else { continue }
            teams.append(TeamInfo(
                zoneName: zone.zoneName,
                ownerName: zone.ownerName,
                name: String(zone.zoneName.dropFirst(TeamSharing.zonePrefix.count)),
                isOwner: scope == .private
            ))
        }
        await ledger.saveTeams(teams)
    }

    /// Someone else's save, or the first fetch of a team just joined.
    private func arrived(_ record: CKRecord, syncEngine: CKSyncEngine) async {
        switch record.recordType {
        case TeamRecords.teamType:
            guard let name = TeamRecords.teamName(from: record) else { return }
            var teams = await ledger.teams()
            if let index = teams.firstIndex(where: { $0.zoneName == record.recordID.zoneID.zoneName }) {
                teams[index].name = name
                await ledger.saveTeams(teams)
            }

        case TeamRecords.mediaType:
            await receiveMedia(record)

        case TeamRecords.projectType:
            guard let theirs = try? TeamRecords.project(from: record) else { return }
            await remember(theirs.id, in: record.recordID.zoneID)
            let base = await ledger.base(of: theirs.id)
            let mine = await library?.teamProject(theirs.id)
            await ledger.setLastRecord(record, of: theirs.id)

            guard let mine, let base, mine != base else {
                // Nothing here that the server does not already have: theirs simply stands.
                await ledger.setBase(theirs)
                await library?.adoptFromTeam(theirs)
                return
            }
            let merged = ProjectMerge.merge(base: base, mine: mine, theirs: theirs)
            await ledger.setBase(theirs)
            await library?.adoptFromTeam(merged.project)
            if !merged.collisions.isEmpty { await library?.teamCollided(merged.collisions, in: theirs.id) }
            // What was merged in from this phone still has to reach the others.
            if merged.project != theirs {
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            }

        default:
            break
        }
    }

    private func receiveMedia(_ record: CKRecord) async {
        let name = record.recordID.recordName
        guard let slash = name.firstIndex(of: "/"),
              let projectID = UUID(uuidString: String(name[..<slash])),
              let asset = record["asset"] as? CKAsset,
              let source = asset.fileURL,
              let folder = await library?.teamMediaDirectory(for: projectID)
        else { return }
        let file = String(name[name.index(after: slash)...])
        // Only a plain file name: a record naming "../" must not write outside the project.
        guard !file.contains("/"), !file.hasPrefix(".") else { return }
        let destination = folder.appending(path: file, directoryHint: .notDirectory)
        guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else { return }
        try? FileManager.default.copyItem(at: source, to: destination)
        await ledger.markUploaded(file, for: projectID)
    }

    private func saved(_ record: CKRecord) async {
        let name = record.recordID.recordName
        if let slash = name.firstIndex(of: "/"), let projectID = UUID(uuidString: String(name[..<slash])) {
            await ledger.markUploaded(String(name[name.index(after: slash)...]), for: projectID)
            return
        }
        guard let projectID = UUID(uuidString: name) else { return }
        await ledger.setLastRecord(record, of: projectID)
        if let sent = inFlight.removeValue(forKey: record.recordID) {
            await ledger.setBase(sent)
        }
    }

    private func failed(_ record: CKRecord, error: CKError, syncEngine: CKSyncEngine) async {
        inFlight[record.recordID] = nil
        switch error.code {
        case .serverRecordChanged:
            // Someone saved first. Their version is taken in, merged with this phone's, and the
            // result is sent again on top of theirs.
            if let server = error.serverRecord {
                await arrived(server, syncEngine: syncEngine)
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            }
        case .zoneNotFound, .userDeletedZone:
            // The team is gone; nothing to send it to.
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        case .unknownItem:
            // The server forgot the record; send it fresh without the old change tag.
            if let id = UUID(uuidString: record.recordID.recordName) { await ledger.forget(id) }
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        default:
            // Network, quota and throttling are retried by the engine on its own.
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers

    private func remember(_ project: Project.ID, in zone: CKRecordZone.ID) async {
        var teams = await ledger.teams()
        guard let index = teams.firstIndex(where: { $0.zoneName == zone.zoneName && $0.ownerName == zone.ownerName }),
              !teams[index].projects.contains(project)
        else { return }
        teams[index].projects.append(project)
        await ledger.saveTeams(teams)
    }

    private func team(containing id: Project.ID) async -> (TeamInfo, CKDatabase.Scope)? {
        guard let team = await ledger.teams().first(where: { $0.projects.contains(id) }) else { return nil }
        return (team, team.isOwner ? .private : .shared)
    }

    func zoneID(for team: TeamInfo) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: team.zoneName, ownerName: team.ownerName)
    }

    /// Forgets a team this phone left or ended.
    public func drop(_ team: TeamInfo) async {
        var teams = await ledger.teams()
        teams.removeAll { $0.id == team.id }
        await ledger.saveTeams(teams)
    }

    /// Adds a team this phone made or joined, so its projects are followed from now on.
    public func adopt(_ team: TeamInfo) async {
        var teams = await ledger.teams()
        teams.removeAll { $0.id == team.id }
        teams.append(team)
        await ledger.saveTeams(teams)
        if team.isOwner {
            engines[.private]?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID(for: team)))])
        }
    }
}
