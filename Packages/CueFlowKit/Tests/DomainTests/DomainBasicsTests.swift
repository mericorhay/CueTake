import Foundation
import Testing
@testable import Domain

struct MediaTimeTests {
    @Test func equalityIsRational() {
        let half = MediaTime(value: 1, timescale: 2)
        let alsoHalf = MediaTime(value: 300, timescale: 600)

        #expect(half == alsoHalf)
        #expect(Set([half, alsoHalf]).count == 1)
        #expect(half + alsoHalf == MediaTime(seconds: 1))
    }
}

struct TurkishTextTests {
    let turkish = Locale(identifier: "tr_TR")

    @Test func captionUppercaseUsesDottedCapitalI() {
        #expect(CaptionTextCase.uppercase.apply(to: "istanbul", locale: turkish) == "İSTANBUL")
    }

    @Test func matchKeyFoldsTurkishCaseAndPunctuation() {
        #expect(ScriptText.matchKey(for: "İSTANBUL'DA,", locale: turkish) == "istanbul'da")
    }
}

struct WorkflowCodingTests {
    @Test func definitionRoundTrips() throws {
        let definition = WorkflowDefinition(name: "Instagram product video", steps: [
            WorkflowStep(kind: .generateScript(ScriptBrief(topic: nil, targetDuration: MediaTime(seconds: 30), platform: .instagramReels))),
            WorkflowStep(kind: .segmentScript),
            WorkflowStep(kind: .record(RecordStepOptions())),
            WorkflowStep(kind: .analyzeSpeech),
            WorkflowStep(kind: .generateCaptions),
            WorkflowStep(kind: .applyCaptionStyle(presetID: "bold-pop")),
            WorkflowStep(kind: .export(.shortFormVertical)),
        ])

        let data = try JSONEncoder().encode(definition)
        let decoded = try JSONDecoder().decode(WorkflowDefinition.self, from: data)

        #expect(decoded.steps == definition.steps)
        #expect(decoded.schemaVersion == WorkflowDefinition.currentSchemaVersion)
    }

    @Test func unknownStepTypeDecodesAsUnsupported() throws {
        let json = #"{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","kind":{"type":"translateVideo","parameters":{"to":"de"}},"isEnabled":true}"#

        let step = try JSONDecoder().decode(WorkflowStep.self, from: Data(json.utf8))

        #expect(step.kind == .unsupported(type: "translateVideo"))
    }
}
