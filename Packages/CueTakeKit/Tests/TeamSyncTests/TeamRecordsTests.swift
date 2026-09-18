import CloudKit
import Foundation
import Testing
@testable import Domain
@testable import TeamSync

struct TeamRecordsTests {
    private let zone = CKRecordZone.ID(zoneName: "team-test", ownerName: CKCurrentUserDefaultName)

    private func project() -> Project {
        let recording = Recording(relativePath: "media/a.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 20))
        let take = Take(recordingID: recording.id, sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 5)), status: .ready)
        var made = Project(
            title: "Kahve Lab",
            localeIdentifier: "tr-TR",
            segments: [Segment(role: .hook, script: "Merhaba", takes: [take], selectedTakeID: take.id)],
            recordings: [recording]
        )
        made.overlays = [Overlay(content: .image(relativePath: "media/logo.png", aspect: 1), start: .zero)]
        return made
    }

    @Test func aProjectComesBackFromItsRecordUnchanged() throws {
        let original = project()
        let record = try TeamRecords.newRecord(for: original, in: zone)
        #expect(record.recordID.recordName == original.id.uuidString)
        let back = try TeamRecords.project(from: record)
        // The same document; dates are kept to the second, as on disk.
        #expect(TeamRecords.same(back, original))
        #expect(back.segments == original.segments)
    }

    @Test func aProjectReadBackIsTheSameAsTheOneInMemory() throws {
        // What the loop guard rests on: a round trip through a document is "no change".
        let original = project()
        let back = try TeamRecords.project(from: TeamRecords.newRecord(for: original, in: zone))
        #expect(TeamRecords.same(original, back))
        var edited = back
        edited.title = "başka"
        #expect(!TeamRecords.same(original, edited))
    }

    @Test func theDocumentGoesInTheEncryptedFields() throws {
        let record = try TeamRecords.newRecord(for: project(), in: zone)
        let document = record.encryptedValues["document"] as? Data
        let title = record.encryptedValues["title"] as? String
        #expect(document?.isEmpty == false)
        #expect(title == "Kahve Lab")
        // The plain fields are a date and a number, and nothing else about the video.
        #expect(record["updatedAt"] as? Date != nil)
        #expect(record["schema"] as? Int != nil)
    }

    @Test func aRecordNamedForAnotherProjectIsRefused() throws {
        let original = project()
        let record = try TeamRecords.newRecord(for: original, in: zone)
        let other = CKRecord(recordType: TeamRecords.projectType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        other.encryptedValues["document"] = record.encryptedValues["document"]
        #expect(throws: TeamRecords.Failure.notAProject) {
            _ = try TeamRecords.project(from: other)
        }
    }

    @Test func everyFileTheProjectNeedsIsListedOnce() {
        let files = TeamRecords.mediaFiles(of: project())
        #expect(files == ["a.mov", "logo.png"])
    }
}
