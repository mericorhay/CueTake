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

    @Test func splitAvailabilityTracksBoundariesPlaybackAndUndo() {
        let model = model()
        model.seek(to: 0.1)
        #expect(!model.canSplitAtPlayhead)
        model.splitAtPlayhead()
        #expect(model.project.segments.count == 1)

        model.seek(to: 5)
        #expect(model.canSplitAtPlayhead)
        model.splitAtPlayhead()
        #expect(model.project.segments.count == 2)
        model.undo()
        #expect(model.project.segments.count == 1)

        model.project.segments[0].playback.isReversed = true
        model.seek(to: 5)
        #expect(!model.canSplitAtPlayhead)
        model.splitAtPlayhead()
        #expect(model.project.segments.count == 1)

        model.project.segments[0].playback.isReversed = false
        model.project.segments[0].playback.freeze = MediaTime(seconds: 2)
        model.seek(to: 1)
        #expect(!model.canSplitAtPlayhead)
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

    // MARK: - Captions survive cuts

    @Test func trimmingPausesKeepsCaptionsOnEveryPiece() {
        let model = model()
        model.tightenSilences(at: 0, threshold: 0.6, pad: 0.1)
        for segment in model.project.segments {
            #expect(!segment.captions.isEmpty, "a cut must not delete a clip's captions")
            // Every cue starts inside its own piece of footage.
            #expect(segment.captions.allSatisfy { $0.range.start.seconds < segment.sourceSeconds })
        }
    }

    @Test func splittingGivesEachHalfItsOwnWordsAndCaptions() {
        let model = model()
        model.seek(to: 3.5)
        model.splitAtPlayhead()

        let segments = model.project.segments
        #expect(segments.count == 2)
        #expect(segments[0].selectedTake?.transcript?.words.map(\.text) == ["so", "um", "this", "is"])
        #expect(segments[1].selectedTake?.transcript?.words.map(\.text) == ["the", "point"])
        #expect(!segments[0].captions.isEmpty)
        #expect(segments[1].captions.first?.text.hasPrefix("the") == true)
        // Rebased: "the" was said at 5.0s, 1.5s after the cut.
        #expect(abs(segments[1].captions[0].range.start.seconds - 1.5) < 0.01)
    }

    @Test func handTypedCaptionsMoveWithTheirHalf() {
        let model = model()
        model.project.segments[0].refreshCaptions(maxWordsPerCue: 3)
        let last = model.project.segments[0].captions.last!
        model.updateCaption(last.id, at: 0) { $0.text = "THE POINT" }

        model.seek(to: 3.5)
        model.splitAtPlayhead()
        #expect(model.project.segments[1].captions.contains { $0.text == "THE POINT" && $0.isUserEdited })
        #expect(!model.project.segments[0].captions.contains { $0.text == "THE POINT" })
    }

    @Test func mergingPutsTheCaptionsBackTogether() {
        let model = model()
        model.seek(to: 3.5)
        model.splitAtPlayhead()
        #expect(model.canMerge(at: 0))
        model.mergeWithNext(at: 0)

        let merged = model.project.segments[0]
        #expect(merged.selectedTake?.transcript?.words.count == 6)
        #expect(abs((merged.selectedTake?.transcript?.words.last?.range.start.seconds ?? 0) - 5.5) < 0.01)
        #expect(merged.captions.last?.text.hasSuffix("point") == true)
    }
}

