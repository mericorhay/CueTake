import Foundation
import Testing
@testable import Domain

/// The prompter's place in the script. A follower that jumps on a common word loses the reader
/// mid-sentence; one that never skips strands them when they drop a line. Both are tested.
struct ScriptFollowerTests {
    private let english = Locale(identifier: "en")
    private let scripts = [
        "Stop scrolling. This changed how I film forever.",
        "Hi, I am Deniz and I make videos alone with one phone.",
        "Follow for part two.",
    ]

    private func feed(_ follower: inout ScriptFollower, _ sentence: String) -> ScriptFollower.Position? {
        var heard: [String] = []
        var last: ScriptFollower.Position?
        for word in sentence.split(separator: " ") {
            heard.append(String(word))
            if let moved = follower.hear(heard) { last = moved }
        }
        return last
    }

    @Test func followsWordByWord() {
        var follower = ScriptFollower(scripts: scripts, locale: english)
        let position = feed(&follower, "stop scrolling this changed")
        #expect(position == .init(segment: 0, word: 3))
    }

    @Test func aCommonWordFarAheadDoesNotMoveIt() {
        var follower = ScriptFollower(scripts: scripts, locale: english)
        _ = feed(&follower, "stop scrolling")
        // "and" is in the next segment, well ahead — one short word is not evidence.
        #expect(follower.hear(["and"]) == nil)
        #expect(follower.position == .init(segment: 0, word: 1))
    }

    @Test func skippingASentenceIsFollowed() {
        var follower = ScriptFollower(scripts: scripts, locale: english)
        _ = feed(&follower, "stop scrolling")
        let position = feed(&follower, "i make videos alone")
        #expect(position?.segment == 1)
        #expect(position?.word == 8)
    }

    @Test func fillerAndRecogniserSpellingAreTolerated() {
        var follower = ScriptFollower(scripts: scripts, locale: english)
        _ = feed(&follower, "stop scrolling this um changed how i filmed")
        #expect(follower.position == .init(segment: 0, word: 6))
    }

    @Test func neverMovesBackwards() {
        var follower = ScriptFollower(scripts: scripts, locale: english)
        _ = feed(&follower, "stop scrolling this changed how i film forever")
        #expect(follower.hear(["stop", "scrolling"]) == nil)
        #expect(follower.position?.word == 7)
    }

    @Test func turkishCaseIsFolded() {
        var follower = ScriptFollower(scripts: ["İstanbul'da çekim yapıyorum"], locale: Locale(identifier: "tr"))
        let position = feed(&follower, "istanbul'da çekim")
        #expect(position == .init(segment: 0, word: 1))
    }

    @Test func alignerFindsWhereEachSegmentBegan() {
        let spoken = "stop scrolling this changed how i film forever hi i am deniz and i make videos alone with one phone follow for part two"
        let words = spoken.split(separator: " ").enumerated().map { index, text in
            TimedWord(
                text: String(text),
                range: MediaTimeRange(start: MediaTime(seconds: Double(index) * 0.4), duration: MediaTime(seconds: 0.3))
            )
        }
        let starts = ScriptAligner.segmentStarts(scripts: scripts, words: words, locale: english)
        #expect(starts.count == 3)
        #expect(abs((starts[0] ?? -1) - 0) < 0.45)
        // "hi" is the ninth word: 8 × 0.4 = 3.2 s.
        #expect(abs((starts[1] ?? -1) - 3.2) < 0.45)
        // "follow" is the twenty-first: 20 × 0.4 = 8 s.
        #expect(abs((starts[2] ?? -1) - 8.0) < 0.45)
    }
}
