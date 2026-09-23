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

struct VideoFormatTests {
    @Test func retiredResolutionMigratesToSupportedMaximum() throws {
        let decoded = try JSONDecoder().decode(VideoFormat.Resolution.self, from: Data(#""uhd8K""#.utf8))
        #expect(decoded == .uhd4K)
        #expect(String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self) == #""uhd4K""#)
    }

    @Test func deliveryFormatKeepsFourKInsideReliableFrameRateEnvelope() {
        let format = VideoFormat(aspectRatio: .portrait9x16, resolution: .uhd4K, frameRate: 120)
        #expect(format.deliveryCompatible.resolution == .uhd4K)
        #expect(format.deliveryCompatible.frameRate == 60)
        #expect(VideoFormat(aspectRatio: .portrait9x16, resolution: .hd1080, frameRate: 120).deliveryCompatible.frameRate == 120)
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

/// Every workflow ends with one export, whatever the document said.
struct WorkflowFinalExportTests {
    @Test func aWorkflowWithoutExportGetsOneLast() throws {
        let workflow = try WorkflowDefinition.decode(json: #"{"name":"x","steps":[{"type":"export","parameters":{"destination":"files"}},{"type":"analyzeSpeech"},{"type":"export"}]}"#)
        #expect(workflow.steps.count == 2)
        #expect(workflow.steps.last?.kind.isFinalExport == true)
        #expect(workflow.steps.first?.kind.typeName == "analyzeSpeech")

        let empty = WorkflowDefinition(name: "e", style: WorkflowStyle(resolution: .uhd4K, frameRate: 60), steps: [])
        guard case .export(let preset)? = empty.finalExport?.kind else {
            Issue.record("no export")
            return
        }
        // The export says what the style says, not a fixed 1080p30.
        #expect(preset.format.resolution == .uhd4K)
        #expect(preset.format.frameRate == 60)
    }

    @Test func deliveryDecodesLenientlyAndKeepsItsSecretOut() throws {
        let workflow = try WorkflowDefinition.decode(json: #"{"name":"x","steps":[{"type":"export","parameters":{"delivery":{"url":"https://api.example.com/upload","method":"put","fields":{"channel":"a"}}}}]}"#)
        let delivery = try #require(workflow.delivery)
        #expect(delivery.isReady)
        #expect(delivery.method == .put)
        #expect(delivery.fields["channel"] == "a")
        #expect(WorkflowDelivery(isEnabled: true, endpoint: "http://example.com").url == nil)
        #expect(delivery.authorization(secret: " abc ")?.value == "Bearer abc")
        let json = try workflow.jsonString()
        #expect(!json.contains("abc"))
    }
}
