import Foundation
import Testing
@testable import Domain
@testable import EditorFeature

/// Editing by text. The failure this guards against is the quiet one: the cut lands, the timeline
/// looks right, and the footage removed is a word away from the word the user deleted.
@MainActor
struct TranscriptEditingTests {
    private func word(_ text: String, _ start: Double, _ duration: Double = 0.4) -> TimedWord {
        TimedWord(text: text, range: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: duration)))
    }

    /// One ten second take starting three seconds into its recording.
    private func model() -> EditorModel {
        let recording = Recording(
            relativePath: "media/a.mov",
            format: .vertical1080,
            camera: .front,
            duration: MediaTime(seconds: 20)
        )
        let transcript = Transcript(localeIdentifier: "en", words: [
            word("so", 0.2),
            word("um", 1.0),
            word("this", 1.6),
            word("is", 2.1),
            // A long pause here.
            word("the", 5.0),
            word("point", 5.5),
        ])
        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: MediaTime(seconds: 3), duration: MediaTime(seconds: 10)),
            status: .ready,
            transcript: transcript
        )
        let segment = Segment(role: .mainPoint, script: "so um this is the point", takes: [take], selectedTakeID: take.id)
        return EditorModel(project: Project(title: "t", localeIdentifier: "en", segments: [segment], recordings: [recording]))
    }

    @Test func removingAWordSplitsAroundItInSourceTime() {
        let model = model()
        model.removeSpoken(at: 0, from: 1.0, to: 1.4)

        let segments = model.project.segments
        #expect(segments.count == 2)
        // Left keeps the start of the take; right resumes exactly where "um" ended.
        #expect(abs(segments[0].selectedTake!.sourceRange.start.seconds - 3.0) < 0.001)
        #expect(abs(segments[0].selectedTake!.sourceRange.duration.seconds - 1.0) < 0.001)
        #expect(abs(segments[1].selectedTake!.sourceRange.start.seconds - 4.4) < 0.001)
        // Words follow their footage and are rebased onto their new take.
        #expect(segments[1].selectedTake!.transcript!.words.map(\.text) == ["this", "is", "the", "point"])
        #expect(abs(segments[1].selectedTake!.transcript!.words[0].range.start.seconds - 0.2) < 0.001)
        #expect(segments[1].script == "this is the point")
    }

    @Test func tighteningCutsOnlyTheLongPause() {
        let model = model()
        #expect(model.silenceGaps(at: 0).count == 1)

        model.tightenSilences(at: 0, threshold: 0.6, pad: 0.1)

        let segments = model.project.segments
        #expect(segments.count == 2)
        #expect(segments[0].selectedTake!.transcript!.words.map(\.text) == ["so", "um", "this", "is"])
        #expect(segments[1].selectedTake!.transcript!.words.map(\.text) == ["the", "point"])
        // The kept parts sum to less than the original ten seconds.
        let kept = segments.reduce(0) { $0 + $1.selectedTake!.sourceRange.duration.seconds }
        #expect(kept < 10)
    }

    @Test func everyTextEditIsUndoable() {
        let model = model()
        model.removeSpoken(at: 0, from: 1.0, to: 1.4)
        #expect(model.canUndo)
        model.undo()
        #expect(model.project.segments.count == 1)
        #expect(abs(model.project.segments[0].selectedTake!.sourceRange.duration.seconds - 10) < 0.001)
    }
}
