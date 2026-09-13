import Foundation
import Testing
@testable import Domain

/// Hand edits to captions. What these guard is readability: a cue that flashes for a frame, runs
/// past its clip or sits on top of its neighbour is a caption edit that made the video worse.
struct CaptionEditingTests {
    private func range(_ start: Double, _ duration: Double) -> MediaTimeRange {
        MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: duration))
    }

    private func word(_ text: String, _ start: Double) -> TimedWord {
        TimedWord(text: text, range: range(start, 0.3))
    }

    /// A four second clip: "one two three four" at 0, 0.5, 1, 1.5 and a second cue later.
    private func segment() -> Segment {
        let recording = UUID()
        let take = Take(
            recordingID: recording,
            sourceRange: range(0, 4),
            status: .ready,
            transcript: Transcript(localeIdentifier: "en", words: [
                word("one", 0), word("two", 0.5), word("three", 1), word("four", 1.5), word("later", 3),
            ])
        )
        return Segment(
            role: .mainPoint,
            script: "",
            takes: [take],
            selectedTakeID: take.id,
            captions: [
                CaptionCue(text: "one two three four", range: range(0, 1.8)),
                CaptionCue(text: "later", range: range(3, 0.3)),
            ]
        )
    }

    @Test func nudgingNeverOverlapsTheNextCue() {
        var segment = segment()
        let id = segment.captions[0].id
        segment.nudgeCaption(id, end: 5)
        #expect(segment.captions[0].range.end.seconds <= segment.captions[1].range.start.seconds + 0.0001)
        #expect(segment.captions[0].isUserEdited)
    }

    @Test func nudgingKeepsACueReadable() {
        var segment = segment()
        let id = segment.captions[1].id
        segment.nudgeCaption(id, start: 10)
        #expect(segment.captions[1].range.duration.seconds >= Segment.shortestCaption - 0.001)
        #expect(segment.captions[1].range.end.seconds <= 4.0001)
    }

    @Test func splittingUsesWhenTheMiddleWordWasSaid() {
        var segment = segment()
        segment.splitCaption(segment.captions[0].id)
        #expect(segment.captions.count == 3)
        #expect(segment.captions[0].text == "one two")
        #expect(segment.captions[1].text == "three four")
        // "three" was said at one second.
        #expect(abs(segment.captions[1].range.start.seconds - 1) < 0.001)
    }

    @Test func mergingJoinsTextAndTime() {
        var segment = segment()
        segment.mergeCaptionWithNext(segment.captions[0].id)
        #expect(segment.captions.count == 1)
        #expect(segment.captions[0].text == "one two three four later")
        #expect(abs(segment.captions[0].range.end.seconds - 3.3) < 0.001)
    }

    @Test func slicingATranscriptGivesAWordToOneSideOnly() {
        let transcript = segment().selectedTake!.transcript!
        let left = transcript.slice(from: 0, to: 1.2)
        let right = transcript.slice(from: 1.2, to: 4)
        #expect(left?.words.map(\.text) == ["one", "two", "three"])
        #expect(right?.words.map(\.text) == ["four", "later"])
        #expect(abs((right?.words.first?.range.start.seconds ?? -1) - 0.3) < 0.001)
    }
}

/// What a model actually writes for a workflow: flat steps, strings for numbers, one bad entry.
struct WorkflowLenientDecodingTests {
    @Test func oneBadStepDoesNotLoseTheWorkflow() throws {
        let json = """
        {"name":"Temiz","sections":[{"role":"hook","seconds":"3"},{"role":42}],
         "steps":[{"type":"analyzeSpeech"},{"kind":{"type":"trimSilences","parameters":{"minPause":0.5}}},{"oops":true},{"type":"generateCaptions"}]}
        """
        let workflow = try WorkflowDefinition.decode(json: json)
        #expect(workflow.name == "Temiz")
        #expect(workflow.sections.first?.seconds == 3)
        #expect(workflow.steps.count >= 3)
        #expect(workflow.steps.first?.kind.typeName == "analyzeSpeech")
    }
}
