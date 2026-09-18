import CloudKit
import Foundation

/// Making a team, letting people into it, and joining one.
///
/// A team is a record zone in its maker's iCloud, shared whole: everything put in the zone is
/// seen by everyone let in. Nobody is let in by having the link — the share's public permission
/// is none — only people added by the maker, by their Apple ID. That is the security model, and
/// it is Apple's, not ours: there is no server of ours to breach.
public struct TeamSharing: Sendable {
    public static let zonePrefix = "team-"

    public enum Failure: Error, Equatable {
        case noICloud
        case notTheOwner
        case notFound
    }

    let container: CKContainer

    public init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
    }

    /// Whether this phone is signed in to iCloud at all. A team cannot exist without it.
    public func isAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    /// Makes a team: its zone, the record naming it, and the share that others join.
    public func makeTeam(named name: String) async throws -> (TeamInfo, CKShare) {
        guard await isAvailable() else { throw Failure.noICloud }
        let cleaned = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let zoneID = CKRecordZone.ID(zoneName: Self.zonePrefix + UUID().uuidString, ownerName: CKCurrentUserDefaultName)
        let database = container.privateCloudDatabase
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = cleaned as CKRecordValue
        share.publicPermission = .none
        let named = TeamRecords.teamRecord(named: cleaned, in: zoneID)
        let saved = try await database.modifyRecords(saving: [share, named], deleting: [])
        let savedShare = (try? saved.saveResults[share.recordID]?.get()) as? CKShare ?? share

        let team = TeamInfo(zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, name: cleaned, isOwner: true)
        return (team, savedShare)
    }

    /// The share of a team this phone owns, for the system's invite sheet.
    public func share(of team: TeamInfo) async throws -> CKShare {
        guard team.isOwner else { throw Failure.notTheOwner }
        let zoneID = CKRecordZone.ID(zoneName: team.zoneName, ownerName: CKCurrentUserDefaultName)
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        guard let share = try await container.privateCloudDatabase.record(for: id) as? CKShare else {
            throw Failure.notFound
        }
        return share
    }

    /// Lets one person in, by the identity their own phone sent over when the two phones met.
    /// They can edit; only the maker can let others in or out.
    public func letIn(_ userRecordID: CKRecord.ID, to team: TeamInfo) async throws -> URL? {
        let share = try await share(of: team)
        let lookup = CKUserIdentity.LookupInfo(userRecordID: userRecordID)
        let participants = try await container.shareParticipants(forUserIdentityLookupInfos: [lookup])
        guard let participant = try participants[lookup]?.get() else { throw Failure.notFound }
        participant.permission = .readWrite
        share.addParticipant(participant)
        _ = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        return share.url
    }

    /// This phone's person, as the other phone needs them to let them in.
    public func me() async throws -> CKRecord.ID {
        try await container.userRecordID()
    }

    /// Joins a team from an invite: a link from the system's sheet, or one handed over by a phone.
    public func join(_ url: URL) async throws -> TeamInfo {
        let metadata = try await container.shareMetadata(for: url)
        return try await accept(metadata)
    }

    /// Joins from metadata the system already fetched (an invite opened from Messages or Mail).
    public func accept(_ metadata: CKShare.Metadata) async throws -> TeamInfo {
        _ = try await container.accept([metadata])
        let zoneID = metadata.share.recordID.zoneID
        let title = metadata.share[CKShare.SystemFieldKey.title] as? String
        return TeamInfo(
            zoneName: zoneID.zoneName,
            ownerName: zoneID.ownerName,
            name: title ?? String(zoneID.zoneName.dropFirst(Self.zonePrefix.count)),
            isOwner: false
        )
    }

    /// Leaves a team this phone joined, or, for its maker, ends it for everyone.
    public func leave(_ team: TeamInfo) async throws {
        if team.isOwner {
            let zoneID = CKRecordZone.ID(zoneName: team.zoneName, ownerName: CKCurrentUserDefaultName)
            _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
        } else {
            let zoneID = CKRecordZone.ID(zoneName: team.zoneName, ownerName: team.ownerName)
            let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
            _ = try await container.sharedCloudDatabase.modifyRecords(saving: [], deleting: [id])
        }
    }
}
