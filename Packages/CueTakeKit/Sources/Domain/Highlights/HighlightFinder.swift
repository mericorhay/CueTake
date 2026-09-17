import Foundation

/// A sentence as it is heard in the finished video.
public struct SpokenSentence: Identifiable, Hashable, Sendable, Codable {
    public var id: Int
    public var text: String
    public var start: Double
    public var end: Double
    public var wordCount: Int

    public init(id: Int, text: String, start: Double, end: Double, wordCount: Int) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.wordCount = wordCount
    }
}

/// A stretch of a long video that could stand as a short on its own, and why.
public struct HighlightCandidate: Identifiable, Hashable, Sendable {
    /// 0…1 each, so the reasons can be drawn as bars rather than a single mystery number.
    public struct Scores: Hashable, Sendable {
        /// How strongly the first sentence pulls a viewer in.
        public var hook: Double
        /// Whether it ends on a finished thought.
        public var complete: Double
        /// Speaking pace: neither dragging nor rushed.
        public var pace: Double
        /// Numbers, money and strong words.
        public var keywords: Double
        /// How close it is to the wanted length.
        public var fit: Double

        public var total: Double {
            0.35 * hook + 0.2 * complete + 0.15 * pace + 0.15 * keywords + 0.15 * fit
        }
    }

    public var id: String { "\(firstSentence)-\(lastSentence)" }
    public var firstSentence: Int
    public var lastSentence: Int
    public var start: Double
    public var end: Double
    public var title: String
    /// The model's reason, when a model chose it.
    public var reason: String?
    public var scores: Scores
    public var pickedByAI: Bool

    public var duration: Double { end - start }
    public var score: Int { Int((scores.total * 100).rounded()) }

    public init(firstSentence: Int, lastSentence: Int, start: Double, end: Double, title: String, reason: String? = nil, scores: Scores, pickedByAI: Bool = false) {
        self.firstSentence = firstSentence
        self.lastSentence = lastSentence
        self.start = start
        self.end = end
        self.title = title
        self.reason = reason
        self.scores = scores
        self.pickedByAI = pickedByAI
    }

    public func overlaps(_ other: HighlightCandidate) -> Bool {
        start < other.end - 0.5 && other.start < end - 0.5
    }
}

/// What a model returned: a run of sentences, a title and a reason.
public struct HighlightPick: Hashable, Sendable, Codable {
    public var from: Int
    public var to: Int
    public var title: String?
    public var reason: String?

    public init(from: Int, to: Int, title: String? = nil, reason: String? = nil) {
        self.from = from
        self.to = to
        self.title = title
        self.reason = reason
    }
}

/// How long the shorts should be.
public struct HighlightLength: Hashable, Sendable {
    public var minimum: Double
    public var maximum: Double

    public init(minimum: Double, maximum: Double) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public var target: Double { (minimum + maximum) / 2 }

    public static let short = HighlightLength(minimum: 12, maximum: 30)
    public static let medium = HighlightLength(minimum: 25, maximum: 60)
    public static let long = HighlightLength(minimum: 50, maximum: 90)
    public static let all = [short, medium, long]
}

/// Finds the stretches of a long talk worth cutting out as shorts, on the device.
///
/// Sentences are scored for a hook, a finished ending, pace and strong words, and the best
/// non-overlapping runs of whole sentences within the wanted length are offered. A model, when
/// allowed, picks runs of the same sentences; they are scored the same way, so its choices show
/// the same bars.
public enum HighlightFinder {
    static let secondPerson: Set<String> = ["you", "your", "you're", "sen", "siz", "senin", "sizin", "sana", "size"]

    /// Sentences from words already placed on the finished video.
    public static func sentences(from words: [PlacedWord]) -> [SpokenSentence] {
        var result: [SpokenSentence] = []
        var current: [PlacedWord] = []
        func close() {
            guard let first = current.first, let last = current.last else { return }
            result.append(SpokenSentence(
                id: result.count,
                text: current.map(\.text).joined(separator: " "),
                start: first.range.start.seconds,
                end: last.range.end.seconds,
                wordCount: current.count
            ))
            current = []
        }
        for (index, word) in words.enumerated() {
            current.append(word)
            let ends = word.text.last.map { ".!?…".contains($0) } ?? false
            let next = index + 1 < words.count ? words[index + 1] : nil
            let pause = next.map { $0.range.start.seconds - word.range.end.seconds > 0.7 } ?? true
            if ends || pause || current.count >= 30 { close() }
        }
        close()
        return result
    }

    /// The best runs of sentences, best first.
    public static func candidates(
        in sentences: [SpokenSentence],
        length: HighlightLength = .medium,
        count: Int = 6,
        locale: Locale
    ) -> [HighlightCandidate] {
        guard !sentences.isEmpty else { return [] }
        var best: [HighlightCandidate] = []
        for first in sentences.indices {
            var top: HighlightCandidate?
            for last in first..<sentences.count {
                let duration = sentences[last].end - sentences[first].start
                if duration > length.maximum { break }
                guard duration >= length.minimum else { continue }
                let candidate = candidate(from: first, to: last, in: sentences, length: length, locale: locale)
                if candidate.scores.total > (top?.scores.total ?? -1) { top = candidate }
            }
            if let top { best.append(top) }
        }
        // Too short for the wanted length: the whole thing is the one candidate.
        if best.isEmpty, let last = sentences.indices.last, sentences[last].end - sentences[0].start >= 5 {
            best = [candidate(from: 0, to: last, in: sentences, length: length, locale: locale)]
        }
        var chosen: [HighlightCandidate] = []
        for candidate in best.sorted(by: { $0.scores.total > $1.scores.total }) {
            guard !chosen.contains(where: { $0.overlaps(candidate) }) else { continue }
            chosen.append(candidate)
            if chosen.count == count { break }
        }
        return chosen
    }

