import Foundation
import Testing
@testable import Domain
@testable import EditorFeature

@MainActor
struct VolumeCurveEditorTests {
    private func model() -> (EditorModel, AudioClip.ID) {
        let recording = Recording(relativePath: "media/a.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 30))
        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 20)),
            status: .ready
        )
        let segment = Segment(role: .hook, script: "", takes: [take], selectedTakeID: take.id)
        var project = Project(title: "t", localeIdentifier: "en", segments: [segment], recordings: [recording])
        let song = AudioClip(
            name: "song",
            relativePath: "media/song.m4a",
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 20))
        )
        project.audio = [song]
        return (EditorModel(project: project), song.id)
    }

    @Test func theSliderDrawsAtThePlayheadAndEditsTheKeyThatIsThere() {
        let (editor, id) = model()
        editor.seek(to: 5)
        #expect(editor.volumeKeyAtPlayhead(id) == nil)

        editor.setVolumeKeyAtPlayhead(id, level: 0.4)
        editor.seek(to: 5.1)
        editor.setVolumeKeyAtPlayhead(id, level: 0.6)

        let keys = editor.project.audio[0].orderedVolumeKeys
        #expect(keys.count == 1)
        #expect(abs((keys.first?.time ?? 0) - 5) < 0.0001)
        #expect(abs(editor.automationAtPlayhead(id) - 0.6) < 0.0001)
    }

    @Test func splittingKeepsTheLevelAtTheCut() {
        let (editor, id) = model()
        editor.seek(to: 2)
        editor.setVolumeKeyAtPlayhead(id, level: 0.2)
        editor.seek(to: 12)
        editor.setVolumeKeyAtPlayhead(id, level: 1)

        editor.seek(to: 7)
        editor.splitAudioAtPlayhead(id)

        let left = editor.project.audio.first { $0.id == id }
        let right = editor.project.audio.first { $0.id != id }
        // Half way between 0.2 and 1 is 0.6, on both sides of the cut.
        #expect(abs((left?.automation(at: 7) ?? 0) - 0.6) < 0.0001)
        #expect(abs((right?.automation(at: 0) ?? 0) - 0.6) < 0.0001)
        // The right half's key that was at 12 on the song is now 5 seconds into its own clip.
        let rightTimes = right?.orderedVolumeKeys.map { $0.time } ?? []
        #expect(rightTimes.contains { abs($0 - 5) < 0.0001 })
    }

    @Test func trimmingTheFrontKeepsKeysOnTheirMusic() {
        let (editor, id) = model()
        editor.seek(to: 10)
        editor.setVolumeKeyAtPlayhead(id, level: 0.5)

        editor.setAudioStartEdge(id, to: 4)
        let clip = editor.project.audio[0]
        #expect(abs(clip.start.seconds - 4) < 0.0001)
        // Still at 10 on the timeline, so 6 seconds into the clip now.
        let times = clip.orderedVolumeKeys.map { $0.time }
        #expect(times.count == 1)
        #expect(abs((times.first ?? 0) - 6) < 0.0001)
    }
}
