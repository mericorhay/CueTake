import CloudKit
import DesignSystem
import Domain
import SettingsFeature
import SwiftUI
import Foundation
import Observation
import UIKit

/// Projects kept in the creator's own iCloud: every project's document and media, file by file,
/// in the app's private CloudKit database. Private means only their Apple ID can read it, it counts
/// against their iCloud storage, and nothing passes through our server.
///
/// Only what changed since the last backup is sent. Caches the app can rebuild (the extracted
/// sound for listening, the cleaned voice) are left out. Restoring on a new phone writes back
/// whatever is missing and leaves what is already there alone.
///
/// Needs the `BackupFile` record type deployed to the CloudKit production schema (see
/// docs/CUETAKE_DARTBOARD.md); without it every save fails and says so.
@MainActor @Observable
final class CloudBackup {
    enum Phase: Equatable {
        case idle
        case backingUp(done: Int, of: Int)
        case restoring(done: Int, of: Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastBackup: Date? = UserDefaults.standard.object(forKey: CloudBackup.lastKey) as? Date
    var isOn = UserDefaults.standard.bool(forKey: CloudBackup.onKey) {
        didSet { UserDefaults.standard.set(isOn, forKey: Self.onKey) }
    }

    static let containerID = "iCloud.com.orhay.cuetake"
    static let recordType = "BackupFile"
    private static let onKey = "cuetake.icloud.backup.on"
    private static let lastKey = "cuetake.icloud.backup.last"
    private static let zoneID = CKRecordZone.ID(zoneName: "Backups", ownerName: CKCurrentUserDefaultName)

    private var database: CKDatabase { CKContainer(identifier: Self.containerID).privateCloudDatabase }

    var isBusy: Bool {
        switch phase {
        case .backingUp, .restoring: true
        default: false
        }
    }

    // MARK: - Files

    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Projects", directoryHint: .isDirectory)
    }