    /// One run of sentences, scored.
    public static func candidate(
        from first: Int,
        to last: Int,
        in sentences: [SpokenSentence],
        length: HighlightLength,
        locale: Locale,
        title: String? = nil,
        reason: String? = nil
    ) -> HighlightCandidate {
        let run = Array(sentences[first...last])
        let opening = run[0]
        let start = opening.start
        let end = run[run.count - 1].end
        let duration = max(0.1, end - start)
        let openingWords = opening.text.split(whereSeparator: \.isWhitespace).map(String.init)

        var hook = 0.3
        if opening.text.contains("?") { hook += 0.25 }
        if opening.text.contains(where: \.isNumber) { hook += 0.2 }
        if openingWords.contains(where: { CaptionKeywords.isKeyword($0, locale: locale) }) { hook += 0.15 }
        if opening.wordCount <= 12 { hook += 0.15 }
        if openingWords.contains(where: { secondPerson.contains(CaptionKeywords.normalized($0, locale: locale)) }) { hook += 0.1 }

        let finalText = run[run.count - 1].text.trimmingCharacters(in: .whitespaces)
        let complete = finalText.last.map { ".!?…".contains($0) } == true ? 1.0 : 0.6

        let words = run.reduce(0) { $0 + $1.wordCount }
        let rate = Double(words) / duration
        let pace = 1 - min(1, max(0, max(2.3 - rate, rate - 3.6)) / 1.5)

        let allWords = run.flatMap { $0.text.split(whereSeparator: \.isWhitespace) }.map(String.init)
        let strong = allWords.filter { CaptionKeywords.isKeyword($0, locale: locale) }.count
        let keywords = min(1, Double(strong) / Double(max(1, allWords.count)) * 10)

        let fit = 1 - min(1, abs(duration - length.target) / length.target)

        let scores = HighlightCandidate.Scores(hook: min(1, hook), complete: complete, pace: pace, keywords: keywords, fit: fit)
        let fallbackTitle = opening.text.count > 60 ? String(opening.text.prefix(57)) + "…" : opening.text
        return HighlightCandidate(
            firstSentence: first,
            lastSentence: last,
            start: start,
            end: end,
            title: title?.isEmpty == false ? title! : fallbackTitle,
            reason: reason,
            scores: scores,
            pickedByAI: reason != nil || title != nil
        )
    }

    /// A model's picks, checked and scored; then the device's own best runs that do not overlap.
    public static func merge(
        picks: [HighlightPick],
        local: [HighlightCandidate],
        sentences: [SpokenSentence],
        length: HighlightLength,
        count: Int,
        locale: Locale
    ) -> [HighlightCandidate] {
        var result: [HighlightCandidate] = []
        for pick in picks {
            let first = min(pick.from, pick.to), last = max(pick.from, pick.to)
            guard sentences.indices.contains(first), sentences.indices.contains(last) else { continue }
            let duration = sentences[last].end - sentences[first].start
            // A little leeway: a model counts sentences, not seconds.
            guard duration >= length.minimum * 0.6, duration <= length.maximum * 1.3 else { continue }
            let candidate = candidate(from: first, to: last, in: sentences, length: length, locale: locale, title: pick.title, reason: pick.reason ?? "")
            guard !result.contains(where: { $0.overlaps(candidate) }) else { continue }
            result.append(candidate)
            if result.count == count { return result }
        }
        for candidate in local where !result.contains(where: { $0.overlaps(candidate) }) {
            result.append(candidate)
            if result.count == count { break }
        }
        return result
    }
}

extension Project {
    /// Every word said, placed on the finished video. Frozen and reversed clips are left out:
    /// their words are not heard in order.
    public var spokenWords: [PlacedWord] {
        var words: [PlacedWord] = []
        var cursor = 0.0
        for segment in segments {
            let length = segment.barWeight
            defer { cursor += length }
            guard segment.playback.freeze == nil, !segment.playback.isReversed,
                  let transcript = segment.selectedTake?.transcript
            else { continue }
            let stretch = segment.sourceSeconds > 0.01 ? length / segment.sourceSeconds : 1
            for word in transcript.words {
                let start = cursor + word.range.start.seconds * stretch
                guard start < cursor + length else { continue }
                words.append(PlacedWord(
                    text: word.text,
                    range: MediaTimeRange(
                        start: MediaTime(seconds: start),
                        duration: MediaTime(seconds: max(0.05, word.range.duration.seconds * stretch))
                    )
                ))
            }
        }
        return words
    }

    public var spokenSentences: [SpokenSentence] {
        HighlightFinder.sentences(from: spokenWords)
    }
}
