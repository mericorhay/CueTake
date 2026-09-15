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
}
