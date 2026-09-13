import Foundation
import Testing
@testable import Domain

/// The arithmetic the editor, the preview and the exporter all share. If these numbers drift,
/// a caption lands a beat late or a cut lands a frame wrong, and nobody can see why.
struct ClipPlaybackTests {
    @Test func speedDividesTheTimeline() {
        let playback = ClipPlayback(speed: 2)
        #expect(playback.timelineSeconds(forSource: 10) == 5)
        #expect(playback.sourceSeconds(forTimeline: 5) == 10)
    }

    @Test func freezeIgnoresTheSource() {
        let playback = ClipPlayback(speed: 4, freeze: MediaTime(seconds: 2))
        #expect(playback.timelineSeconds(forSource: 30) == 2)
        #expect(playback.badge == "FREEZE")
    }

    @Test func oldDocumentsDecodeWithNormalPlayback() throws {
        let segment = Segment(role: .hook, script: "Hi")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(segment)) as! [String: Any]
        json.removeValue(forKey: "playback")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(Segment.self, from: data)
        #expect(decoded.playback == .normal)
    }
}

struct CaptionPlacementTests {
    private func project(speed: Double) -> Project {
        let recording = Recording(
            relativePath: "media/a.mov",
            format: .vertical1080,
            camera: .front,
            duration: MediaTime(seconds: 10)
        )
        let transcript = Transcript(localeIdentifier: "en", words: [
            TimedWord(text: "one", range: MediaTimeRange(start: MediaTime(seconds: 1), duration: MediaTime(seconds: 0.5))),
            TimedWord(text: "two", range: MediaTimeRange(start: MediaTime(seconds: 2), duration: MediaTime(seconds: 0.5))),
        ])
        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 10)),
            status: .ready,
            transcript: transcript
        )
        var segment = Segment(role: .hook, script: "one two", takes: [take], selectedTakeID: take.id)
        segment.captions = CaptionBuilder.cues(from: transcript, maxWordsPerCue: 4)
        segment.playback = ClipPlayback(speed: speed)

        var intro = Segment(role: .intro, script: "", estimatedDuration: MediaTime(seconds: 4))
        intro.captions = []
        return Project(title: "t", localeIdentifier: "en", segments: [intro, segment], recordings: [recording])
    }

    @Test func cuesAreOffsetByTheClipsBeforeThem() {
        let cues = project(speed: 1).captionCues
        #expect(cues.count == 1)
        #expect(abs(cues[0].range.start.seconds - 5) < 0.01)
        #expect(cues[0].words.map(\.text) == ["one", "two"])
        #expect(abs(cues[0].words[1].range.start.seconds - 6) < 0.01)
    }

    @Test func cuesStretchWithSlowMotion() {
        let cues = project(speed: 0.5).captionCues
        // Word two is two seconds into the clip; at half speed that is four, after a four second intro.
        #expect(abs(cues[0].words[1].range.start.seconds - 8) < 0.01)
    }

    @Test func wordIndexTracksThePlayhead() {
        let cue = project(speed: 1).captionCues[0]
        #expect(cue.wordIndex(at: 4.9) == nil)
        #expect(cue.wordIndex(at: 5.2) == 0)
        #expect(cue.wordIndex(at: 6.1) == 1)
    }

    @Test func presetsAreWholeStyles() {
        #expect(CaptionStyle.preset("karaoke").highlightsWords)
        #expect(!CaptionStyle.preset("pop").highlightsWords)
        #expect(CaptionStyle.preset("clean").backgroundColor != nil)
        #expect(CaptionStyle.preset("clean").maxWordsPerCue > CaptionStyle.preset("pop").maxWordsPerCue)
    }
}

struct WorkflowDocumentTests {
    /// What a model actually writes: no ids, no dates, missing parameters, a wrapper sentence.
    @Test func aiWrittenJSONDecodes() throws {
        let text = """
        Here is your workflow:
        ```json
        {"name": "Quick reel",
         "sections": [{"role": "hook", "seconds": 3, "clip": 1}, {"role": "cta"}],
         "style": {"captionPreset": "karaoke", "aspect": "vertical"},
         "steps": [{"kind": {"type": "trimSilences"}},
                   {"kind": {"type": "setSpeed", "parameters": {"target": "hook", "speed": 1.2}}},
                   {"kind": {"type": "teleport"}}]}
        ```
        """
        let workflow = try WorkflowDefinition.decode(json: text)

        #expect(workflow.name == "Quick reel")
        #expect(workflow.sections.count == 2)
        #expect(workflow.sections[1].seconds == 5)
        #expect(workflow.style.captionPreset == "karaoke")
        #expect(workflow.style.aspect == .portrait9x16)
        #expect(workflow.steps[0].kind == .trimSilences(TrimSilencesOptions()))
        #expect(workflow.steps[1].kind == .setSpeed(SpeedOptions(target: "hook", speed: 1.2)))
        #expect(workflow.steps[2].kind == .unsupported(type: "teleport"))
    }

    @Test func documentsRoundTripThroughTheirOwnJSON() throws {
        let original = WorkflowDefinition.builtIns[1]
        let decoded = try WorkflowDefinition.decode(json: original.jsonString())
        #expect(decoded.steps == original.steps)
        #expect(decoded.sections == original.sections)
        #expect(decoded.style == original.style)
    }
}

struct AssistantSessionTests {
    @Test func titleIsTheFirstWords() {
        #expect(AssistantSession.title(from: "How do I cut the pauses out of my video please") == "How do I cut the pauses…")
        #expect(AssistantSession.title(from: "Short one") == "Short one")
    }
}
