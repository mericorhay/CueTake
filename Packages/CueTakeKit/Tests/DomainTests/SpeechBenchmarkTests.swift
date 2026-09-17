import Foundation
import Testing
@testable import Domain

struct SpeechBenchmarkTests {
    private func words(_ rows: [(String, Double)]) -> [TimedWord] {
        rows.map { TimedWord(text: $0.0, range: MediaTimeRange(start: MediaTime(seconds: $0.1), duration: MediaTime(seconds: 0.3))) }
    }

    @Test func scoresCountErrorsDriftAndFillers() {
        let reference = words([("so", 0), ("um", 0.5), ("this", 1), ("is", 1.5), ("it", 2)])
        let perfect = SpeechBenchmark.score(heard: reference, reference: reference, localeIdentifier: "en")
        #expect(perfect.wordErrorRate == 0)
        #expect(perfect.startError == 0)
        #expect(perfect.fillerRecall == 1)

        let heard = words([("so", 0.1), ("this", 1.1), ("was", 1.5), ("it", 2.1)])
        let score = SpeechBenchmark.score(heard: heard, reference: reference, localeIdentifier: "en")
        // "um" missing, "is" heard as "was": two errors in five words.
        #expect(abs(score.wordErrorRate - 0.4) < 0.0001)
        #expect(abs(score.startError - 0.1) < 0.0001)
        #expect(score.fillerRecall == 0)
        #expect(score.referenceWords == 5)
    }

    @Test func fixturesRoundTrip() throws {
        let fixture = SpeechBenchmark.Fixture(
            name: "t",
            localeIdentifier: "tr-TR",
            reference: words([("merhaba", 0.12345)]),
            heard: ["device": words([("merhaba", 0.2)])]
        )
        let data = try JSONEncoder().encode(fixture)
        let back = try JSONDecoder().decode(SpeechBenchmark.Fixture.self, from: data)
        #expect(back.referenceWords.first?.text == "merhaba")
        #expect(abs((back.referenceWords.first?.range.start.seconds ?? 0) - 0.123) < 0.002)
        #expect(back.words(of: "device").count == 1)
        #expect(back.words(of: "cloud").isEmpty)
    }

    /// Scores every recording in Tests/SpeechBenchmarks and prints the table. Numbers, not a gate:
    /// the point is to see what a change to the engine did.
    @Test func benchmarkReport() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "SpeechBenchmarks", directoryHint: .isDirectory)
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var lines = ["speech benchmark: \(files.count) recordings"]
        for file in files {
            let fixture = try JSONDecoder().decode(SpeechBenchmark.Fixture.self, from: Data(contentsOf: file))
            #expect(!fixture.referenceWords.isEmpty, "\(file.lastPathComponent) has no reference words")
            for listener in fixture.heard.keys.sorted() {
                let score = SpeechBenchmark.score(
                    heard: fixture.words(of: listener),
                    reference: fixture.referenceWords,
                    localeIdentifier: fixture.localeIdentifier
                )
                let recall = score.fillerRecall.map { String(format: "%.0f%%", $0 * 100) } ?? "-"
                lines.append(String(
                    format: "%@ · %@ · WER %.1f%% · start ±%.0f ms · fillers %@",
                    fixture.name, listener, score.wordErrorRate * 100, score.startError * 1000, recall
                ))
                #expect(score.wordErrorRate.isFinite)
            }
        }
        print(lines.joined(separator: "\n"))
    }

    // MARK: - Hints

    @Test func hintsAreTheWordsARecogniserWouldMiss() {
        let terms = SpeechHints.terms(
            scripts: ["Today I test the new iPhone 17 with CueTake. It costs *nothing* at all, honestly."],
            brand: BrandVoice(name: "Kahve Lab", mustSay: "Bir fincan yeter, iyi günler"),
            localeIdentifier: "en"
        )
        #expect(Array(terms.prefix(3)) == ["Kahve Lab", "Bir fincan yeter", "iyi günler"])
        #expect(terms.contains("iPhone"))
        #expect(terms.contains("17"))
        #expect(terms.contains("CueTake"))
        #expect(terms.contains("nothing"))
        // A capital that only starts a sentence is not a name.
        #expect(!terms.contains("Today"))
        #expect(!terms.contains("It"))
        #expect(!terms.contains("honestly"))
    }

    @Test func whisperIsPrimedToKeepFillers() {
        let tr = SpeechHints.whisperPrompt(script: String(repeating: "kelime ", count: 200), terms: ["Kahve Lab"], localeIdentifier: "tr-TR")
        #expect(tr.count <= 400)
        #expect(tr.hasPrefix("Kahve Lab."))
        #expect(tr.hasSuffix("Iıı, şey… yani, hmm, ee, bu önemli."))
        let en = SpeechHints.whisperPrompt(script: "", terms: [], localeIdentifier: "en")
        #expect(en == "Umm, so, uh… like, I mean, hmm.")
    }

    @Test func numbersSaidAsWordsBecomeDigits() {
        let tr = Locale(identifier: "tr-TR")
        let en = Locale(identifier: "en-US")
        #expect(SpokenNumbers.collapse(["iki", "bin", "yirmi", "altı", "yılında"], locale: tr) == ["2026", "yılında"])
        #expect(SpokenNumbers.collapse(["yüzde", "elli", "indirim"], locale: tr) == ["50", "indirim"])
        #expect(SpokenNumbers.collapse(["bir", "şey"], locale: tr) == ["bir", "şey"])
        #expect(SpokenNumbers.collapse(["beş", "yüz", "elli"], locale: tr) == ["550"])
        #expect(SpokenNumbers.collapse(["one", "hundred", "and", "five", "people"], locale: en) == ["105", "people"])
        #expect(SpokenNumbers.collapse(["fifty", "percent", "off"], locale: en) == ["50", "off"])
        #expect(SpokenNumbers.collapse(["rock", "and", "roll"], locale: en) == ["rock", "and", "roll"])
    }

    @Test func theFollowerReadsNumbersAndBentLetters() {
        var follower = ScriptFollower(scripts: ["Bu yıl 2026 kameranın en iyi yılı"], locale: Locale(identifier: "tr-TR"))
        let number = follower.hear(["bu", "yıl", "iki", "bin", "yirmi", "altı"])
        let bent = follower.hear(["iki", "bin", "yirmi", "altı", "kameranin"])
        #expect(number?.word == 2)
        #expect(bent?.word == 3)
    }

    @Test func wordlessSoundsBecomeFillers() {
        let said = [
            TimedWord(text: "this", range: MediaTimeRange(start: MediaTime(seconds: 0.2), duration: MediaTime(seconds: 0.4))),
            TimedWord(text: "works", range: MediaTimeRange(start: MediaTime(seconds: 2.0), duration: MediaTime(seconds: 0.4))),
        ]
        let plan = CleanupPlanner.plan(
            words: said,
            script: "",
            total: 3,
            segmentID: UUID(),
            locale: Locale(identifier: "en"),
            sounds: [1.0...1.4, 0.3...0.5, 1.5...2.6]
        )
        let sounds = plan.items.filter { $0.kind == .filler && $0.words == nil }
        // Only the one between the words counts: the others lie over words that were heard.
        #expect(sounds.count == 1)
        #expect(abs((sounds.first?.start ?? 0) - 0.96) < 0.001)
        #expect(sounds.first?.isOn == true)
    }
}
