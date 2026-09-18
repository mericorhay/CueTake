import CloudKit
import Domain
import Foundation
import Persistence

/// How a project is written into a team's shared iCloud zone, and read back.
///
/// One record per project, its whole document in one field. Field-per-property would let CloudKit
/// merge some edits by itself, but only the dumb way — last write per field — and the document
/// already has a proper three-way merge (`ProjectMerge`). One field also means one thing to
/// encrypt.
///
/// The document sits in `encryptedValues`: CloudKit encrypts those on the device with keys only
/// the team's members hold, so neither Apple's servers nor anyone with the database can read a
/// script. The title is encrypted too; the list decrypts it on the phone like everything else.
public enum TeamRecords {
    public static let projectType = "Project"
    public static let mediaType = "Media"
    public static let teamType = "Team"
    /// The one record every team zone has, naming it.
    public static let teamRecordName = "team"

    enum Field {
        static let document = "document"
        static let title = "title"
        static let updatedAt = "updatedAt"
        static let schema = "schema"
        static let file = "file"
        static let asset = "asset"
        static let project = "project"
        static let name = "name"
    }

    public enum Failure: Error, Equatable {
        case notAProject
        case unreadable
        case newerSchema(Int)
    }

    // MARK: - Projects

    public static func recordID(for project: Project.ID, in zone: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: project.uuidString, zoneID: zone)
    }

    /// Writes a project into a record — a fresh one, or the one last fetched from the server so
    /// the save carries the change tag CloudKit checks conflicts against.
    public static func write(_ project: Project, into record: CKRecord) throws {
        let json = try ProjectDocumentCoder.encode(project)
        let packed = try (json as NSData).compressed(using: .lzfse) as Data
        record.encryptedValues[Field.document] = packed
        record.encryptedValues[Field.title] = project.title
        // Plain on purpose: a date and a number say nothing about the video, and the list sorts
        // by the date without decrypting every document.
        record[Field.updatedAt] = project.updatedAt
        record[Field.schema] = project.schemaVersion
    }

    public static func newRecord(for project: Project, in zone: CKRecordZone.ID) throws -> CKRecord {
        let record = CKRecord(recordType: projectType, recordID: recordID(for: project.id, in: zone))
        try write(project, into: record)
        return record
    }

    public static func project(from record: CKRecord) throws -> Project {
        guard record.recordType == projectType else { throw Failure.notAProject }
        guard let packed = record.encryptedValues[Field.document] as? Data else { throw Failure.unreadable }
        let json: Data
        do {
            json = try (packed as NSData).decompressed(using: .lzfse) as Data
        } catch {
            throw Failure.unreadable
        }
        do {
            let project = try ProjectDocumentCoder.decode(json)
            // A document named for another project is not this record's project.
            guard project.id.uuidString == record.recordID.recordName else { throw Failure.notAProject }
            return project
        } catch let failure as Failure {
            throw failure
        } catch ProjectStoreError.newerSchema(let found, _) {
            // A teammate on a newer build. Their project is not overwritten with an older
            // understanding of it; this phone says to update instead.
            throw Failure.newerSchema(found)
        } catch {
            throw Failure.unreadable
        }
    }

    // MARK: - Media

    /// Footage and pictures, one record per file, named after the project and the file so the same
    /// file is never uploaded twice.
    public static func mediaID(project: Project.ID, file: String, in zone: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(project.uuidString)/\(file)", zoneID: zone)
    }

    public static func mediaRecord(project: Project.ID, file: URL, in zone: CKRecordZone.ID) -> CKRecord {
        let name = file.lastPathComponent
        let record = CKRecord(recordType: mediaType, recordID: mediaID(project: project, file: name, in: zone))
        record.encryptedValues[Field.file] = name
        record[Field.asset] = CKAsset(fileURL: file)
        record[Field.project] = CKRecord.Reference(
            recordID: recordID(for: project, in: zone),
            action: .deleteSelf
        )
        return record
    }

    /// The files a project needs beside its document for it to open whole on another phone.
    public static func mediaFiles(of project: Project) -> [String] {
        func name(_ path: String) -> String { (path as NSString).lastPathComponent }
        var files = Set(project.recordings.map { name($0.relativePath) })
        files.formUnion(project.audio.map { name($0.relativePath) })
        for overlay in project.overlays {
            if case .image(let path, _) = overlay.content { files.insert(name(path)) }
        }
        for effect in project.effects {
            if let table = effect.filter?.lut { files.insert(name(table.file)) }
        }
        return files.sorted()
    }

    // MARK: - Teams

    public static func teamRecord(named name: String, in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: teamType, recordID: CKRecord.ID(recordName: teamRecordName, zoneID: zone))
        record.encryptedValues[Field.name] = name
        return record
    }

    public static func teamName(from record: CKRecord) -> String? {
        record.encryptedValues[Field.name] as? String
    }
}
