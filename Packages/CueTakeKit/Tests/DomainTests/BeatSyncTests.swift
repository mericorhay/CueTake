import Foundation
import Testing
@testable import Domain

/// The camera moves on the music the video plays: beats found in the file's own time, moved and
/// trimmed with the clip, never closer than a punch can land and let go.
struct BeatSyncTests {
    @Test func beatsFollowTheMusicClipOnTheTimeline() {
        var music = AudioClip(
            name: "m", relativePath: "media/m.m4a", role: .music, start: MediaTime(seconds: 2),
            sourceRange: MediaTimeRange(start: MediaTime(seconds: 10), duration: MediaTime(seconds: 8))
        )
        music.beats = BeatGrid(bpm: 120, beats: [9.5, 10, 10.5, 11, 12, 20], downbeats: [10, 12, 20])
        var project = Project(title: "t", localeIdentifier: "en")
        project.audio = [music]
        // 9.5 and 20 are outside the part that plays; the rest move by start − source start.
        #expect(project.musicBeats(downbeats: false) == [2, 2.5, 3, 4])
        #expect(project.musicBeats(downbeats: true) == [2, 4])
    }

    @Test func punchesStayInsideClipsAndApart() {
        let segments = [
            Segment(role: .hook, script: "a", estimatedDuration: MediaTime(seconds: 5)),
            Segment(role: .mainPoint, script: "b", estimatedDuration: MediaTime(seconds: 5)),
        ]
        var project = Project(title: "t", localeIdentifier: "en", segments: segments)
        var music = AudioClip(name: "m", relativePath: "media/m.m4a", role: .music, sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 10)))
        music.beats = BeatGrid(bpm: 120, beats: Array(stride(from: 0.5, to: 10, by: 0.5)), downbeats: [0.5, 2.5, 4.5, 4.9, 6.5, 8.5])
        project.audio = [music]
        var document = EditDocument(project: project)
        for index in document.clips.indices {
            document.clips[index].at = Double(index) * 5
            document.clips[index].length = 5
        }
        let moves = BeatSync.plan(BeatSyncOptions(pulse: .bar), project: project, document: document).compactMap { op -> CameraMoveRequest? in
            if case .cameraMove(let request) = op { return request }
            return nil
        }
        // 4.9 is too close to 4.5; each move ends inside its clip.
        #expect(moves.compactMap(\.at) == [0.5, 2.5, 4.5, 6.5, 8.5])
        #expect(moves.allSatisfy { $0.kind == .punch })
        #expect((moves[2].to ?? 0) <= 4.95)
    }
}
