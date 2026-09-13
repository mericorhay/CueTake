import Foundation
import Testing
@testable import Domain

/// The AI's vocabulary and the restore behind "take this change back". What these guard is trust:
/// a plan written a little loosely still does what it says, and undoing one AI change never undoes
/// something else.
struct AIControlTests {
    @Test func decodesTheWholeVocabulary() throws {
        let text = """
        Sure:
        {"summary":"s","operations":[
          {"op":"addText","text":"Hello","start":"2.5","duration":3,"y":0.2,"animation":"pop"},
          {"op":"captionStyle","preset":"bold","size":0.06,"highlightColor":"none"},
          {"op":"captionStyle","preset":"clean"},
          {"op":"voiceCleanup","noiseReduction":true},
          {"op":"captionWindow","from":2,"to":null},
          {"op":"splitClip","clip":"C","at":"4"},
          {"op":"updateAudio","audio":"A","gainDb":-12,"muted":"true"},
          "not an object",
          {"op":"setTitle","title":"New"}
        ]}
        """
        let plan = try EditPlan.decode(from: text)
        #expect(plan.operations.count == 9)
        #expect(plan.operations[0] == .addText(EditPlan.OverlayPatch(text: "Hello", start: 2.5, duration: 3, y: 0.2, animation: "pop")))
        #expect(plan.operations[1] == .captionLook(EditPlan.CaptionLook(preset: "bold", size: 0.06, highlightColor: "none")))
        #expect(plan.operations[2] == .captionStyle(preset: "clean", position: nil))
        #expect(plan.operations[3] == .voiceEffects(noiseReduction: true, voiceEnhance: nil, deRumble: nil))
        #expect(plan.operations[4] == .captionWindow(from: 2, to: nil))
        #expect(plan.operations[5] == .splitClip(clip: "C", at: 4))
        #expect(plan.operations[6] == .updateAudio(audio: "A", patch: EditPlan.AudioPatch(gainDb: -12, muted: true)))
        #expect(plan.operations[7] == .unknown(type: "unknown"))
        #expect(plan.operations[8] == .setTitle("New"))

        let again = try JSONDecoder().decode(EditPlan.self, from: JSONEncoder().encode(plan))
        #expect(again == plan)
    }

    @Test func hexColoursRoundTrip() {
        let orange = RGBAColor(hex: "#FF8000")
        #expect(orange?.red == 1)
        #expect(orange?.hex == "#FF8000")
        #expect(RGBAColor(hex: "00000080")?.hex == "#00000080")
        #expect(RGBAColor(hex: "red") == nil)
    }

    @Test func restoringPutsBackOnlyWhatWasTouched() {
        let a = Segment(role: .hook, script: "a", estimatedDuration: MediaTime(seconds: 3))
        let b = Segment(role: .mainPoint, script: "b", estimatedDuration: MediaTime(seconds: 3))
        let before = Project(title: "Before", localeIdentifier: "en", segments: [a, b])

        // What the AI did: deleted the hook, changed the look, added a title.
        var after = before
        after.segments.remove(at: 0)
        after.captionStyle = CaptionStyle.preset("bold")
        let title = Overlay(content: .text(OverlayText(text: "Hi")), start: .zero)
        after.overlays.append(title)
        after.title = "After"

        // What the user did afterwards, by hand.
        var now = after
        let mine = Overlay(content: .text(OverlayText(text: "Mine")), start: .zero)
        now.overlays.append(mine)

        let restored = now.restoring([.clip(a.id), .overlay(title.id)], from: before)
        #expect(restored.segments.map(\.id) == [a.id, b.id])
        #expect(restored.overlays.map(\.id) == [mine.id])
        #expect(restored.captionStyle.presetID == "bold")
        #expect(restored.title == "After")

        let reapplied = restored.restoring([.clip(a.id), .overlay(title.id)], from: after)
        #expect(reapplied.segments.map(\.id) == [b.id])
        #expect(reapplied.overlays.map(\.id).contains(title.id))
        #expect(reapplied.overlays.map(\.id).contains(mine.id))
    }

