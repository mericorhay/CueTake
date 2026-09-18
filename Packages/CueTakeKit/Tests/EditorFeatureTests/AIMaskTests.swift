import Foundation
import Testing
@testable import Domain
@testable import EditorFeature

/// The assistant can use the masks: text behind the person, an object or a screen kept in front
/// of a new background, a green screen taken out of an added video.
@MainActor
struct AIMaskTests {
    private func model() -> EditorModel {
        let recording = Recording(relativePath: "media/a.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 20))
        let screen = Recording(relativePath: "media/b.mov", format: .vertical1080, camera: .back, duration: MediaTime(seconds: 20))
        let take = Take(recordingID: recording.id, sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 10)), status: .ready)
        let segment = Segment(role: .mainPoint, script: "", takes: [take], selectedTakeID: take.id)
        var project = Project(title: "t", localeIdentifier: "en", segments: [segment], recordings: [recording, screen])
        project.videoLayers = [VideoLayer(recordingID: screen.id, title: "b", sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 4)))]
        return EditorModel(project: project)
    }

    @Test func theNewFieldsAreReadFromThePlan() throws {
        let plan = try EditPlan.decode(from: """
        {"summary":"","operations":[
          {"op":"addText","text":"BIG","behind":true},
          {"op":"setBackground","style":"studio","keep":"screen","screen":"#0000FF"},
          {"op":"updateVideo","video":"v1","screen":"none"}
        ]}
        """)
        #expect(plan.operations[0] == .addText(EditPlan.OverlayPatch(text: "BIG", behind: true)))
        #expect(plan.operations[1] == .setBackground(BackgroundRequest(style: "studio", keep: "screen", screen: "#0000FF")))
        #expect(plan.operations[2] == .updateVideo(video: "v1", patch: VideoPatch(screen: "none")))
        let again = try JSONDecoder().decode(EditPlan.self, from: JSONEncoder().encode(plan))
        #expect(again == plan)
    }

    @Test func theAssistantPutsTextBehindThePersonAndKeysAScreen() {
        let model = model()
        let video = model.project.videoLayers[0].id
        let outcome = model.apply(EditPlan(summary: "", operations: [
            .addText(EditPlan.OverlayPatch(text: "BIG", start: 1, behind: true)),
            .setBackground(BackgroundRequest(style: "studio", keep: "screen")),
            .updateVideo(video: video.uuidString, patch: VideoPatch(screen: "#0000FF")),
        ]))
        #expect(outcome.skipped.isEmpty)
        #expect(model.project.overlays.first?.isBehindPerson == true)
        let background = model.project.effects.first?.background
        #expect(background?.cutout == .color)
        #expect(background?.key == .green)
        let key = model.project.videoLayers[0].chroma
        #expect(key?.color.blue == 1)
        #expect(key?.color.green == 0)

        _ = model.apply(EditPlan(summary: "", operations: [
            .updateVideo(video: video.uuidString, patch: VideoPatch(screen: "none")),
        ]))
        #expect(model.project.videoLayers[0].chroma == nil)
    }

    @Test func theDocumentTellsTheAssistantWhatIsBehindAndKeyed() throws {
        let model = model()
        var overlay = Overlay(content: .text(OverlayText(text: "BIG")), start: .zero)
        overlay.isBehindPerson = true
        model.project.overlays = [overlay]
        model.project.videoLayers[0].chroma = .green
        model.project.effects = [TimelineEffect(
            start: .zero,
            duration: MediaTime(seconds: 2),
            kind: .background(BackgroundSettings(style: .black, cutout: .subject))
        )]
        let document = EditDocument(project: model.project)
        #expect(document.overlays?.first?.behind == true)
        #expect(document.videos?.first?.screen == ChromaKey.green.color.hex)
        #expect(document.effects?.first?.keep == "subject")
        #expect(document.effects?.first?.screen == nil)
    }
}
