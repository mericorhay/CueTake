import Foundation
import Testing
@testable import Domain
@testable import EditorFeature

/// The AI running the studio: that a plan can reach every part of it, that pieces of one plan find
/// each other after a split, and that each change it made can be taken back on its own.
@MainActor
struct AIDirectorTests {
    private func word(_ text: String, _ start: Double, _ duration: Double = 0.4) -> TimedWord {
        TimedWord(text: text, range: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: duration)))
    }

    /// One ten second take with words at known times.
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

    private func isOverlay(_ target: AITarget) -> Bool {
        if case .overlay = target { return true }
        return false
    }

    @Test func aPlanReachesTheWholeStudioAndEachChangeReverts() throws {
        let model = model()
        let clip = model.project.segments[0].id.uuidString
        let plan = EditPlan(summary: "s", operations: [
            .addText(EditPlan.OverlayPatch(text: "Title", start: 0.5, duration: 2, y: 0.2)),
            .captionLook(EditPlan.CaptionLook(size: 0.06, textColor: "#FFD60A")),
            .setSpeed(clip: clip, speed: 2),
            .setTitle("New title"),
        ])
        let outcome = model.apply(plan)
        #expect(outcome.applied == 4)
        #expect(outcome.skipped.isEmpty)
        #expect(model.project.overlays.count == 1)
        #expect(abs(model.project.captionStyle.relativeFontSize - 0.06) < 0.0001)
        #expect(model.project.captionStyle.textColor.hex == "#FFD60A")
        #expect(model.project.segments[0].playback.speed == 2)
        #expect(model.project.title == "New title")
        #expect(model.aiChanges.count == 1)

        // Only the text goes; the rest of the plan stays.
        let set = model.aiChanges[0]
        let text = try #require(set.items.first { $0.targets.contains(where: isOverlay) })
        model.revertAIChange(text.id, in: set.id)
        #expect(model.project.overlays.isEmpty)
        #expect(model.project.title == "New title")
        #expect(model.project.segments[0].playback.speed == 2)
        #expect(model.aiChanges[0].items.first { $0.id == text.id }?.reverted == true)
        #expect(!model.isAITouched(.overlay(model.aiChanges[0].after.overlays[0].id)))

        model.reapplyAIChange(text.id, in: set.id)
        #expect(model.project.overlays.count == 1)

        model.revertAIChangeSet(set.id)
        #expect(model.project.title == "t")
        #expect(model.project.segments[0].playback.speed == 1)
        #expect(model.project.overlays.isEmpty)
        #expect(model.aiChanges[0].isFullyReverted)

        // Taking changes back is itself an edit, and undo brings them back.
        model.undo()
        #expect(model.project.title == "New title")
    }

    @Test func aCutAfterASplitLandsOnTheRightPiece() {
        let model = model()
        let clip = model.project.segments[0].id.uuidString
        // Split at 4 s of footage, then remove "the" (5.0–5.4 s), which is now in the second piece.
        let plan = EditPlan(summary: "", operations: [
            .cut(clip: clip, from: 5.0, to: 5.4),
            .splitClip(clip: clip, at: 4),
        ])
        let outcome = model.apply(plan)
        #expect(outcome.applied == 2)
        #expect(model.project.segments.count >= 2)
        let words = model.project.segments.flatMap { $0.selectedTake?.transcript?.words.map(\.text) ?? [] }
        #expect(!words.contains("the"))
        #expect(words.contains("point"))
        #expect(words.contains("um"))
    }

    @Test func takingBackACutAfterASplitKeepsBothHalves() throws {
        let model = model()
        let clip = model.project.segments[0].id.uuidString
        model.apply(EditPlan(summary: "", operations: [
            .splitClip(clip: clip, at: 4),
            .cut(clip: clip, from: 5.0, to: 5.4),
        ]))
        let set = try #require(model.aiChanges.first)
        let cut = try #require(set.items.last)
        model.revertAIChange(cut.id, in: set.id)

        #expect(model.project.segments.count == 2)
        let words = model.project.segments.flatMap { $0.selectedTake?.transcript?.words.map(\.text) ?? [] }
        #expect(words == ["so", "um", "this", "is", "the", "point"])

        // Undo the take-back: the list follows the project.
        model.undo()
        #expect(model.aiChanges[0].items.last?.reverted == false)
        model.undo()
        #expect(model.aiChanges[0].isFullyReverted)
    }

    @Test func captionsAndTheirWindowAreReachable() throws {
        let model = model()
        model.project.segments[0].refreshCaptions(maxWordsPerCue: 3)
        let cue = try #require(model.project.segments[0].captions.first)
        let plan = EditPlan(summary: "", operations: [
            .setCaptionText(caption: cue.id.uuidString, text: "So, um"),
            .captionWindow(from: 1, to: 6),
            .captionStyle(preset: "boxed", position: 0.2),
        ])
        let outcome = model.apply(plan)
        #expect(outcome.applied == 3)
        #expect(model.project.segments[0].captions.contains { $0.text == "So, um" })
        #expect(model.project.captionWindow?.start.seconds == 1)
        #expect(model.project.captionStyle.presetID == "boxed")
        #expect(abs(model.project.captionStyle.position.y - 0.2) < 0.0001)
    }

    @Test func toolsOnlyTheAIHas() throws {
        let model = model()
        model.project.segments[0].refreshCaptions(maxWordsPerCue: 2)
        let before = model.project.segments[0].captions.map(\.range.start.seconds)
        model.addTextOverlay("Hi")
        let plan = EditPlan(summary: "", operations: [
            .renameClip(clip: "c1", title: "Opening"),
            .setScript(clip: "c1", text: "New words"),
            .shiftCaptions(clip: nil, by: 0.3),
            .duplicateOverlay(overlay: "o1", start: 5),
        ])
        let outcome = model.apply(plan)
        #expect(outcome.applied == 4)
        #expect(model.project.segments[0].title == "Opening")
        #expect(model.project.segments[0].script == "New words")
        let after = model.project.segments[0].captions.map(\.range.start.seconds)
        #expect(zip(before, after).allSatisfy { abs(($1 - $0) - 0.3) < 0.001 })
        #expect(model.project.overlays.count == 2)
        #expect(model.project.overlays[1].start.seconds == 5)
    }

    @Test func aPlanThatChangesNothingIsNamedForTheRetry() {
        let model = model()
        #expect(model.problem(with: EditPlan(summary: "Video is ready", operations: [])) != nil)
        #expect(model.problem(with: EditPlan(summary: "", operations: [.deleteClip(clip: "c7")])) != nil)
        #expect(model.problem(with: EditPlan(summary: "", operations: [.setTitle("x")])) == nil)
    }

    @Test func theAINeverRemovesAClip() {
        let model = model()
        let clip = model.project.segments[0].id.uuidString
        model.duplicateSegment(at: 0)
        let outcome = model.apply(EditPlan(summary: "", operations: [
            .deleteClip(clip: clip),
            .cut(clip: clip, from: 0, to: 10),
            .setBackground(clip: "c2", style: "blur"),
        ]))
        #expect(model.project.segments.count == 2)
        #expect(model.project.segments[0].selectedTake?.sourceRange.duration.seconds == 10)
        #expect(model.project.segments[1].background == .blur)
        #expect(outcome.skipped.contains("deleteClip"))
    }

    @Test func missingThingsAreSkippedNotGuessed() {
        let model = model()
        let plan = EditPlan(summary: "", operations: [
            .deleteClip(clip: "nope"),
            .removeOverlay(overlay: UUID().uuidString),
            .setMusicLevel(audio: UUID().uuidString, gainDb: -10),
        ])
        let outcome = model.apply(plan)
        #expect(outcome.applied == 0)
        #expect(outcome.skipped.count == 3)
        #expect(model.aiChanges.isEmpty)
    }
}
