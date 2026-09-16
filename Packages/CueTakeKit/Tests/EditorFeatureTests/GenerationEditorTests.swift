import Foundation
import Testing
@testable import Domain
@testable import EditorFeature

@MainActor
struct GenerationEditorTests {
    private func model() -> EditorModel {
        let recording = Recording(relativePath: "media/a.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 20))
        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 10)),
            status: .ready
        )
        let first = Segment(role: .hook, script: "", takes: [take], selectedTakeID: take.id)
        let secondTake = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: MediaTime(seconds: 10), duration: MediaTime(seconds: 5)),
            status: .ready
        )
        let second = Segment(role: .callToAction, script: "", takes: [secondTake], selectedTakeID: secondTake.id)
        let model = EditorModel(project: Project(title: "t", localeIdentifier: "en", segments: [first, second], recordings: [recording]))
        model.generationHasKey = { _ in true }
        return model
    }

    /// A generator that answers after a moment with a six second clip.
    private func madeClip(seconds: Double = 6) -> GeneratedClip {
        let recording = Recording(relativePath: "media/g.mov", format: .vertical1080, camera: .back, duration: MediaTime(seconds: seconds))
        let take = Take(recordingID: recording.id, sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: seconds)), status: .ready)
        return GeneratedClip(recording: recording, take: take, thumbnail: nil)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aGeneratedShotLandsAsBrollAtThePlayhead() async {
        let model = model()
        let clip = madeClip()
        var asked: ClipGenerationRequest?
        model.clipGenerator = { request, progress in
            asked = request
            progress(0.5)
            return clip
        }
        model.generationDefaults = GenerateVideoOptions(preset: "veo-3.1", seconds: 30, aspect: "16:9")
        model.seek(to: 12)

        let id = model.generateClip(prompt: "  Waves on a beach  ")
        #expect(id != nil)
        #expect(model.generationJobs.count == 1)
        await waitUntil { model.project.videoLayers.count == 1 }

        // Fitted to the model and to this portrait project.
        #expect(asked?.prompt == "Waves on a beach")
        #expect(asked?.options.seconds == 8)
        #expect(asked?.options.aspect == "9:16")

        let layer = model.project.videoLayers[0]
        #expect(abs(layer.start.seconds - 12) < 0.001)
        #expect(layer.isMuted)
        // Cut to where the video ends.
        #expect(abs(layer.duration - 3) < 0.01)
        #expect(model.project.recordings.contains { $0.id == clip.recording.id })
        #expect(model.generationJobs.first?.phase == .done)

        model.undo()
        #expect(model.project.videoLayers.isEmpty)
    }

    @Test func aGeneratedClipGoesAfterTheClipAtItsMoment() async {
        let model = model()
        model.clipGenerator = { _, _ in self.madeClip() }
        model.generationPlacement = .clip
        model.seek(to: 3)
        model.generateClip(prompt: "A city at night")
        await waitUntil { model.project.segments.count == 3 }

        #expect(model.project.segments.count == 3)
        #expect(model.project.segments[1].metadata["generatedBy"] == "video-model")
        #expect(model.project.segments[2].role == .callToAction)
    }

    @Test func aFailedShotCanBeTriedAgain() async {
        let model = model()
        var attempts = 0
        model.clipGenerator = { _, _ in
            attempts += 1
            if attempts == 1 { throw URLError(.timedOut) }
            return self.madeClip()
        }
        let id = model.generateClip(prompt: "Rain")!
        await waitUntil { model.generationJobs.first?.phase == .failed }
        #expect(model.generationJobs.first?.failure != nil)
        #expect(model.project.videoLayers.isEmpty)

        model.retryGeneration(id)
        await waitUntil { model.project.videoLayers.count == 1 }
        #expect(attempts == 2)
    }

    @Test func withoutAGeneratorNothingStarts() {
        let model = model()
        #expect(model.generateClip(prompt: "x") == nil)
        #expect(model.aiVideoModel == nil)
        #expect(model.generationJobs.isEmpty)
    }

    @Test func theAIPlansBrollOnlyWhenAModelIsConnected() throws {
        let plan = try EditPlan.decode(from: """
        {"summary":"s","operations":[{"op":"generateVideo","prompt":"Ocean waves","at":4,"seconds":5,"as":"broll"}]}
        """)
        guard case .generateVideo(let request) = plan.operations.first else {
            Issue.record("did not decode")
            return
        }
        #expect(request.prompt == "Ocean waves")
        #expect(request.at == 4 && request.seconds == 5 && !request.asClip)

        let model = model()
        // No generator: the step is reported, not faked.
        #expect(model.apply(plan).skipped == ["generateVideo"])

        model.clipGenerator = { _, _ in self.madeClip() }
        #expect(model.aiVideoModel == "seedance-2.5")
        #expect(model.document().videoModel == nil)
    }
}
