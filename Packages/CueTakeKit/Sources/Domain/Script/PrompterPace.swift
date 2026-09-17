import Foundation

/// How fast the reader is going, from where the prompter found them over the last few seconds.
///
/// Measured from the place in the script rather than from the recogniser's word count: a
/// recogniser re-sends and revises, and the place only moves when a word really was read.
public struct PaceMeter: Sendable {
    public enum Verdict: Sendable, Equatable {
        case slow
        case good
        case fast
    }

    /// Seconds of reading the measure looks back over.
    public var window: Double
    private var samples: [(time: Double, word: Int)] = []

    public init(window: Double = 12) {
        self.window = window
    }

    /// `word` counts across the whole script, so moving to the next segment keeps counting.
    public mutating func record(word: Int, at time: Double) {
        if let last = samples.last, word < last.word {
            // Moved back by hand or re-found further back: what came before no longer describes
            // this reading.
            samples.removeAll()
        }
        samples.append((time, word))
        let window = self.window
        samples.removeAll { time - $0.time > window }
    }

    public mutating func reset() {
        samples.removeAll()
    }

    /// Nil until there is enough reading to say: three seconds and four words.
    public var wordsPerMinute: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let seconds = last.time - first.time
        let words = last.word - first.word
        guard seconds >= 3, words >= 4 else { return nil }
        return Double(words) / seconds * 60
    }

    public static func verdict(_ wordsPerMinute: Double, target: Double) -> Verdict {
        if wordsPerMinute > target * 1.25 { return .fast }
        if wordsPerMinute < target * 0.7 { return .slow }
        return .good
    }
}

public enum ScriptTiming {
    /// Seconds of reading left from a place, at a pace.
    public static func remainingSeconds(scripts: [String], segment: Int, word: Int, wordsPerMinute: Double) -> Double {
        guard wordsPerMinute > 0 else { return 0 }
        var words = 0
        for (index, script) in scripts.enumerated() where index >= segment {
            let count = ScriptText.words(in: script).count
            words += index == segment ? max(0, count - word - 1) : count
        }
        return Double(words) / wordsPerMinute * 60
    }

    /// The place counted across every script, for pace and progress.
    public static func globalWord(scripts: [String], segment: Int, word: Int) -> Int {
        scripts.prefix(max(0, segment)).reduce(0) { $0 + ScriptText.words(in: $1).count } + word
    }

    public static func wordCount(_ scripts: [String]) -> Int {
        scripts.reduce(0) { $0 + ScriptText.words(in: $1).count }
    }

    /// "0:42"
    public static func label(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

extension ScriptText {
    /// A word written as `*word*` is to be stressed. The stars are for the writer, not the reader.
    public static func emphasis(_ word: some StringProtocol) -> (text: String, isEmphasized: Bool) {
        guard word.contains("*") else { return (String(word), false) }
        let text = word.replacingOccurrences(of: "*", with: "")
        return (text.isEmpty ? String(word) : text, !text.isEmpty)
    }

    /// Whether a word closes a sentence.
    public static func endsSentence(_ word: some StringProtocol) -> Bool {
        let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)»*"))
        guard let last = trimmed.last else { return false }
        return ".!?…".contains(last)
    }

    /// The words of the sentence around `index`.
    public static func sentence(around index: Int, in words: [String]) -> ClosedRange<Int>? {
        guard words.indices.contains(index) else { return nil }
        var lower = index
        while lower > 0, !endsSentence(words[lower - 1]) { lower -= 1 }
        var upper = index
        while upper < words.count - 1, !endsSentence(words[upper]) { upper += 1 }
        return lower...upper
    }
}

extension Take {
    /// The take cut down to its speech, with a little air either side.
    ///
    /// A retake is everything from the shutter to the stop button: the reach back to the phone,
    /// the breath before the line and the reach again afterwards. Once its words are known, that
    /// is trimmed away. Nil when there are no words or nothing to trim.
    public func trimmedToSpeech(lead: Double = 0.25, tail: Double = 0.4) -> Take? {
        guard let words = transcript?.words, let first = words.first, let last = words.last else { return nil }
        let total = sourceRange.duration.seconds
        let start = max(0, first.range.start.seconds - lead)
        let end = min(total, last.range.end.seconds + tail)
        guard end - start > 0.3, start > 0.05 || total - end > 0.05 else { return nil }

        var trimmed = self
        trimmed.sourceRange = MediaTimeRange(
            start: sourceRange.start + MediaTime(seconds: start),
            duration: MediaTime(seconds: end - start)
        )
        trimmed.transcript?.words = words.map { word in
            var moved = word
            moved.range = MediaTimeRange(
                start: MediaTime(seconds: word.range.start.seconds - start),
                duration: word.range.duration
            )
            return moved
        }
        return trimmed
    }
}
