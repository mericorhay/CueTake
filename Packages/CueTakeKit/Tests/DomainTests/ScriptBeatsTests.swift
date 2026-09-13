import Foundation
import Testing
@testable import Domain

/// Pasting a script. What matters is that the writer's own breaks are kept and that one long block
/// still becomes something a prompter can show a beat at a time.
struct ScriptBeatsTests {
    @Test func paragraphsAreBeats() {
        let text = "Stop scrolling.\n\nHere is the trick.\nIt takes a minute.\n\nFollow for more."
        let beats = ScriptText.beats(from: text, localeIdentifier: "en")
        #expect(beats.map(\.script) == ["Stop scrolling.", "Here is the trick. It takes a minute.", "Follow for more."])
        #expect(beats.map(\.role) == [.hook, .mainPoint, .callToAction])
    }

    @Test func oneBlockIsCutAtSentences() {
        let text = "Bunu bilmiyordun. Birinci adım basit. İkinci adım da öyle. Üçüncüsü en önemlisi. Dördüncüyü unutma. Takip et."
        let beats = ScriptText.beats(from: text, localeIdentifier: "tr")
        #expect(beats.first?.script == "Bunu bilmiyordun.")
        #expect(beats.first?.role == .hook)
        #expect(beats.last?.script == "Takip et.")
        #expect(beats.last?.role == .callToAction)
        #expect(beats.count == 4)
        #expect(beats.allSatisfy { ($0.estimatedDuration?.seconds ?? 0) >= 1 })
    }

    @Test func emptyTextIsNoBeats() {
        #expect(ScriptText.beats(from: "  \n ", localeIdentifier: "en").isEmpty)
        #expect(ScriptText.beats(from: "Just one line", localeIdentifier: "en").map(\.role) == [.mainPoint])
    }
}
