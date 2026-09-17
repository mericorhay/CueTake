import Foundation
import Testing
@testable import Domain

struct HighlightFinderTests {
    private let locale = Locale(identifier: "en-US")

    /// Words at a steady 2.5 a second, with a pause after each sentence.
    private func words(_ sentences: [String]) -> [PlacedWord] {
        var result: [PlacedWord] = []
        var time = 0.0
        for sentence in sentences {
            for word in sentence.split(separator: " ") {
                result.append(PlacedWord(text: String(word), range: MediaTimeRange(start: MediaTime(seconds: time), duration: MediaTime(seconds: 0.35))))
                time += 0.4
            }
            time += 1
        }
        return result
    }

    private func talk(_ count: Int) -> [String] {
        (0..<count).map { index in
            index % 5 == 0
                ? "Why do \(index + 3) people lose money every single day?"
                : "this part keeps going with ordinary words that explain something slowly and carefully."
        }
    }

    @Test func sentencesSplitOnPunctuationAndPauses() {
        let spoken = words(["Hello there.", "no stop here", "Is it?"])
        let sentences = HighlightFinder.sentences(from: spoken)
        #expect(sentences.map(\.text) == ["Hello there.", "no stop here", "Is it?"])
        #expect(sentences.map(\.id) == [0, 1, 2])
        #expect(sentences[1].wordCount == 3)
        #expect(sentences[0].start == 0)
    }

    @Test func candidatesFitTheLengthDoNotOverlapAndStartOnHooks() {
        let sentences = HighlightFinder.sentences(from: words(talk(40)))
        let found = HighlightFinder.candidates(in: sentences, length: .medium, count: 4, locale: locale)
        #expect(!found.isEmpty)
        #expect(found.count <= 4)
        for candidate in found {
            #expect(candidate.duration >= HighlightLength.medium.minimum)
            #expect(candidate.duration <= HighlightLength.medium.maximum)
        }
        for (i, a) in found.enumerated() {
            for b in found.dropFirst(i + 1) {
                #expect(!a.overlaps(b))
            }
        }
        // Best first, and the best opens with the question.
        #expect(found == found.sorted { $0.scores.total >= $1.scores.total })
        #expect(found[0].title.hasPrefix("Why do"))
        #expect(found[0].scores.hook > 0.8)
    }

    @Test func aShortVideoIsOneCandidate() {
        let sentences = HighlightFinder.sentences(from: words(["Here is a quick tip that saves you time.", "Use it today and thank me later!"]))
        let found = HighlightFinder.candidates(in: sentences, length: .medium, locale: locale)
        #expect(found.count == 1)
        #expect(found[0].firstSentence == 0)
        #expect(found[0].lastSentence == 1)
    }

    @Test func modelPicksComeFirstAndBadOnesAreDropped() {
        let sentences = HighlightFinder.sentences(from: words(talk(40)))
        let local = HighlightFinder.candidates(in: sentences, length: .medium, count: 6, locale: locale)
        let picks = [
            HighlightPick(from: 10, to: 13, title: "The money question", reason: "Opens with a number."),
            HighlightPick(from: 500, to: 510),       // not there
            HighlightPick(from: 20, to: 20),         // far too short
            HighlightPick(from: 11, to: 12),         // overlaps the first
        ]
        let merged = HighlightFinder.merge(picks: picks, local: local, sentences: sentences, length: .medium, count: 6, locale: locale)
        #expect(merged.first?.title == "The money question")
        #expect(merged.first?.pickedByAI == true)
        #expect(merged.filter(\.pickedByAI).count == 1)
        #expect(merged.count <= 6)
        for (i, a) in merged.enumerated() {
            for b in merged.dropFirst(i + 1) {
                #expect(!a.overlaps(b))
            }
        }
    }

    @Test func aStretchBecomesAVerticalProjectWithItsWords() throws {
        var recording = Recording(relativePath: "long.mov", format: VideoFormat(aspectRatio: .landscape16x9, resolution: .uhd4K), camera: .back, duration: MediaTime(seconds: 30))
        recording.reframe = [VideoFocusKeyframe(time: 12, x: 0.4, y: 0.5)]
        let spoken = Transcript(localeIdentifier: "en-US", words: (0..<20).map { index in
            TimedWord(text: "w\(index)", range: MediaTimeRange(start: MediaTime(seconds: Double(index)), duration: MediaTime(seconds: 0.5)), confidence: 1)
        })
        func segment(_ start: Double) -> Segment {
            var take = Take(recordingID: recording.id, sourceRange: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: 10)), status: .ready)
            take.transcript = spoken.slice(from: 0, to: 10)
            return Segment(role: .hook, script: "", takes: [take], selectedTakeID: take.id)
        }
        let unused = Recording(relativePath: "other.mov", format: .vertical1080, camera: .back, duration: MediaTime(seconds: 5))
        var project = Project(title: "Long", localeIdentifier: "en-US", segments: [segment(0), segment(10)], recordings: [recording, unused])
        project.setTransition(after: project.segments[0].id, kind: .crossfade)
        project.audio = []

        let clip = project.extractingClip(from: 6, to: 14, title: "Best bit")
        #expect(clip.id != project.id)
        #expect(clip.title == "Best bit")
        #expect(clip.format.aspectRatio == .portrait9x16)
        #expect(clip.format.resolution == .uhd4K)
        #expect(clip.segments.count == 2)
        let first = try #require(clip.segments[0].selectedTake)
        let second = try #require(clip.segments[1].selectedTake)
        #expect(abs(first.sourceRange.start.seconds - 6) < 0.001)
        #expect(abs(first.sourceRange.duration.seconds - 4) < 0.001)
        #expect(abs(second.sourceRange.start.seconds - 10) < 0.001)
        #expect(abs(second.sourceRange.duration.seconds - 4) < 0.001)
        #expect(first.transcript?.words.first?.text == "w6")
        #expect(first.transcript?.words.first?.range.start.seconds == 0)
        #expect(!clip.segments[0].captions.isEmpty)
        #expect(clip.recordings.map(\.id) == [recording.id])
        #expect(clip.recordings.first?.reframe?.count == 1)
        // The cut between the two kept clips keeps its transition, under the new clip's id.
        #expect(clip.transitions.count == 1)
        #expect(clip.transitions.first?.after == clip.segments[0].id)
        #expect(clip.needsVerticalReframe)
        #expect(abs(clip.segments.reduce(0) { $0 + $1.barWeight } - 8) < 0.01)
    }

    @Test func projectWordsArePlacedOnTheFinishedVideo() {
        let recording = Recording(relativePath: "a.mov", format: .vertical1080, camera: .back, duration: MediaTime(seconds: 20))
        func segment(_ words: [String]) -> Segment {
            var take = Take(recordingID: recording.id, sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 4)), status: .ready)
            take.transcript = Transcript(localeIdentifier: "en-US", words: words.enumerated().map { index, text in
                TimedWord(text: text, range: MediaTimeRange(start: MediaTime(seconds: Double(index)), duration: MediaTime(seconds: 0.5)), confidence: 1)
            })
            return Segment(role: .hook, script: "", takes: [take], selectedTakeID: take.id)
        }
        let project = Project(title: "t", localeIdentifier: "en-US", segments: [segment(["One", "two."]), segment(["Three", "four."])], recordings: [recording])
        let placed = project.spokenWords
        #expect(placed.map(\.text) == ["One", "two.", "Three", "four."])
        #expect(placed[2].range.start.seconds == 4)
        #expect(project.spokenSentences.map(\.text) == ["One two.", "Three four."])
    }
}
