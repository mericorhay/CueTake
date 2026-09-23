import Foundation
import Testing
@testable import Domain

/// The studio's tools as workflow steps: a loosely written step still runs, and each one lands on
/// the video where an editor would have put it.
struct WorkflowStudioToolsTests {
    private func document(roles: [String], words: [[(String, Double, Double)]] = []) -> EditDocument {
        let segments = roles.map { _ in Segment(role: .mainPoint, script: "s", estimatedDuration: MediaTime(seconds: 10)) }
        var document = EditDocument(project: Project(title: "", localeIdentifier: "en", segments: segments))
        for index in document.clips.indices {
            document.clips[index].role = roles[index]
            document.clips[index].at = Double(index) * 10
            document.clips[index].length = 10
            document.clips[index].speed = 1
            document.clips[index].words = index < words.count
                ? words[index].map { EditDocument.Word(text: $0.0, start: $0.1, end: $0.2) }
                : []
        }
        document.duration = Double(roles.count) * 10
        return document
    }

    @Test func readsLooseStepsWithDefaults() throws {
        let json = """
        {"name":"w","steps":[
          {"type":"autoZoom","parameters":{"style":"punch","amount":"a lot"}},
          {"type":"filter"},
          {"type":"brandTemplate","parameters":{"style":"coupon","lines":{"code":"CUE20"},"moment":"sometime"}},
          {"type":"bestTakes"},
          {"type":"aiEdit","parameters":{"instruction":"warm ending"}}
        ]}
        """
        let workflow = try WorkflowDefinition.decode(json: json)
        let kinds = workflow.steps.map(\.kind)
        #expect(kinds[0] == .autoZoom(ZoomStepOptions(style: .punch, amount: 0.14, spacing: 5)))
        #expect(kinds[1] == .filter(FilterStepOptions()))
        #expect(kinds[2] == .brandTemplate(TemplateStepOptions(style: "coupon", lines: ["code": "CUE20"], moment: .cta)))
        #expect(kinds[3] == .bestTakes)
        #expect(kinds[4] == .aiEdit(AIEditOptions(instruction: "warm ending")))
    }

    @Test func everyStudioToolSurvivesSaving() throws {
        let kinds: [WorkflowStepKind] = [
            .cleanup(CleanupStepOptions(repeats: false)), .bestTakes, .brandKit(BrandStepOptions(logo: false)),
            .addTitle(TitleStepOptions(text: "Hi", moment: .at, seconds: 3)), .brandTemplate(TemplateStepOptions(style: "poll")),
            .filter(FilterStepOptions(look: "warm", target: "hook")), .background(BackgroundStepOptions(style: "dim")),
            .autoZoom(ZoomStepOptions(style: .push)), .trackFace(TrackFaceOptions(closeness: 0.15)),
            .transitions(TransitionStepOptions(kind: "zoomIn", placement: .everyCut)),
            .voiceEffect(VoiceEffectOptions(preset: "radio")), .videoLayout(VideoLayoutOptions(layout: "grid")),
            .aiEdit(AIEditOptions(instruction: "x")),
        ]
        let workflow = WorkflowDefinition(name: "w", steps: kinds.map { WorkflowStep(kind: $0) })
        let decoded = try WorkflowDefinition.decode(json: workflow.jsonString())
        #expect(Array(decoded.steps.map(\.kind).prefix(kinds.count)) == kinds)
        for kind in kinds {
            #expect(WorkflowStepKind.knownTypes.contains(kind.typeName))
        }
    }

    @Test func zoomLandsOnSentenceStartsSpacedOut() {
        let words: [(String, Double, Double)] = [
            ("One", 0, 0.4), ("two.", 0.5, 0.9), ("Three", 1.0, 1.4), ("four", 1.5, 1.9),
            ("five", 6.0, 6.4), ("six", 6.5, 6.9),
        ]
        let moves = WorkflowStudioPlanner.zoom(ZoomStepOptions(style: .mixed, amount: 0.1, spacing: 5), in: document(roles: ["hook"], words: [words]))
        let requests = moves.compactMap { op -> CameraMoveRequest? in
            if case .cameraMove(let request) = op { return request }
            return nil
        }
        #expect(requests.map(\.at) == [0, 6.0])
        #expect(requests.map(\.kind) == [.pushIn, .punch])
        #expect(requests.allSatisfy { ($0.to ?? 0) <= 9.95 })
    }

    @Test func sectionTransitionsOnlyWhereTheStoryChanges() {
        let ops = WorkflowStudioPlanner.transitions(
            TransitionStepOptions(kind: "crossfade", seconds: 0.5, placement: .sections),
            in: document(roles: ["hook", "point", "point", "cta"])
        )
        let clips = ops.compactMap { op -> String? in
            if case .transition(let clip, _, _) = op { return clip }
            return nil
        }
        #expect(clips == ["c1", "c3"])
    }

    @Test func titleAndTemplateFindTheirMoment() {
        let doc = document(roles: ["hook", "point", "cta"], words: [[("Stop", 0, 0.3), ("scrolling", 0.35, 0.8), ("now!", 0.85, 1.1), ("Here", 1.5, 1.7)]])
        let title = WorkflowStudioPlanner.title(TitleStepOptions(), in: doc)
        if case .addText(let patch) = title.first {
            #expect(patch.text == "Stop scrolling now!")
            #expect(patch.start == 0.2)
        } else {
            Issue.record("no title")
        }

        let template = WorkflowStudioPlanner.template(
            TemplateStepOptions(style: "codeCard", lines: ["code": "CUE20", "price": "not a slot", "note": " "], moment: .cta, duration: 4),
            in: doc
        )
        if case .addTemplate(let request) = template.first {
            #expect(request.texts == ["code": "CUE20"])
            #expect(request.start == 20.2)
            #expect(request.color == nil)
        } else {
            Issue.record("no template")
        }
    }

    @Test func sectionTargetsNameTheirClips() {
        let ops = WorkflowStudioPlanner.filter(FilterStepOptions(look: "warm", target: "cta"), in: document(roles: ["hook", "cta", "cta"]))
        let clips = ops.compactMap { op -> String? in
            if case .setFilter(let request) = op { return request.clip }
            return nil
        }
        #expect(clips == ["c2", "c3"])
    }
}
