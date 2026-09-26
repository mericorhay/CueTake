import Foundation
import Testing
@testable import Domain
@testable import MediaEngine

/// What the storage sweep removes. The failure that matters is deleting footage a clip still uses,
/// so every case that should stay is checked as carefully as the ones that should go.
struct MediaJanitorTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "janitor-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ name: String, in folder: URL) {
        FileManager.default.createFile(atPath: folder.appending(path: name).path(percentEncoded: false), contents: Data(repeating: 1, count: 4096))
    }

    private func names(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [])
    }

    @Test func keepsWhatClipsUseAndRemovesTheRest() throws {
        let media = try folder()
        defer { try? FileManager.default.removeItem(at: media) }

        let used = Recording(relativePath: "media/used.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 5))
        let orphan = Recording(relativePath: "media/orphan.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 5))
        let take = Take(
            recordingID: used.id,
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 5)),
            status: .ready,
            transcript: Transcript(localeIdentifier: "en", words: [])
        )
        let segment = Segment(role: .hook, script: "", takes: [take], selectedTakeID: take.id)
        var project = Project(title: "t", localeIdentifier: "en", segments: [segment], recordings: [used, orphan])
        project.overlays = [Overlay(content: .image(relativePath: "media/overlay-1.png", aspect: 1), start: .zero)]

        for name in [
            "used.mov", "orphan.mov", "cover.jpg", "overlay-1.png", "overlay-old.png",
            "used-speech.m4a", "\(used.id.uuidString)-voice.m4a", "\(used.id.uuidString)-voice-nv2.m4a",
        ] {
            touch(name, in: media)
        }

        // The open project: only caches go.
        let cautious = MediaJanitor.clean(project: project, mediaDirectory: media, keepOriginals: true)
        #expect(cautious > 0)
        #expect(names(in: media) == ["used.mov", "orphan.mov", "cover.jpg", "overlay-1.png", "overlay-old.png"])

        // Any other project: whatever nothing uses goes too.
        _ = MediaJanitor.clean(project: project, mediaDirectory: media, keepOriginals: false)
        #expect(names(in: media) == ["used.mov", "cover.jpg", "overlay-1.png"])
    }

    @Test func aBoughtColourGradeIsNotACache() throws {
        let media = try folder()
        defer { try? FileManager.default.removeItem(at: media) }

        let recording = Recording(relativePath: "media/used.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 5))
        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 5)),
            status: .ready
        )
        let segment = Segment(role: .hook, script: "", takes: [take], selectedTakeID: take.id)
        var project = Project(title: "t", localeIdentifier: "en", segments: [segment], recordings: [recording])
        var settings = FilterSettings(look: .natural)
        settings.lut = LookUpTable(name: "Teal", file: "media/lut-1.cube", size: 33)
        project.effects = [TimelineEffect(start: .zero, duration: MediaTime(seconds: 5), kind: .filter(settings))]

        for name in ["used.mov", "lut-1.cube", "lut-old.cube"] { touch(name, in: media) }

        _ = MediaJanitor.clean(project: project, mediaDirectory: media, keepOriginals: false)
        let left = names(in: media)
        #expect(left.contains("lut-1.cube"))
        #expect(!left.contains("lut-old.cube"))
    }

    @Test func footageOnlyAnOldVersionUsesStays() throws {
        let media = try folder()
        defer { try? FileManager.default.removeItem(at: media) }

        let now = Recording(relativePath: "media/now.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 5))
        let before = Recording(relativePath: "media/before.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 5))
        func take(_ recording: Recording) -> Segment {
            let take = Take(recordingID: recording.id, sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 5)), status: .ready)
            return Segment(role: .hook, script: "", takes: [take], selectedTakeID: take.id)
        }
        let current = Project(title: "t", localeIdentifier: "en", segments: [take(now)], recordings: [now])
        let version = Project(title: "t", localeIdentifier: "en", segments: [take(before)], recordings: [before])

        for name in ["now.mov", "before.mov", "nobody.mov"] { touch(name, in: media) }

        _ = MediaJanitor.clean(project: current, mediaDirectory: media, keepOriginals: false, versions: [version])
        #expect(names(in: media) == ["now.mov", "before.mov"])
    }

    @Test func cachesTheCurrentSettingsReadStay() throws {
        let media = try folder()
        defer { try? FileManager.default.removeItem(at: media) }

        let recording = Recording(relativePath: "media/a.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 5))
        let take = Take(recordingID: recording.id, sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 5)), status: .ready)
        let segment = Segment(role: .hook, script: "", takes: [take], selectedTakeID: take.id)
        var project = Project(title: "t", localeIdentifier: "en", segments: [segment], recordings: [recording])
        project.voiceEffects = AudioEffects(noiseReduction: true, voiceEnhance: true)

        let id = recording.id.uuidString
        for name in ["a.mov", "a-speech.m4a", "\(id)-voice.m4a", "\(id)-voice-nv2.m4a", "\(id)-voice-r2.m4a"] {
            touch(name, in: media)
        }
        _ = MediaJanitor.clean(project: project, mediaDirectory: media, keepOriginals: false)
        // Not transcribed yet, so its extracted sound stays; the old switch combination goes.
        #expect(names(in: media) == ["a.mov", "a-speech.m4a", "\(id)-voice.m4a", "\(id)-voice-nv2.m4a"])
    }
}
