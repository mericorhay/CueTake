import Foundation
import Testing
@testable import Domain

struct ScriptLibraryTests {
    private func sentence(_ count: Int, _ tag: String) -> String {
        (1...count).map { "\(tag)\($0)" }.joined(separator: " ") + "."
    }

    @Test func aLongDraftLosesMiddleBeatsFirst() {
        let draft = ScriptDraft(title: "t", segments: [
            SegmentDraft(role: .hook, title: "", script: sentence(10, "h")),
            SegmentDraft(role: .mainPoint, title: "", script: sentence(20, "a")),
            SegmentDraft(role: .mainPoint, title: "", script: sentence(20, "b")),
            SegmentDraft(role: .example, title: "", script: sentence(20, "c")),
            SegmentDraft(role: .callToAction, title: "", script: sentence(8, "e")),
        ])
        #expect(ScriptBudget.maxWords(seconds: 15, localeIdentifier: "en") == 38)
        let fitted = ScriptBudget.fit(draft, seconds: 15, localeIdentifier: "en")
        let roles = fitted.segments.map(\.role)
        #expect(roles == [.hook, .mainPoint, .callToAction])
        #expect(fitted.segments[1].script.hasPrefix("a1"))
        #expect(abs((fitted.segments[0].estimatedDuration?.seconds ?? 0) - 4) < 0.001)
    }

    @Test func aLongBeatLosesSentencesFromItsEnd() {
        let text = [sentence(20, "a"), sentence(20, "b"), sentence(20, "c")].joined(separator: " ")
        let draft = ScriptDraft(title: "t", segments: [SegmentDraft(role: .mainPoint, title: "", script: text)])
        let fitted = ScriptBudget.fit(draft, seconds: 15, localeIdentifier: "en")
        let words = ScriptText.words(in: fitted.segments[0].script)
        #expect(words.count == 40)
        #expect(words.last == "b20.")

        // Within the budget: untouched apart from timing.
        let short = ScriptDraft(title: "t", segments: [SegmentDraft(role: .hook, title: "", script: sentence(30, "s"))])
        #expect(ScriptBudget.fit(short, seconds: 15, localeIdentifier: "en").segments[0].script == short.segments[0].script)
        // Turkish is spoken slower, so the same length holds fewer words.
        #expect(ScriptBudget.maxWords(seconds: 30, localeIdentifier: "tr") < ScriptBudget.maxWords(seconds: 30, localeIdentifier: "en"))
        #expect(ScriptBudget.maxWords(seconds: 600, localeIdentifier: "en") == 225)
    }

    @Test func theBrandVoiceIsShortContext() {
        #expect(BrandVoice().isEmpty)
        #expect(BrandVoice().briefText.isEmpty)
        let voice = BrandVoice(name: "Kahve Lab", about: String(repeating: "x", count: 900), mustSay: "Bir fincan yeter.")
        #expect(!voice.isEmpty)
        let text = voice.briefText
        #expect(text.contains("Brand: Kahve Lab"))
        #expect(text.contains("Must say: Bir fincan yeter."))
        #expect(!text.contains("Audience"))
        #expect(text.count < 600)

        // A brief written before brands existed still reads.
        let old = #"{"targetDuration":{"value":18000,"timescale":600},"platform":"tiktok"}"#
        let brief = try? JSONDecoder().decode(ScriptBrief.self, from: Data(old.utf8))
        #expect(brief != nil)
        #expect(brief?.brand == nil)
        #expect(SavedScript.title(for: "*Merhaba* arkadaşlar bugün size bir şey anlatacağım") == "Merhaba arkadaşlar bugün size bir")
    }
}