/// AI edit plans: the document the model reads, and the plan it sends back applied as one step.
@MainActor
struct EditPlanTests {
    private func model() -> EditorModel {
        let recording = Recording(relativePath: "media/a.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 20))
        func word(_ text: String, _ start: Double) -> TimedWord {
            TimedWord(text: text, range: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: 0.4)))
        }
        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 6)),
            status: .ready,
            transcript: Transcript(localeIdentifier: "en", words: [word("so", 0.2), word("um", 1.0), word("this", 1.6), word("works", 4.0)])
        )
        var segment = Segment(role: .hook, script: "so um this works", takes: [take], selectedTakeID: take.id)
        segment.refreshCaptions(maxWordsPerCue: 3)
        return EditorModel(project: Project(title: "t", localeIdentifier: "en", segments: [segment], recordings: [recording]))
    }

    @Test func documentCarriesWordsAndOptionalBeats() throws {
        let model = model()
        let small = model.document()
        #expect(small.clips.count == 1)
        #expect(small.clips[0].id == "c1")
        #expect(small.clips[0].words.map(\.text) == ["so", "um", "this", "works"])
        #expect(small.clips[0].captions.first?.id == "k1")
        #expect(small.beats == nil)

        let detailed = model.document(beatStep: 0.5)
        #expect(detailed.beats?.count == 12)
        #expect(detailed.beats?.first { $0.t == 1.0 }?.word == "um")
        #expect(try detailed.jsonData().count > small.jsonData().count)
    }

    @Test func messyModelOutputDecodes() throws {
        let text = """
        Here is the plan:
        {"summary":"Cut the filler.","operations":[
          {"op":"removeWords","clip":"X","words":[1]},
          {"op":"setSpeed","clip":"X","speed":"1.2"},
          {"op":"teleport","clip":"X"}
        ]}
        """
        let plan = try EditPlan.decode(from: text)
        #expect(plan.summary == "Cut the filler.")
        #expect(plan.operations.count == 3)
        #expect(plan.operations[1] == .setSpeed(clip: "X", speed: 1.2))
        #expect(plan.operations[2] == .unknown(type: "teleport"))
    }

    @Test func applyingAPlanIsOneUndo() {
        let model = model()
        let id = model.project.segments[0].id.uuidString
        let plan = EditPlan(summary: "", operations: [
            .removeWords(clip: id, words: [1]),
            .setSpeed(clip: id, speed: 1.5),
            .captionStyle(preset: "bold", position: nil),
            .unknown(type: "teleport"),
        ])
        let outcome = model.apply(plan)
        #expect(outcome.applied == 3)
        #expect(outcome.skipped == ["teleport"])
        #expect(model.project.segments.count == 2)
        #expect(model.project.segments.allSatisfy { !($0.selectedTake?.transcript?.words.contains { $0.text == "um" } ?? false) })
        #expect(model.project.captionStyle.presetID == "bold")

        model.undo()
        #expect(model.project.segments.count == 1)
        #expect(model.project.captionStyle.presetID != "bold")
        #expect(!model.canUndo)
    }
}

@MainActor
struct OverlayEditingTests {
    private func model() -> EditorModel {
        let segment = Segment(role: .hook, script: "hello", estimatedDuration: MediaTime(seconds: 60))
        return EditorModel(project: Project(title: "t", localeIdentifier: "en", segments: [segment]))
    }

    @Test func textOverlayStartsAtThePlayheadAndIsSelected() {
        let model = model()
        model.seek(to: 29)
        model.addTextOverlay("Title")
        let overlay = model.project.overlays.first
        #expect(overlay != nil)
        #expect(abs((overlay?.start.seconds ?? 0) - 29) < 0.001)
        #expect(model.selectedOverlay == overlay?.id)
        #expect(model.overlaysVisible(at: 30).count == 1)
        #expect(model.overlaysVisible(at: 40).isEmpty)
    }

    @Test func endAtPlayheadAndLimits() {
        let model = model()
        model.seek(to: 10)
        model.addTextOverlay("T")
        let id = model.project.overlays[0].id
        model.seek(to: 30)
        model.endOverlayAtPlayhead(id)
        #expect(abs(model.project.overlays[0].duration.seconds - 20) < 0.001)

        model.updateOverlay(id) {
            $0.transform.scale = 100
            $0.transform.opacity = 0
            $0.duration = MediaTime(seconds: 0)
        }
        #expect(model.project.overlays[0].transform.scale == OverlayTransform.scaleRange.upperBound)
        #expect(model.project.overlays[0].transform.opacity > 0)
        #expect(model.project.overlays[0].duration.seconds >= Overlay.shortest)
    }

    @Test func removingIsUndoable() {
        let model = model()
        model.addTextOverlay("T")
        let id = model.project.overlays[0].id
        model.removeOverlay(id)
        #expect(model.project.overlays.isEmpty)
        model.undo()
        #expect(model.project.overlays.count == 1)
    }
}
