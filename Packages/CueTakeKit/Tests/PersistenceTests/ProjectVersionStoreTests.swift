import Foundation
import Testing
@testable import Domain
@testable import Persistence

struct ProjectVersionStoreTests {
    private func store() throws -> (FileProjectStore, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "versions-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (FileProjectStore(layout: ProjectLayout(rootURL: root)), root)
    }

    private func project(title: String = "Kahve", clips: Int = 2) -> Project {
        let recording = Recording(relativePath: "media/a.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 30))
        let made = (0..<clips).map { index -> Segment in
            let take = Take(
                recordingID: recording.id,
                sourceRange: MediaTimeRange(start: MediaTime(seconds: Double(index) * 3), duration: MediaTime(seconds: 3)),
                status: .ready
            )
            return Segment(role: .mainPoint, script: "", takes: [take], selectedTakeID: take.id)
        }
        return Project(title: title, localeIdentifier: "tr-TR", segments: made, recordings: [recording])
    }

    @Test func aVersionComesBackAsItWasSaved() async throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }

        var current = project()
        try await store.save(current)
        let version = try await store.saveVersion(of: current, name: "  Müşteriye giden  ", kind: .manual)
        #expect(version.name == "Müşteriye giden")
        #expect(version.clips == 2)

        // The project moves on…
        current.segments.removeLast()
        try await store.save(current)

        // …and the version still has what it had.
        let back = try await store.loadVersion(version.id, of: current.id)
        #expect(back.segments.count == 2)
        #expect(back.id == current.id)

        let listed = try await store.versions(of: current.id)
        let ids = listed.map(\.id)
        #expect(ids == [version.id])
    }

    @Test func automaticVersionsClearThemselvesOutButManualOnesStay() async throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }

        let current = project()
        try await store.save(current)
        let kept = try await store.saveVersion(of: current, name: "Benim", kind: .manual)
        for index in 0..<(ProjectVersion.automaticLimit + 3) {
            _ = try await store.saveVersion(of: current, name: "oto \(index)", kind: .automatic)
        }

        let listed = try await store.versions(of: current.id)
        let automatic = listed.filter { $0.kind == .automatic }
        #expect(automatic.count == ProjectVersion.automaticLimit)
        #expect(listed.contains { $0.id == kept.id })
        // The oldest automatic ones went, files and all.
        let names = automatic.map(\.name)
        #expect(!names.contains("oto 0"))
        let folder = ProjectLayout(rootURL: root).versionsDirectory(for: current.id)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(files.count == listed.count + 1)
    }

    @Test func aDeletedVersionIsGoneAndDeletingTheProjectTakesTheRest() async throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }

        let current = project()
        try await store.save(current)
        let first = try await store.saveVersion(of: current, name: "bir", kind: .manual)
        let second = try await store.saveVersion(of: current, name: "iki", kind: .manual)

        try await store.deleteVersion(first.id, of: current.id)
        let listed = try await store.versions(of: current.id)
        let ids = listed.map(\.id)
        #expect(ids == [second.id])
        await #expect(throws: ProjectStoreError.self) {
            _ = try await store.loadVersion(first.id, of: current.id)
        }

        try await store.delete(current.id)
        let after = try await store.versions(of: current.id)
        #expect(after.isEmpty)
    }

    @Test func aVersionOfAnotherProjectIsNotRestoredOverThisOne() async throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }

        let mine = project(title: "Benim")
        let theirs = project(title: "Başkası")
        try await store.save(mine)
        try await store.save(theirs)
        let version = try await store.saveVersion(of: theirs, name: "x", kind: .manual)

        // The document exists, but under someone else's project: asking for it as mine fails.
        await #expect(throws: ProjectStoreError.self) {
            _ = try await store.loadVersion(version.id, of: mine.id)
        }
    }
}
