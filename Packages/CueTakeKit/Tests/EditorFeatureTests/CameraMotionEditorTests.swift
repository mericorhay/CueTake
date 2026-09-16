import Foundation
import Testing
@testable import Domain
@testable import EditorFeature

@MainActor
struct CameraMotionEditorTests {
    private func model() -> EditorModel {
        let recording = Recording(
            relativePath: "media/a.mov",
            format: .vertical1080,
            camera: .front,
            duration: MediaTime(seconds: 20)
        )
        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(
                start: MediaTime(seconds: 3),
                duration: MediaTime(seconds: 10)
            ),
            status: .ready
        )
        let segment = Segment(
            role: .mainPoint,
            script: "",
            takes: [take],
            selectedTakeID: take.id
        )
        return EditorModel(
            project: Project(
                title: "t",
                localeIdentifier: "en",
                segments: [segment],
                recordings: [recording]
            )
        )
    }

    @Test func staticFramingCanBeEditedBeforeMediaPreparation() throws {
        let model = model()
        #expect(model.mediaDirectory == nil)

        model.seek(to: 2)
        model.setMainVideoZoom(1.2)

        let recording = try #require(model.project.recordings.first)
        let recipe = try #require(recording.cameraMotions?.first)
        #expect(recipe.kind == .hold)
        #expect(abs(recipe.amount - 0.2) < 0.001)
        #expect(abs(recipe.sourceRange.start.seconds - 3) < 0.001)
        #expect(abs(recipe.sourceRange.duration.seconds - 10) < 0.001)
        #expect(model.project.mainVideoPlacement.zoom == nil)
    }

    @Test func cameraRangeDragIsOneUndoableSourceTimeEdit() throws {
        let model = model()
        model.seek(to: 2)
        model.applyCameraMotion(.pushIn, amount: 0.15)
        let recording = try #require(model.project.recordings.first)
        let recipe = try #require(recording.cameraMotions?.first)
        model.past.removeAll()

        model.setCameraMotionRange(
            recordingID: recording.id,
            motionID: recipe.id,
            sourceStart: 5,
            sourceEnd: 15,
            coalescing: "move"
        )
        model.setCameraMotionRange(
            recordingID: recording.id,
            motionID: recipe.id,
            sourceStart: 6,
            sourceEnd: 16,
            coalescing: "move"
        )

        // A move keeps its length: two seconds from the playhead, at source second 5.
        let moved = try #require(model.project.recordings.first?.cameraMotions?.first)
        #expect(abs(moved.start - 6) < 0.001)
        #expect(abs(moved.end - 8) < 0.001)
        #expect(model.changes.count == 1)

        model.undo()
        let restored = try #require(model.project.recordings.first?.cameraMotions?.first)
        #expect(abs(restored.start - 5) < 0.001)
        #expect(abs(restored.end - 7) < 0.001)
    }

    @Test func aNewMoveStartsAtThePlayheadAndLeavesOthersAlone() throws {
        let model = model()
        model.seek(to: 1)
        model.applyCameraMotion(.pushIn, amount: 0.15)
        model.seek(to: 6)
        model.applyCameraMotion(.punch, amount: 0.2)
        model.seek(to: 4)
        model.setMainVideoZoom(1.1)

        let moves = try #require(model.project.recordings.first?.cameraMotions)
        #expect(moves.map(\.kind) == [.pushIn, .hold, .punch])
        #expect(abs(moves[0].start - 4) < 0.001 && abs(moves[0].end - 6) < 0.001)
        // The static zoom fills the free stretch between the two moves.
        #expect(abs(moves[1].start - 6) < 0.001 && abs(moves[1].end - 9) < 0.001)
        #expect(abs(moves[2].start - 9) < 0.001 && abs(moves[2].end - 10) < 0.001)

        model.select(cameraMotion: moves[2].id)
        model.removeCameraMotion(moves[2].id)
        #expect(model.project.recordings.first?.cameraMotions?.count == 2)
        #expect(model.selectedCameraMotionValue == nil)
    }

    @Test func aTrackIsABarThatCanBeShortenedAndRemoved() throws {
        let model = model()
        model.project.recordings[0].reframe = stride(from: 3.0, through: 13.0, by: 1).map {
            VideoFocusKeyframe(time: $0, x: 0.3, y: 0.5)
        }
        let span = try #require(model.subjectTrackSpans.first)
        #expect(abs(span.start - 0) < 0.001 && abs(span.end - 10) < 0.001)

        model.isAdjustingTimeline = true
        model.setSubjectTrackRange(forSegment: span.segmentID, start: 2.5, coalescing: "start")
        model.setSubjectTrackRange(forSegment: span.segmentID, start: 4, coalescing: "start")
        model.isAdjustingTimeline = false
        let shortened = try #require(model.subjectTrackSpans.first)
        #expect(abs(shortened.start - 4) < 0.001)
        #expect(abs(shortened.end - 10) < 0.001)
        #expect(model.changes.count == 1)

        model.removeSubjectTrack(forSegment: span.segmentID)
        #expect(model.subjectTrackSpans.isEmpty)
        #expect(model.project.recordings[0].reframe == nil)
    }

    @Test func changingSelectedMoveKeepsItsAuthoredRange() throws {
        let model = model()
        model.seek(to: 2)
        model.applyCameraMotion(.pushIn, amount: 0.15)
        let recording = try #require(model.project.recordings.first)
        let recipe = try #require(recording.cameraMotions?.first)
        model.setCameraMotionRange(
            recordingID: recording.id,
            motionID: recipe.id,
            sourceStart: 5,
            sourceEnd: 9
        )

        // Timeline second 3 points at source second 6 for this take.
        model.seek(to: 3)
        model.setCameraMotionFeel(.calm)
        model.applyCameraMotion(.punch, amount: 0.2)

        let changed = try #require(model.project.recordings.first?.cameraMotions?.first)
        #expect(changed.id == recipe.id)
        #expect(changed.kind == .punch)
        #expect(changed.feel == .calm)
        #expect(abs(changed.start - 5) < 0.001)
        #expect(abs(changed.end - 9) < 0.001)
    }

    @Test func changingMoveAmountDoesNotReplaceItWithAStaticZoom() throws {
        let model = model()
        model.seek(to: 2)
        model.applyCameraMotion(.pushIn, amount: 0.15)
        let original = try #require(model.project.recordings.first?.cameraMotions?.first)

        model.setCameraMotionAmount(0.32)

        let changed = try #require(model.project.recordings.first?.cameraMotions?.first)
        #expect(changed.id == original.id)
        #expect(changed.kind == .pushIn)
        #expect(changed.sourceRange == original.sourceRange)
        #expect(abs(changed.amount - 0.32) < 0.001)
    }

    @Test func cameraRangeCannotOverlapANeighbour() throws {
        let model = model()
        let recording = try #require(model.project.recordings.first)
        let first = CameraMotionRecipe(
            sourceRange: MediaTimeRange(start: MediaTime(seconds: 3), duration: MediaTime(seconds: 3)),
            kind: .pushIn
        )
        let second = CameraMotionRecipe(
            sourceRange: MediaTimeRange(start: MediaTime(seconds: 8), duration: MediaTime(seconds: 3)),
            kind: .pullOut
        )
        model.project.recordings[0].cameraMotions = [first, second]

        model.setCameraMotionRange(
            recordingID: recording.id,
            motionID: first.id,
            sourceStart: 7,
            sourceEnd: 10,
            coalescing: "move"
        )

        let moved = try #require(model.project.recordings.first?.cameraMotions?.first(where: { $0.id == first.id }))
        #expect(abs(moved.start - 5) < 0.001)
        #expect(abs(moved.end - 8) < 0.001)
        #expect(moved.end <= second.start)
    }
}