    @Test func orderComesBackAroundNewClips() {
        let a = Segment(role: .hook, script: "a", estimatedDuration: MediaTime(seconds: 2))
        let b = Segment(role: .mainPoint, script: "b", estimatedDuration: MediaTime(seconds: 2))
        let c = Segment(role: .callToAction, script: "c", estimatedDuration: MediaTime(seconds: 2))
        let d = Segment(role: .example, script: "d", estimatedDuration: MediaTime(seconds: 2))
        let before = Project(title: "t", localeIdentifier: "en", segments: [a, b, c])
        var now = before
        now.segments = [c, d, a]

        let restored = now.restoring([.clipOrder], from: before)
        #expect(restored.segments.map(\.id) == [a.id, d.id, c.id])
    }

    @Test func documentCarriesOverlaysAndTheFullLook() throws {
        let segment = Segment(role: .hook, script: "a", estimatedDuration: MediaTime(seconds: 4))
        var project = Project(title: "t", localeIdentifier: "en", segments: [segment])
        project.overlays = [
            Overlay(content: .text(OverlayText(text: "Hi")), start: MediaTime(seconds: 1), duration: MediaTime(seconds: 1)),
        ]
        let document = EditDocument(project: project)
        #expect(document.schema == "cuetake.edit-document/3")
        #expect(document.overlays?.first?.id == "o1")
        #expect(document.overlays?.first?.text == "Hi")
        #expect(document.overlays?.first?.length == 1)
        #expect(document.audio == nil)
        #expect(document.style.textColor.hasPrefix("#"))
        #expect(document.fonts == OverlayText.fonts)
        let json = String(decoding: try document.jsonData(), as: UTF8.self)
        // Short names only: no full ids spent on the model's token budget.
        #expect(!json.contains(project.overlays[0].id.uuidString))
    }

    @Test func shortReferencesResolveToRealIDs() {
        let recording = UUID()
        func take(_ words: [String]) -> Take {
            Take(
                recordingID: recording,
                sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 3)),
                status: .ready,
                transcript: Transcript(localeIdentifier: "en", words: words.enumerated().map { i, text in
                    TimedWord(text: text, range: MediaTimeRange(start: MediaTime(seconds: Double(i)), duration: MediaTime(seconds: 0.4)))
                })
            )
        }
        let first = take(["a", "b"])
        let second = take(["c"])
        var a = Segment(role: .hook, script: "", takes: [first, second], selectedTakeID: first.id)
        a.refreshCaptions(maxWordsPerCue: 1)
        let b = Segment(role: .mainPoint, script: "b", estimatedDuration: MediaTime(seconds: 2))
        var project = Project(title: "t", localeIdentifier: "en", segments: [a, b])
        project.overlays = [Overlay(content: .text(OverlayText(text: "Hi")), start: .zero)]

        let plan = EditPlan(summary: "", operations: [
            .deleteClip(clip: "c2"),
            .setSpeed(clip: "1", speed: 2),
            .setCaptionText(caption: "K2", text: "x"),
            .removeOverlay(overlay: "o1"),
            .selectTake(clip: "c1", take: "t2"),
            .reorder(clips: ["c2", String(a.id.uuidString.prefix(8))]),
            .deleteClip(clip: "c9"),
        ]).resolvingReferences(in: project)

        #expect(plan.operations[0] == .deleteClip(clip: b.id.uuidString))
        #expect(plan.operations[1] == .setSpeed(clip: a.id.uuidString, speed: 2))
        #expect(plan.operations[2] == .setCaptionText(caption: a.captions[1].id.uuidString, text: "x"))
        #expect(plan.operations[3] == .removeOverlay(overlay: project.overlays[0].id.uuidString))
        #expect(plan.operations[4] == .selectTake(clip: a.id.uuidString, take: second.id.uuidString))
        #expect(plan.operations[5] == .reorder(clips: [b.id.uuidString, a.id.uuidString]))
        #expect(plan.operations[6] == .deleteClip(clip: "c9"))
    }
}
