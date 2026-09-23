import Foundation
import Testing
@testable import Domain

/// Sound design follows what is on screen: every sound answers a cut, a title or a zoom, and two
/// sounds never pile onto one moment.
struct SoundDesignTests {
    private func document(roles: [String]) -> EditDocument {
        let segments = roles.map { _ in Segment(role: .mainPoint, script: "s", estimatedDuration: MediaTime(seconds: 5)) }
        var document = EditDocument(project: Project(title: "", localeIdentifier: "en", segments: segments))
        for index in document.clips.indices {
            document.clips[index].role = roles[index]
            document.clips[index].at = Double(index) * 5
            document.clips[index].length = 5
        }
        document.duration = Double(roles.count) * 5
        return document
    }

    @Test func soundsAnswerWhatIsOnScreen() {
        var doc = document(roles: ["hook", "point", "cta"])
        doc.clips[0].transition = "crossfade"
        doc.cameraMoves = [EditDocument.CameraMove(id: "m1", at: 7, length: 1, kind: "punch", amount: 0.2, feel: nil)]

        let cues = SoundDesign.plan(SoundDesignOptions(), for: doc)
        let kinds = cues.map(\.kind)
        #expect(kinds == [.whoosh, .impact, .ding])
        // The whoosh peaks on the cut, so it starts before it.
        #expect(abs(cues[0].start - (5 - SoundCueKind.whoosh.peak)) < 0.001)
        #expect(abs(cues[2].start - 10.15) < 0.001)
    }

    @Test func twoSoundsNeverShareAMoment() {
        var doc = document(roles: ["hook", "cta"])
        doc.clips[0].transition = "fadeBlack"
        // A punch-in right on the cut: the transition's whoosh wins.
        doc.cameraMoves = [EditDocument.CameraMove(id: "m1", at: 5.1, length: 1, kind: "punch", amount: 0.2, feel: nil)]
        let cues = SoundDesign.plan(SoundDesignOptions(dings: false), for: doc)
        #expect(cues.map(\.kind) == [.whoosh])
    }

    @Test func intensityChangesHowMuchAndHowLoud() {
        let doc = document(roles: ["hook", "point", "point", "cta"])
        let subtle = SoundDesign.plan(SoundDesignOptions(intensity: .subtle, dings: false), for: doc)
        let bold = SoundDesign.plan(SoundDesignOptions(intensity: .bold, dings: false), for: doc)
        // Subtle only marks transitions (there are none); bold marks every cut and adds a riser.
        #expect(subtle.isEmpty)
        #expect(bold.filter { $0.kind == .whoosh }.count == 3)
        #expect(bold.contains { $0.kind == .riser })
        #expect(bold.allSatisfy { $0.start >= 0 })
    }

    @Test func onlyItsOwnSoundsAreReplaced() {
        let mine = AudioClip(name: "Theme", relativePath: "media/theme.m4a", sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 3)))
        let auto = AudioClip(name: "Pop", relativePath: "media/\(SoundCueKind.pop.fileName)", role: .effect, sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 0.2)))
        #expect(!SoundDesign.isAutomatic(mine))
        #expect(SoundDesign.isAutomatic(auto))
    }

    @Test func aiCanAskForIt() throws {
        let plan = try EditPlan.decode(from: #"{"summary":"s","operations":[{"op":"soundDesign","intensity":"bold"},{"op":"sfx","on":false}]}"#)
        #expect(plan.operations == [.soundDesign(intensity: "bold", on: true), .soundDesign(intensity: nil, on: false)])
    }

    @Test func workflowStepReadsLoosely() throws {
        let workflow = try WorkflowDefinition.decode(json: #"{"name":"w","steps":[{"type":"soundDesign","parameters":{"intensity":"loud","pops":false}}]}"#)
        #expect(workflow.steps.first?.kind == .soundDesign(SoundDesignOptions(intensity: .normal, pops: false)))
    }
}
