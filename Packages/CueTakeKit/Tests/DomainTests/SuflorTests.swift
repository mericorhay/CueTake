import Foundation
import Testing
@testable import Domain

struct SuflorTests {
    private func words(_ text: String, every seconds: Double = 0.5) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { index, word in
            TimedWord(text: String(word), range: MediaTimeRange(start: MediaTime(seconds: Double(index) * seconds), duration: MediaTime(seconds: seconds)))
        }
    }

    @Test func theAdStaysTogetherWhateverOrderItWasWrittenIn() {
        let plan = SuflorPlan(brief: SuflorBrief(), cues: [
            SuflorCue(role: .cta, text: "Kod KOD20"),
            SuflorCue(role: .opening, text: "Merhaba"),
            SuflorCue(role: .ad, text: "Bu krem"),
            SuflorCue(role: .topic, text: "Bugün rutin"),
            SuflorCue(role: .bridge, text: "Tam da bu yüzden"),
            SuflorCue(role: .closing, text: "Görüşürüz"),
            SuflorCue(role: .topic, text: "  "),
        ])
        #expect(plan.ordered.map(\.role) == [.opening, .topic, .bridge, .ad, .cta, .closing])
        #expect(plan.adStart == 2)
        #expect(plan.wordCount == 12)
    }

    @Test func aBriefSavedBeforeDetailsStillOpens() throws {
        var brief = SuflorBrief(brand: "Marvel", product: "Spider-Man", details: "Kolektör figürü, 30 cm")
        let data = try JSONEncoder().encode(brief)
        #expect(try JSONDecoder().decode(SuflorBrief.self, from: data) == brief)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["details"] = nil
        let old = try JSONSerialization.data(withJSONObject: object)
        brief.details = ""
        #expect(try JSONDecoder().decode(SuflorBrief.self, from: old) == brief)
    }

    @Test func theVoiceSampleTakesNewestSpeechUpToTheLimit() {
        func transcript(_ count: Int, _ word: String) -> Transcript {
            Transcript(localeIdentifier: "tr-TR", words: words(Array(repeating: word, count: count).joined(separator: " ")))
        }
        #expect(SuflorVoice.sample(from: [transcript(40, "a")]) == nil)
        let sample = SuflorVoice.sample(from: [transcript(50, "yeni"), transcript(3, "kısa"), transcript(80, "eski")], maxWords: 100)
        #expect(SuflorVoice.wordCount(sample) == 100)
        #expect(sample?.hasPrefix("yeni") == true)
        #expect(sample?.contains("kısa") == false)
        #expect(sample?.components(separatedBy: "\n\n").count == 2)
    }

    @Test func modelTextIsReadAroundTheJSON() {
        let cues = SuflorPlan.cues(fromModelText: #"İşte: {"cues":[{"role":"bridge","text":"Bu arada"},{"role":"weird","text":"x"},{"role":"ad","text":""}]} bitti"#)
        #expect(cues.map(\.role) == [.bridge, .topic])
    }

    @Test func theFlowWaitsAtTheAdUntilTheMinute() {
        var clock = SuflorClock(end: 1000, holdAt: 100, adAt: 60)
        clock.tick(9, speed: 50)
        #expect(clock.phase == .countdown)
        #expect(clock.offset == 0)
        clock.tick(1, speed: 50)
        #expect(clock.offset == 50)
        clock.tick(3, speed: 50)
        #expect(clock.offset == 100)
        #expect(clock.phase == .holding)
        #expect(clock.secondsToAd == 47)
        for _ in 0..<46 { clock.tick(1, speed: 50) }
        #expect(clock.offset == 100)
        clock.tick(1, speed: 50)
        #expect(clock.released)
        #expect(clock.offset == 150)
        #expect(clock.phase == .rolling)
    }

    @Test func aManualHoldWaitsForTheSpeaker() {
        var clock = SuflorClock(end: 400, holdAt: 100)
        for _ in 0..<60 { clock.tick(1, speed: 40) }
        #expect(clock.phase == .holding)
        #expect(clock.secondsToAd == nil)
        clock.jump(to: 100)
        #expect(clock.released)
        clock.tick(1, speed: 40)
        #expect(clock.offset == 140)
        for _ in 0..<60 { clock.tick(1, speed: 40) }
        #expect(clock.phase == .finished)
    }

    @Test func nothingMovesUntilTheFirstPlay() {
        var clock = SuflorClock(end: 500, holdAt: 100, adAt: 60, started: false)
        #expect(clock.phase == .ready)
        #expect(!clock.isPlaying)
        clock.tick(120, speed: 50)
        #expect(clock.elapsed == 0)
        #expect(clock.offset == 0)
        clock.setPlaying(true)
        #expect(clock.phase == .countdown)
        clock.tick(9, speed: 10)
        #expect(clock.offset == 0)
        clock.tick(2, speed: 10)
        #expect(clock.offset == 20)
        #expect(clock.secondsToAd == 49)
    }

    @Test func pausingAndDraggingMoveOnlyByHand() {
        var clock = SuflorClock(end: 500)
        clock.isPlaying = false
        clock.tick(8, speed: 10)
        #expect(clock.offset == 0)
        clock.move(by: 80)
        clock.move(by: -30)
        #expect(clock.offset == 50)
        clock.move(by: -300)
        #expect(clock.offset == 0)
    }

    @Test func proofFindsSpokenCodesHoweverTheyAreSpaced() {
        let heard = words("evet arkadaşlar kodum kod 20 ile yüzde yirmi indirim var linki de bio da cuetake.app")
        let proofs = SuflorProof.find(["KOD20", "cuetake.app", "Glow Serum"], in: heard, localeIdentifier: "tr-TR")
        #expect(proofs.map(\.item) == ["KOD20", "cuetake.app"])
        #expect(proofs[0].seconds == 1.5)
        #expect(proofs[0].quote.contains("kod 20"))
    }

    @Test func turkishLettersFoldTheSameOnBothSides() {
        let heard = words("bugün İNCİ şampuanı denedik")
        #expect(SuflorProof.find(["inci şampuan"], in: heard, localeIdentifier: "tr-TR").count == 1)
    }

    @Test func evidencePrefersWhatWasHeard() {
        var session = SuflorSession(plan: SuflorPlan(brief: SuflorBrief(mustSay: ["KOD20", "link"]), cues: []))
        session.ticked["KOD20"] = 40
        session.ticked["link"] = 50
        session.proofs = [SuflorProof(item: "KOD20", seconds: 42, quote: "kod 20")]
        #expect(session.evidence(for: "KOD20") == .heard(session.proofs[0]))
        #expect(session.evidence(for: "link") == .ticked(50))
        #expect(session.evidence(for: "other") == .missing)
        #expect(session.reportID.count == 12)
        #expect(SuflorSession.clock(3723) == "1:02:03")
        #expect(SuflorSession.clock(83) == "1:23")
    }
}