    /// What was sent last time: relative path to size and modification time.
    private static var manifestURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "icloud-backup.json", directoryHint: .notDirectory)
    }

    private struct Stamp: Codable, Equatable {
        var size: Int64
        var modified: Double
    }

    /// Caches rebuilt on demand; not worth anyone's iCloud space.
    private static func isCache(_ name: String) -> Bool {
        name.hasSuffix("-speech.m4a") || name.contains("-voice-") || name.hasPrefix("download-")
    }

    /// Every file worth keeping, as "projectID/relative/path".
    private static func localFiles() -> [String: (url: URL, stamp: Stamp)] {
        var found: [String: (URL, Stamp)] = [:]
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        else { return [:] }
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // Saved versions are history on this phone; the project itself is what matters.
            if path.contains("/versions/") || isCache(url.lastPathComponent) { continue }
            let stamp = Stamp(size: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
            found[path] = (url, stamp)
        }
        return found
    }

    private static func recordID(for path: String) -> CKRecord.ID {
        // Record names allow letters, digits and a few marks; a path is folded into those.
        let name = path.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? String($0) : "_" }.joined()
        return CKRecord.ID(recordName: String(name.suffix(250)), zoneID: zoneID)
    }

    // MARK: - Backup

    /// Sends what changed. `quietly` for the automatic one on leaving the app.
    func backUp() async {
        guard !isBusy else { return }
        do {
            try await ensureZone()
            let files = Self.localFiles()
            var manifest = Self.loadManifest()
            let changed = files.filter { manifest[$0.key] != $0.value.stamp }.sorted { $0.key < $1.key }
            phase = .backingUp(done: 0, of: changed.count)
            // One file a request: a long video is a large asset, and a failure costs only that file.
            for (index, item) in changed.enumerated() {
                let (path, file) = item
                let record = CKRecord(recordType: Self.recordType, recordID: Self.recordID(for: path))
                record["path"] = path as CKRecordValue
                record["project"] = String(path.prefix { $0 != "/" }) as CKRecordValue
                record["size"] = file.stamp.size as CKRecordValue
                record["modified"] = Date(timeIntervalSince1970: file.stamp.modified) as CKRecordValue
                record["file"] = CKAsset(fileURL: file.url)
                let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
                // A refused record is reported inside the result, not thrown.
                if case .failure(let error)? = result.saveResults[record.recordID] { throw error }
                manifest[path] = file.stamp
                Self.saveManifest(manifest)
                phase = .backingUp(done: index + 1, of: changed.count)
            }
            lastBackup = .now
            UserDefaults.standard.set(lastBackup, forKey: Self.lastKey)
            phase = .idle
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// The automatic backup when the app goes to the background, given the time iOS allows.
    func backUpInBackground() {
        guard isOn, !isBusy else { return }
        let task = BackgroundTask()
        task.id = UIApplication.shared.beginBackgroundTask(withName: "icloud-backup") {
            MainActor.assumeIsolated { task.end() }
        }
        Task {
            await backUp()
            task.end()
        }
    }

    // MARK: - Restore

    /// Writes back every backed-up file this phone does not have. Returns how many came back.
    @discardableResult
    func restore() async -> Int {
        guard !isBusy else { return 0 }
        do {
            // The list first, without the files; then only the missing ones are downloaded.
            var listed: [CKRecord] = []
            var token: CKServerChangeToken?
            var more = true
            while more {
                let changes = try await database.recordZoneChanges(
                    inZoneWith: Self.zoneID,
                    since: token,
                    desiredKeys: ["path", "size", "modified"]
                )
                for (_, result) in changes.modificationResultsByID {
                    if case .success(let modification) = result { listed.append(modification.record) }
                }
                token = changes.changeToken
                more = changes.moreComing
            }
            let local = Self.localFiles()
            let missing = listed.filter { record in
                guard let path = record["path"] as? String else { return false }
                return local[path] == nil
            }
            phase = .restoring(done: 0, of: missing.count)
            var restored = 0
            for record in missing {
                guard let path = record["path"] as? String else { continue }
                let fetched = try await database.records(for: [record.recordID])
                guard case .success(let full)? = fetched[record.recordID],
                      let asset = full["file"] as? CKAsset, let source = asset.fileURL
                else { continue }
                let destination = Self.root.appending(path: path, directoryHint: .notDirectory)
                try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: source, to: destination)
                restored += 1
                phase = .restoring(done: restored, of: missing.count)
            }
            // What came back counts as backed up, so it is not sent again.
            var manifest = Self.loadManifest()
            for (path, file) in Self.localFiles() where manifest[path] == nil { manifest[path] = file.stamp }
            Self.saveManifest(manifest)
            phase = .idle
            return restored
        } catch {
            phase = .failed(Self.describe(error))
            return 0
        }
    }

    // MARK: - Parts

    private func ensureZone() async throws {
        guard !UserDefaults.standard.bool(forKey: "cuetake.icloud.backup.zone") else { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.zoneID)], deleting: [])
        UserDefaults.standard.set(true, forKey: "cuetake.icloud.backup.zone")
    }

    private static func loadManifest() -> [String: Stamp] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Stamp].self, from: data)) ?? [:]
    }

    private static func saveManifest(_ manifest: [String: Stamp]) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    /// The reason in words people can act on, with CloudKit's own code and words after it, so a
    /// failure seen on a phone can be traced.
    private static func describe(_ error: Error) -> String {
        var error = error
        // Several records at once come back as one partial failure; the first real reason is inside.
        if let ck = error as? CKError, ck.code == .partialFailure,
           let first = ck.partialErrorsByItemID?.values.first {
            error = first
        }
        let ck = error as? CKError
        let reason: String = switch ck?.code {
        case .notAuthenticated: AppLocalization.string("icloud.error.signedOut")
        case .zoneNotFound, .userDeletedZone: AppLocalization.string("icloud.error.noBackup")
        case .quotaExceeded: AppLocalization.string("icloud.error.full")
        case .networkUnavailable, .networkFailure: AppLocalization.string("icloud.error.offline")
        // The record type is not in the production schema yet: nothing the user can do.
        case .serverRejectedRequest, .invalidArguments, .unknownItem: AppLocalization.string("icloud.error.setup")
        default: AppLocalization.string("icloud.error.generic")
        }
        let detail = (error as NSError).localizedDescription
        return "\(reason) (\(ck.map { "CKError \($0.code.rawValue)" } ?? "error"): \(detail.prefix(120)))"
    }
}

/// The time iOS gives a backup after the app leaves the screen, ended once whichever comes first.
@MainActor
private final class BackgroundTask: @unchecked Sendable {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

extension AppModel {
    /// Settings' iCloud section. Backing up is CueTake+; restoring what was backed up never is.
    var cloudBackupRow: CloudBackupRow {
        let backup = cloudBackup
        let plus = access.plan == .pro
        return CloudBackupRow(
            isOn: Binding(
                get: { backup.isOn && plus },
                set: { [weak self] on in
                    guard let self else { return }
                    if on {
                        guard self.access.use(.iCloudBackup) else { return }
                        backup.isOn = true
                        Task { await backup.backUp() }
                    } else {
                        backup.isOn = false
                    }
                }
            ),
            status: Self.backupStatus(backup),
            isBusy: backup.isBusy,
            locked: !plus,
            onBackup: { Task { await backup.backUp() } },
            onRestore: { [weak self] in
                Task {
                    let restored = await backup.restore()
                    await self?.refreshLibrary()
                    if case .failed = backup.phase { return }
                    self?.show(notice: AppLocalization.string("icloud.restored \(restored)"))
                }
            }
        )
    }

    static func backupStatus(_ backup: CloudBackup) -> String {
        switch backup.phase {
        case .backingUp(let done, let total): return AppLocalization.string("icloud.status.backingUp \(done) \(total)")
        case .restoring(let done, let total): return AppLocalization.string("icloud.status.restoring \(done) \(total)")
        case .failed(let reason): return reason
        case .idle:
            guard let last = backup.lastBackup else { return AppLocalization.string("icloud.status.never") }
            let when = last.formatted(.relative(presentation: .named).locale(AppLocalization.locale))
            return AppLocalization.string("icloud.status.last \(when)")
        }
    }
}
