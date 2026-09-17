import Foundation
import Testing
@testable import Domain
@testable import EditorFeature

/// Cleaning a take against its script, and opening the cut again.
@MainActor
struct CleanupEditingTests {
    private func word(_ text: String, _ start: Double, _ duration: Double = 0.4) -> TimedWord {
        TimedWord(text: text, range: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: duration)))
    }

    /// A ten second take, three seconds into its recording, that opens with "so um" and pauses
    /// twice; then a clip with no words.
    private func model() -> EditorModel {
        let recording = Recording(
            relativePath: "media/a.mov",
            format: .vertical1080,
            camera: .front,
            duration: MediaTime(seconds: 30)
        )
        let transcript = Transcript(localeIdentifier: "en", words: [
            word("so", 0.2),
            word("um", 1.0),
            word("this", 1.6),
            word("is", 2.1),
            word("the", 5.0),
            word("point", 5.5),
        ])
        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: MediaTime(seconds: 3), duration: MediaTime(seconds: 10)),
            status: .ready,
            transcript: transcript
        )
        let first = Segment(role: .mainPoint, script: "This is the point.", takes: [take], selectedTakeID: take.id)
        let silent = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: MediaTime(seconds: 20), duration: MediaTime(seconds: 5)),
            status: .ready
        )
        let second = Segment(role: .callToAction, script: "", takes: [silent], selectedTakeID: silent.id)
        return EditorModel(project: Project(title: "t", localeIdentifier: "en", segments: [first, second], recordings: [recording]))
    }

    @Test func cleaningCutsTheTakeAndCanBeOpenedAgain() throws {
        let model = model()
        let originalID = model.project.segments[0].id
        let secondID = model.project.segments[1].id
        model.project.setTransition(after: originalID, kind: .crossfade)

        let plan = try #require(model.cleanupPlan(at: 0))
        #expect(plan.alignment != nil)
        #expect(model.cleanupPlan(at: 1) == nil)
        let saved = model.applyCleanup(plan, chosen: plan.defaultSelection)
        #expect(abs(saved - 7.74) < 0.01)

        let segments = model.project.segments
        #expect(segments.count == 3)
        #expect(segments[0].id == originalID)
        #expect(segments[2].id == secondID)
        // "so um" and the silence around it are gone; the clip starts just before "this".
        #expect(abs((segments[0].selectedTake?.sourceRange.start.seconds ?? 0) - 4.5) < 0.001)
        #expect(segments[0].selectedTake?.transcript?.words.map(\.text) == ["this", "is"])
        #expect(segments[1].selectedTake?.transcript?.words.map(\.text) == ["the", "point"])
        // Each piece keeps its part of the script, not the words it happened to keep.
        #expect(segments[0].script == "This is")
        #expect(segments[1].script == "the point.")
        // One cleanup; only the first piece carries the clip as shot.
        #expect(segments[0].cleanup?.group == segments[1].cleanup?.group)
        #expect(segments[0].cleanup?.takes?.count == 1)
        #expect(segments[1].cleanup?.takes == nil)
        #expect(segments[0].cleanup?.script == "This is the point.")
        // The transition still plays after the whole clip, not between its pieces.
        #expect(model.project.transitions.map(\.after) == [segments[1].id])

        let group = try #require(model.cleanupGroup(at: 1))
        #expect(group.range == 0...1)
        #expect(abs(group.removed - 7.74) < 0.01)
        #expect(model.cleanupGroup(at: 2) == nil)

        // A second pass has nothing left to take.
        let again = try #require(model.cleanupPlan(at: 0))
        #expect(again.saved(again.defaultSelection) < 0.05)

        model.restoreCleanup(at: 1)
        #expect(model.project.segments.count == 2)
        let restored = model.project.segments[0]
        #expect(restored.id == originalID)
        #expect(restored.cleanup == nil)
        #expect(abs((restored.selectedTake?.sourceRange.duration.seconds ?? 0) - 10) < 0.001)
        #expect(restored.selectedTake?.transcript?.words.count == 6)
        #expect(restored.script == "This is the point.")
        #expect(model.project.transitions.map(\.after) == [originalID])
        #expect(model.project.segments[1].id == secondID)
    }

    @Test func cleaningEveryClipIsOneUndo() {
        let model = model()
        let result = model.cleanUpAllClips(kinds: Set(CleanupItem.Kind.allCases))
        #expect(result.clips == 1)
        #expect(result.seconds > 7)
        #expect(model.project.segments.count == 3)
        model.undo()
        #expect(model.project.segments.count == 2)
        #expect(model.project.segments[0].cleanup == nil)
    }

    @Test func onlyTheChosenKindsAreCut() {
        let model = model()
        let result = model.cleanUpAllClips(kinds: [.filler])
        #expect(result.clips == 1)
        // The pauses stay: one clip, starting just before "this".
        #expect(model.project.segments.count == 2)
        #expect(model.project.segments[0].selectedTake?.transcript?.words.first?.text == "this")
    }
}

/// Shooting one sentence again.
@MainActor
struct SentenceRetakeTests {
    private func word(_ text: String, _ start: Double) -> TimedWord {
        TimedWord(text: text, range: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: 0.4)))
    }

    private func model() -> EditorModel {
        let recording = Recording(relativePath: "media/a.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 20))
        let transcript = Transcript(localeIdentifier: "en", words: [
            word("Hello", 0.2),
            word("there.", 0.7),
            word("This", 1.6),
            word("is", 2.1),
            word("wrong.", 2.6),
            word("Bye", 3.6),
        ])
        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 5)),
            status: .ready,
            transcript: transcript
        )
        let segment = Segment(role: .hook, script: "Hello there. This is right. Bye", takes: [take], selectedTakeID: take.id)
        return EditorModel(project: Project(title: "t", localeIdentifier: "en", segments: [segment], recordings: [recording]))
    }

    @Test func aSentenceBecomesItsOwnClipWithTheScriptsWords() throws {
        let model = model()
        let id = try #require(model.isolateForRetake(at: 0, words: 2...4))
        let segments = model.project.segments
        #expect(segments.count == 3)
        #expect(segments[1].id == id)
        // Cut in the silences: between "there." (ends 1.1) and "This" (1.6), and after "wrong.".
        #expect(abs((segments[1].selectedTake?.sourceRange.start.seconds ?? 0) - 1.35) < 0.001)
        #expect(abs((segments[1].selectedTake?.sourceRange.duration.seconds ?? 0) - 1.95) < 0.001)
        // The prompter will show what the script says, not the misreading.
        #expect(segments[1].script == "This is right.")
        #expect(segments[0].script == "Hello there.")

        // A selection that is the whole clip is the clip.
        let whole = model.project.segments[0].id
        #expect(model.isolateForRetake(at: 0, words: 0...1) == whole)
    }
}
