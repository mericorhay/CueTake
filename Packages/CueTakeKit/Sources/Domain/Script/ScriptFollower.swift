import Foundation

/// Keeps a place in the script from the words someone is actually saying.
///
/// The prompter's whole promise is that it waits for you. A timer cannot keep it: people speed up,
/// stop to breathe, repeat a phrase, skip a sentence. So the position comes from the last few words
/// heard, matched against the script just ahead of where the reader was — never far behind, because
/// a recogniser revising its guess must not throw the text backwards mid-sentence, and never a long
/// jump on the strength of one common word, because "the" appears everywhere.
///
/// Pure, so the same follower runs live against the microphone and afterwards against the file's
/// transcript to find where each segment really began.
public struct ScriptFollower: Sendable {
    public struct Position: Hashable, Sendable {
        public var segment: Int
        public var word: Int

        public init(segment: Int, word: Int) {
            self.segment = segment
            self.word = word
        }
    }

    private struct Entry: Sendable {
        let segment: Int
        let word: Int
        let key: String
    }

    private let entries: [Entry]
    private let locale: Locale
    /// Index into `entries` of the last word matched, or -1 before the first.
    public private(set) var cursor = -1
    /// What was heard last time. A recogniser re-sends the same guess many times while it firms
    /// up, and matching it again would walk the place forward onto the next copy of the same word.
    private var lastHeard: [String] = []

    /// How far ahead a match may land. Enough to skip a sentence, not enough to lose the page.
    public var lookAhead = 24
    /// How many of the most recent heard words are compared.
    public var tail = 4

    public init(scripts: [String], locale: Locale) {
        self.locale = locale
        entries = scripts.enumerated().flatMap { segment, script in
            ScriptText.words(in: script).enumerated().map { word, text in
                Entry(segment: segment, word: word, key: ScriptText.matchKey(for: text, locale: locale))
            }
        }
    }

    public var position: Position? {
        entries.indices.contains(cursor) ? Position(segment: entries[cursor].segment, word: entries[cursor].word) : nil
    }

    public var isAtEnd: Bool {
        !entries.isEmpty && cursor >= entries.count - 1
    }

    public var wordCount: Int { entries.count }

    /// Moves the place by hand, when the reader taps or scrolls the prompter.
    public mutating func jump(to position: Position) {
        if let index = entries.firstIndex(where: { $0.segment == position.segment && $0.word == position.word }) {
            cursor = index - 1
            lastHeard = []
        }
    }

    /// Puts the place exactly on a word, as though it had just been heard.
    public mutating func place(at position: Position) {
        if let index = entries.firstIndex(where: { $0.segment == position.segment && $0.word == position.word }) {
            cursor = index
            lastHeard = []
        }
    }

    /// Steps the place back, so a match can land a little behind it. Used when the prompter ran
    /// ahead on its own before the voice was heard: the reader is somewhere behind the text.
    public mutating func rewind(words: Int) {
        cursor = max(-1, cursor - words)
        lastHeard = []
    }

    /// Feeds the words heard most recently, oldest first. Returns the new place when it moved.
    @discardableResult
    public mutating func hear(_ words: [String]) -> Position? {
        let heard = words
            .map { ScriptText.matchKey(for: $0, locale: locale) }
            .filter { !$0.isEmpty }
            .suffix(tail)
        guard !heard.isEmpty, !entries.isEmpty else { return nil }
        let recent = Array(heard)
        guard recent != lastHeard else { return nil }
        lastHeard = recent

        let first = max(0, cursor + 1)
        let last = min(entries.count - 1, cursor + lookAhead)
        guard first <= last else { return nil }

        var best: (index: Int, score: Double)?
        for candidate in first...last {
            // Only an end that matches the newest word counts: the place is where they are now,
            // not where they were three words ago.
            guard Self.matches(recent[recent.count - 1], entries[candidate].key) else { continue }

            var score = 1.0
            var scriptIndex = candidate - 1
            var heardIndex = recent.count - 2
            while heardIndex >= 0, scriptIndex >= 0, scriptIndex > candidate - tail - 2 {
                if Self.matches(recent[heardIndex], entries[scriptIndex].key) {
                    score += 1
                    heardIndex -= 1
                    scriptIndex -= 1
                } else if heardIndex > 0, Self.matches(recent[heardIndex - 1], entries[scriptIndex].key) {
                    // An extra word was said — "um", a repeat — skip it in what was heard.
                    heardIndex -= 1
                } else {
                    // A word was skipped in the script.
                    scriptIndex -= 1
                }
            }

            let distance = candidate - first
            // A single word is trusted only right next to the reader; further away it takes more
            // agreement, and a longer word is worth more than a short common one.
            let required: Double = distance <= 2 ? 1 : (distance <= 8 ? 2 : 3)
            let weight = entries[candidate].key.count >= 5 ? 0.5 : 0
            guard score + weight >= required else { continue }

            let ranked = score - Double(distance) * 0.05
            if best == nil || ranked > best!.score {
                best = (candidate, ranked)
            }
        }

        guard let best, best.index != cursor else { return nil }
        cursor = best.index
        return position
    }

    /// Equal, or near enough that a recogniser's spelling does not lose the place: one letter off
    /// in a longer word, or the same stem ("record" / "recording").
    static func matches(_ heard: String, _ script: String) -> Bool {
        if heard == script { return true }
        guard heard.count >= 4, script.count >= 4 else { return false }
        if heard.hasPrefix(script) || script.hasPrefix(heard) {
            return min(heard.count, script.count) >= 4
        }
        return abs(heard.count - script.count) <= 1 && editDistance(heard, script, limit: 1) <= 1
    }

    private static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            var rowMin = current[0]
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                rowMin = min(rowMin, current[j])
            }
            if rowMin > limit { return limit + 1 }
            previous = current
        }
        return previous[b.count]
    }
}

/// Where each segment of a script really begins inside a recording, from its transcript.
public enum ScriptAligner {
    /// Start times, one per script, in the recording's seconds. Nil for a segment the speaker never
    /// reached — or that could not be recognised — so the caller can fall back to what it knew live.
    public static func segmentStarts(scripts: [String], words: [TimedWord], locale: Locale) -> [Double?] {
        var follower = ScriptFollower(scripts: scripts, locale: locale)
        var starts: [Double?] = Array(repeating: nil, count: scripts.count)
        var heard: [String] = []
        var currentSegment = -1

        for word in words {
            heard.append(word.text)
            if heard.count > 6 { heard.removeFirst() }
            guard let position = follower.hear(heard), position.segment != currentSegment else { continue }

            if position.segment > currentSegment {
                // The time of the word that was matched, walked back to the first word of the
                // segment when a few of its opening words were missed.
                let lead = Double(min(position.word, 3)) * 0.35
                let start = max(0, word.range.start.seconds - lead)
                for skipped in max(0, currentSegment + 1)...position.segment where starts[skipped] == nil {
                    starts[skipped] = start
                }
                currentSegment = position.segment
            }
        }
        return starts
    }
}
