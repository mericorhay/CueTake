import Foundation

/// How well a listener heard a recording, against a transcript a person checked.
///
/// The numbers every change to the speech engine is judged by: word error rate, how far word
/// start times drift (what decides whether a cut lands between words), and how many of the "um"s
/// were caught (what decides whether the cleanup can see them).
public enum SpeechBenchmark {
    /// One recording: what was really said, and what each listener heard.
    public struct Fixture: Codable, Hashable, Sendable {
        public var name: String
        public var localeIdentifier: String
        /// Checked by a person: `[text, start, end]` in seconds of the recording.
        public var reference: [[Word]]
        /// Listener name → what it heard, in the same shape.
        public var heard: [String: [[Word]]]

        public enum Word: Codable, Hashable, Sendable {
            case text(String)
            case time(Double)

            public init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let number = try? container.decode(Double.self) {
                    self = .time(number)
                } else {
                    self = .text(try container.decode(String.self))
                }
            }

            public func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let text): try container.encode(text)
                case .time(let time): try container.encode(time)
                }
            }
        }

        public init(name: String, localeIdentifier: String, reference: [TimedWord], heard: [String: [TimedWord]]) {
            self.name = name
            self.localeIdentifier = localeIdentifier
            self.reference = Self.rows(reference)
            self.heard = heard.mapValues(Self.rows)
        }

        static func rows(_ words: [TimedWord]) -> [[Word]] {
            words.map { [.text($0.text), .time(Self.round($0.range.start.seconds)), .time(Self.round($0.range.end.seconds))] }
        }

        static func round(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }

        static func words(_ rows: [[Word]]) -> [TimedWord] {
            rows.compactMap { row in
                guard row.count >= 3, case .text(let text) = row[0], case .time(let start) = row[1], case .time(let end) = row[2] else { return nil }
                return TimedWord(text: text, range: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: max(0, end - start))))
            }
        }

        public var referenceWords: [TimedWord] { Self.words(reference) }
        public func words(of listener: String) -> [TimedWord] { Self.words(heard[listener] ?? []) }

        /// A starting point from a real recording: both listeners, and the chosen words as the
        /// reference for a person to correct.
        public init(name: String, versions: TranscriptVersions) {
            var heard: [String: [TimedWord]] = [
                SpeechSource.device.rawValue: versions.passages.flatMap(\.device),
            ]
            if versions.hasCloud {
                heard[SpeechSource.cloud.rawValue] = versions.passages.flatMap(\.cloud)
            }
            self.init(
                name: name,
                localeIdentifier: versions.localeIdentifier,
                reference: versions.passages.flatMap(\.chosen),
                heard: heard
            )
        }
    }

    public struct Score: Hashable, Sendable {
        /// Substitutions, insertions and deletions over the reference length.
        public var wordErrorRate: Double
        /// Mean distance between the start times of words both agree on, in seconds.
        public var startError: Double
        /// Share of the reference's filler sounds that were heard. Nil when it has none.
        public var fillerRecall: Double?
        public var referenceWords: Int
    }

    public static func score(heard: [TimedWord], reference: [TimedWord], localeIdentifier: String) -> Score {
        let locale = Locale(identifier: localeIdentifier)
        let a = reference.map { ScriptAlignment.key($0.text, locale: locale) }
        let b = heard.map { ScriptAlignment.key($0.text, locale: locale) }
        let errors = editDistance(a, b)

        // Start error over the words the two agree on, paired in order.
        let alignment = ScriptAlignment.align(spoken: b, script: a, locale: locale)
        var drift: [Double] = []
        for (index, match) in alignment.spoken.enumerated() {
            if case .exact(let target) = match {
                drift.append(abs(heard[index].range.start.seconds - reference[target].range.start.seconds))
            }
        }

        let fillers = a.indices.filter { Disfluency.isSound(a[$0], locale: locale) }
        var recall: Double?
        if !fillers.isEmpty {
            let caught = fillers.filter { index in
                let moment = reference[index].range.start.seconds
                return heard.enumerated().contains { position, word in
                    Disfluency.isSound(b[position], locale: locale) && abs(word.range.start.seconds - moment) < 0.5
                }
            }
            recall = Double(caught.count) / Double(fillers.count)
        }

        return Score(
            wordErrorRate: a.isEmpty ? (b.isEmpty ? 0 : 1) : Double(errors) / Double(a.count),
            startError: drift.isEmpty ? 0 : drift.reduce(0, +) / Double(drift.count),
            fillerRecall: recall,
            referenceWords: a.count
        )
    }

    static func editDistance(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var diagonal = row[0]
            row[0] = i
            for j in 1...b.count {
                let above = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, diagonal + (a[i - 1] == b[j - 1] ? 0 : 1))
                diagonal = above
            }
        }
        return row[b.count]
    }
}
