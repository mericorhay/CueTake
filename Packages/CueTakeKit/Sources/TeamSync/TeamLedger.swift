import CloudKit
import Domain
import Foundation
import Persistence

/// What the engine remembers between launches: its own CloudKit state, the teams, and for each
/// shared project the last version everyone agreed on.
///
/// That last agreed version is the whole trick. A merge needs three projects — the one both sides
/// started from, mine, theirs — and "the one both sides started from" is exactly the version this
/// phone last saved or fetched. Without it every edit made on two phones would be a collision.
actor TeamLedger {
    private let folder: URL
    private var files: FileManager { .default }

    init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: - Engine state

    func engineState(for scope: CKDatabase.Scope) -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: url("engine-\(scope.rawValue).plist")) else { return nil }
        return try? PropertyListDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    func saveEngineState(_ state: CKSyncEngine.State.Serialization, for scope: CKDatabase.Scope) {
        guard let data = try? PropertyListEncoder().encode(state) else { return }
        try? data.write(to: url("engine-\(scope.rawValue).plist"), options: .atomic)
    }

    // MARK: - Teams

    func teams() -> [TeamInfo] {
        guard let data = try? Data(contentsOf: url("teams.json")) else { return [] }
        return (try? JSONDecoder().decode([TeamInfo].self, from: data)) ?? []
    }

    func saveTeams(_ teams: [TeamInfo]) {
        guard let data = try? JSONEncoder().encode(teams) else { return }
        try? data.write(to: url("teams.json"), options: .atomic)
    }

    // MARK: - Per project

    /// The version this phone and the server last agreed on.
    func base(of id: Project.ID) -> Project? {
        guard let data = try? Data(contentsOf: url("\(id.uuidString).base.json")) else { return nil }
        return try? ProjectDocumentCoder.decode(data)
    }

    func setBase(_ project: Project) {
        guard let data = try? ProjectDocumentCoder.encode(project) else { return }
        try? data.write(to: url("\(project.id.uuidString).base.json"), options: .atomic)
    }

    /// The server's record as last seen: only its system fields, which carry the change tag a
    /// save is checked against. The document itself is in the base.
    func lastRecord(of id: Project.ID) -> CKRecord? {
        guard let data = try? Data(contentsOf: url("\(id.uuidString).record")),
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data)
        else { return nil }
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }

    func setLastRecord(_ record: CKRecord, of id: Project.ID) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        try? coder.encodedData.write(to: url("\(id.uuidString).record"), options: .atomic)
    }

    /// Which of a project's files are already in the team's storage, so none is sent twice.
    func uploaded(for id: Project.ID) -> Set<String> {
        guard let data = try? Data(contentsOf: url("\(id.uuidString).media.json")) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    func markUploaded(_ file: String, for id: Project.ID) {
        var done = uploaded(for: id)
        done.insert(file)
        guard let data = try? JSONEncoder().encode(done) else { return }
        try? data.write(to: url("\(id.uuidString).media.json"), options: .atomic)
    }

    func forget(_ id: Project.ID) {
        for suffix in ["base.json", "record", "media.json"] {
            try? files.removeItem(at: url("\(id.uuidString).\(suffix)"))
        }
    }

    /// Everything, for when the phone's Apple ID changes.
    func wipe() {
        let contents = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in contents { try? files.removeItem(at: file) }
    }

    private func url(_ name: String) -> URL {
        folder.appending(path: name, directoryHint: .notDirectory)
    }
}
