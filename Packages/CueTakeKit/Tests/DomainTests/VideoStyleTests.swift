import Foundation
import Testing
@testable import Domain

/// A style is a promise of a finished look: it must listen before it cuts, use only looks the
/// app has, and survive being saved inside a workflow.
struct VideoStyleTests {
    @Test func everyStyleListensFirstAndUsesRealLooks() {
        for style in VideoStyle.allCases {
            #expect(style.steps.first == .analyzeSpeech, "\(style)")
            #expect(CaptionStyle.presetIDs.contains(style.captionPreset), "\(style)")
            #expect(style.steps.contains { if case .soundDesign = $0 { true } else { false } }, "\(style)")
            #expect(style.steps.allSatisfy { !$0.isFinalExport && $0.typeName != "applyStyle" }, "\(style)")
            // Captions come before anything that places itself on the words.
            let captions = style.steps.firstIndex(of: .generateCaptions) ?? .max
            let sound = style.steps.firstIndex { if case .soundDesign = $0 { true } else { false } } ?? -1
            #expect(captions < sound, "\(style)")
        }
    }

    @Test func stylesHaveTheirOwnStableWorkflows() {
        let ids = Set(VideoStyle.allCases.map { $0.workflow(name: "x").id })
        #expect(ids.count == VideoStyle.allCases.count)
        #expect(VideoStyle.vlog.workflow(name: "a").id == VideoStyle.vlog.workflow(name: "b").id)
    }

    @Test func applyStyleStepReadsLoosely() throws {
        let workflow = try WorkflowDefinition.decode(json: #"{"name":"w","steps":[{"type":"applyStyle","parameters":{"style":"vlog"}},{"type":"applyStyle","parameters":{"style":"tiktok"}}]}"#)
        #expect(workflow.steps[0].kind == .applyStyle(ApplyStyleOptions(style: .vlog)))
        #expect(workflow.steps[1].kind == .applyStyle(ApplyStyleOptions(style: .boldBusiness)))
    }
}
