import Foundation
import Testing
@testable import Domain
@testable import EditorFeature

@MainActor
struct StageTests {
    private func model() -> EditorModel {
        let recording = Recording(relativePath: "media/a.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 20))
        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 10)),
            status: .ready
        )
        let segment = Segment(role: .hook, script: "", takes: [take], selectedTakeID: take.id)
        let added = Recording(relativePath: "media/b.mov", format: .vertical1080, camera: .back, duration: MediaTime(seconds: 12))
        let model = EditorModel(project: Project(title: "t", localeIdentifier: "en", segments: [segment], recordings: [recording, added]))
        model.project.videoLayers = [
            VideoLayer(
                recordingID: added.id,
                title: "B roll",
                sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 4))
            ),
        ]
        return model
    }

    @Test func halfTheFrameCropsRatherThanLetterboxes() {
        let editor = model()
        #expect(editor.isMainVideoWholeFrame)
        editor.setMainVideoPlacement(VideoPlacement(x: 0, y: 0, width: 0.5, height: 1))
        #expect(editor.project.mainVideoPlacement.fillsFrame)
        #expect(!editor.isMainVideoWholeFrame)

        editor.fillFrameWithMainVideo()
        #expect(editor.isMainVideoWholeFrame)
        let placement = editor.project.mainVideoPlacement
        #expect(placement.x == 0)
        #expect(placement.width == 1)
    }

    @Test func sideBySideGivesEachPictureAHalf() {
        let editor = model()
        let layer = editor.project.videoLayers[0].id
        editor.splitScreen(.sideBySide, with: layer)

        let main = editor.project.mainVideoPlacement
        let other = editor.project.videoLayers[0].placement
        #expect(abs(main.width - 0.5) < 0.001)
        #expect(abs(other.width - 0.5) < 0.001)
        #expect(abs(other.x - 0.5) < 0.001)
        #expect(main.fillsFrame && other.fillsFrame)
    }

    @Test func swappingExchangesTheTwoRectangles() {
        let editor = model()
        let layer = editor.project.videoLayers[0].id
        editor.splitScreen(.pictureInPicture, with: layer)
        let smallBefore = editor.project.videoLayers[0].placement
        #expect(smallBefore.width < 0.5)

        editor.swapStage(with: layer)
        let main = editor.project.mainVideoPlacement
        #expect(abs(main.width - smallBefore.width) < 0.001)
        #expect(main.fillsFrame)
        #expect(editor.project.videoLayers[0].placement.width > 0.999)
        // Motion from before the swap would pull the layer straight back out of its new place.
        #expect(editor.project.videoLayers[0].keyframes.isEmpty)
    }

    @Test func onlyOnePictureIsPlacedAtATime() {
        let editor = model()
        let layer = editor.project.videoLayers[0].id
        editor.select(videoLayer: layer)
        #expect(editor.placedPiece == .layer(layer))

        editor.placeMainVideo(true)
        #expect(editor.placedPiece == .main)
        #expect(editor.selectedVideoLayer == nil)

        editor.select(videoLayer: layer)
        #expect(!editor.isPlacingMainVideo)
        #expect(editor.placedPiece == .layer(layer))
    }

    @Test func placingThePictureIsOneUndoStepPerDrag() {
        let editor = model()
        let steps = editor.changes.count
        editor.setMainVideoPlacement(VideoPlacement(x: 0.1, y: 0, width: 0.5, height: 1))
        editor.setMainVideoPlacement(VideoPlacement(x: 0.2, y: 0, width: 0.5, height: 1))
        #expect(editor.changes.count == steps + 1)
    }
}
