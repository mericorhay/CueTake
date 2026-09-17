import Foundation
import Testing
@testable import Domain

struct CleanupTests {
    private let en = Locale(identifier: "en-US")
    private let tr = Locale(identifier: "tr-TR")

    /// Words 0.4 s apart, each 0.3 s long, starting at `start`.
    private func words(_ text: String, start: Double = 0.2) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { index, word in
            TimedWord(
                text: String(word),
                range: MediaTimeRange(start: MediaTime(seconds: start + Double(index) * 0.4), duration: MediaTime(seconds: 0.3)),
                confidence: 0.9
            )
        }
    }

    private func plan(_ spoken: String, script: String, locale: Locale) -> CleanupPlan {
        let said = words(spoken)
        return CleanupPlanner.plan(
            words: said,
            script: script,
            total: (said.last?.range.end.seconds ?? 0) + 0.3,
            segmentID: UUID(),
            locale: locale
        )
    }

    // MARK: - Alignment

    @Test func aRestartLeavesTheFirstAttemptOver() {
        let alignment = ScriptAlignment.align(
            spoken: "today I will today I will show you".split(separator: " ").map(String.init),
            script: "Today I will show you.".split(separator: " ").map(String.init),
            locale: en
        )
        #expect(alignment.spoken[0] == .extra)
        #expect(alignment.spoken[1] == .extra)
        #expect(alignment.spoken[2] == .extra)
        #expect(alignment.spoken[3] == .exact(0))
        #expect(alignment.spoken[7] == .exact(4))
        #expect(alignment.missed.isEmpty)
        #expect(alignment.coverage == 1)
        #expect(alignment.isUsable)
    }

    @Test func wordsAreComparedTheWayTheyAreSpoken() {
        #expect(ScriptAlignment.key("İstanbul'da,", locale: tr) == "istanbulda")
        #expect(ScriptAlignment.similarity("kameranin", "kameranın") >= 0.9)
        #expect(ScriptAlignment.similarity("anlatacağım", "anlatacağımı") > 0)
        #expect(ScriptAlignment.similarity("bu", "bir") == 0)

        let alignment = ScriptAlignment.align(
            spoken: ["kameranin", "açısı", "çok", "önemli"],
            script: ["Kameranın", "açısı", "önemli"],
            locale: tr
        )
        #expect(alignment.spoken[0] == .close(0))
        #expect(alignment.spoken[2] == .extra)
        #expect(alignment.accuracy > 0.8)
    }

    @Test func anUnrelatedScriptIsNotUsed() {
        let alignment = ScriptAlignment.align(
            spoken: ["hello", "everyone", "welcome", "back"],
            script: ["the", "lens", "matters", "most", "here"],
            locale: en
        )
        #expect(!alignment.isUsable)
    }

    // MARK: - Planning

    @Test func withAScriptFillerWordsAreCutOnlyWhenTheScriptDoesNotHaveThem() {
        let offered = plan("so um this is like the point", script: "This is the point.", locale: en)
        let fillers = offered.items.filter { $0.kind == .filler }
        let texts = fillers.map { $0.text }
        let allOn = fillers.allSatisfy { $0.isOn }
        #expect(texts == ["so um", "like"])
        #expect(allOn)

        // "like" is in this script, so it stays.
        let meant = plan("this is like the point", script: "This is like the point.", locale: en)
        #expect(meant.items.filter { $0.kind == .filler }.isEmpty)
    }

    @Test func withoutAScriptOnlySoundsAreCutAndRepeatsFollowTheLanguage() {
        let english = plan("so um this this is great", script: "", locale: en)
        #expect(english.alignment == nil)
        let sound = english.items.first { $0.text == "um" }
        #expect(sound?.isOn == true)
        let word = english.items.first { $0.text == "so" }
        #expect(word?.isOn == false)
        let repeated = english.items.first { $0.kind == .repeated }
        #expect(repeated?.words == 2...2)
        #expect(repeated?.isOn == true)

        // Turkish doubles words on purpose.
        let turkish = plan("bu çok çok güzel ııı oldu", script: "", locale: tr)
        #expect(turkish.items.first { $0.kind == .repeated }?.isOn == false)
        #expect(turkish.items.first { $0.text == "ııı" }?.isOn == true)
    }

    @Test func aRestartIsOneCutWithItsFiller() {
        let offered = plan(
            "today I um today I will show you the trick",
            script: "Today I will show you the trick.",
            locale: en
        )
        let restarts = offered.items.filter { $0.kind == .restart }
        #expect(restarts.count == 1)
        #expect(restarts.first?.words == 0...2)
        #expect(restarts.first?.isOn == true)
        #expect(offered.items.filter { $0.kind == .offScript }.isEmpty)
    }

    @Test func adLibsAreOfferedButKept() {
        let offered = plan(
            "this is honestly my favourite part the point",
            script: "This is the point.",
            locale: en
        )
        let adLib = offered.items.filter { $0.kind == .offScript }
        #expect(!adLib.isEmpty)
        let allOff = adLib.allSatisfy { !$0.isOn }
        #expect(allOff)
        #expect(offered.saved(offered.defaultSelection) < 0.01)
    }

    @Test func longPausesAreOfferedAndCutsMerge() {
        let said = [
            TimedWord(text: "one", range: MediaTimeRange(start: MediaTime(seconds: 0.1), duration: MediaTime(seconds: 0.4))),
            TimedWord(text: "two", range: MediaTimeRange(start: MediaTime(seconds: 2.5), duration: MediaTime(seconds: 0.4))),
            TimedWord(text: "three", range: MediaTimeRange(start: MediaTime(seconds: 3.0), duration: MediaTime(seconds: 0.4))),
        ]
        let offered = CleanupPlanner.plan(words: said, script: "one two three", total: 5, segmentID: UUID(), locale: en)
        let pauses = offered.items.filter { $0.kind == .pause }
        // Between one and two, and the tail after three.
        #expect(pauses.count == 2)
        #expect(abs(pauses[0].start - 0.62) < 0.001)
        #expect(abs(pauses[0].end - 2.38) < 0.001)
        #expect(abs(pauses[1].end - 5) < 0.001)

        let kept = offered.kept(offered.defaultSelection)
        #expect(kept.count == 2)
        #expect(abs(kept[0].lowerBound) < 0.001)
        #expect(abs(offered.saved(offered.defaultSelection) - (1.76 + 1.48)) < 0.01)
        #expect(offered.kept([]) == [0...5])

        // A longer threshold offers fewer.
        let patient = CleanupPlanner.plan(words: said, script: "one two three", total: 5, segmentID: UUID(), locale: en, options: CleanupOptions(pause: 2.1))
        #expect(patient.items.filter { $0.kind == .pause }.count == 0)
    }

    // MARK: - Takes

    @Test func theCleanerTakeScoresHigher() {
        let script = "Today I will show you the trick that changed my videos."
        func take(_ spoken: String) -> Take {
            let said = words(spoken)
            return Take(
                recordingID: UUID(),
                sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: (said.last?.range.end.seconds ?? 0) + 0.3)),
                status: .ready,
                transcript: Transcript(localeIdentifier: "en-US", words: said)
            )
        }
        let messy = take("today um I uh today I will show you uh the the trick")
        let clean = take("today I will show you the trick that changed my videos")
        let messyScore = TakeScore.score(messy, script: script, localeIdentifier: "en-US")
        let cleanScore = TakeScore.score(clean, script: script, localeIdentifier: "en-US")
        #expect((cleanScore?.total ?? 0) > (messyScore?.total ?? 1))
        #expect(cleanScore?.hasScript == true)
        #expect((cleanScore?.total ?? 0) > 0.9)

        let segment = Segment(role: .hook, script: script, takes: [clean, messy], selectedTakeID: messy.id)
        #expect(segment.bestTake(localeIdentifier: "en-US")?.id == clean.id)
    }

    @Test func aCleanedClipStillOpensFromDisk() throws {
        var segment = Segment(role: .hook, script: "a b")
        segment.cleanup = CleanupOrigin(group: UUID(), script: "a b c", takes: [], selectedTakeID: nil)
        let data = try JSONEncoder().encode(segment)
        let decoded = try JSONDecoder().decode(Segment.self, from: data)
        #expect(decoded.cleanup == segment.cleanup)

        // And a clip saved before cleanups existed still opens.
        var old = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "cleanup")
        let legacy = try JSONDecoder().decode(Segment.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(legacy.cleanup == nil)
    }
}
