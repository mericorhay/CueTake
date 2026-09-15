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

        let moved = try #require(model.project.recordings.first?.cameraMotions?.first)
        #expect(abs(moved.start - 6) < 0.001)
        #expect(abs(moved.end - 16) < 0.001)
        #expect(model.changes.count == 1)

        model.undo()
        let restored = try #require(model.project.recordings.first?.cameraMotions?.first)
        #expect(abs(restored.start - 3) < 0.001)
        #expect(abs(restored.end - 13) < 0.001)
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
