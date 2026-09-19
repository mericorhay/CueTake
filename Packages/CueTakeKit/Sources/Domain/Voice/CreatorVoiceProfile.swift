import Foundation

/// How a creator talks, kept as facts rather than a paragraph: the pace they naturally read at,
/// how long their sentences run, the fillers they lean on, how they open and how they send people
/// to the link, and the words they never use.
///
/// Part of it is measured from their own videos, part of it is theirs to write. The prompter and
/// the suflör start at their pace; the AI writes to it.
public struct CreatorVoiceProfile: Codable, Hashable, Sendable {
    /// Words a minute while talking, pauses between sentences left out.
    public var wordsPerMinute: Double?
    /// Words between two pauses long enough to end a sentence.
    public var sentenceWords: Double?
    /// The fillers heard most, most used first.
    public var fillers: [String]
    /// How they start a video, in their words.
    public var openings: [String]
    /// How they send people to the code, the link, the follow.
    public var callsToAction: [String]
    /// Words they do not use.
    public var avoid: [String]
    /// Anything else about how they talk, in their own words.
    public var notes: String
    /// What the measurement was taken from.
    public var measuredWords: Int
    public var measuredVideos: Int
    public var measuredAt: Date?
    /// The prompter and the suflör start at `wordsPerMinute`.
    public var usesPace: Bool

    public init(
        wordsPerMinute: Double? = nil, sentenceWords: Double? = nil, fillers: [String] = [], openings: [String] = [],
        callsToAction: [String] = [], avoid: [String] = [], notes: String = "", measuredWords: Int = 0,
        measuredVideos: Int = 0, measuredAt: Date? = nil, usesPace: Bool = true
    ) {
        self.wordsPerMinute = wordsPerMinute
        self.sentenceWords = sentenceWords
        self.fillers = fillers
        self.openings = openings
        self.callsToAction = callsToAction
        self.avoid = avoid
        self.notes = notes
        self.measuredWords = measuredWords
        self.measuredVideos = measuredVideos
        self.measuredAt = measuredAt
        self.usesPace = usesPace
    }

    public var isEmpty: Bool {
        wordsPerMinute == nil && fillers.isEmpty && openings.isEmpty && callsToAction.isEmpty && avoid.isEmpty
            && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The pace to start the prompter at, when the creator chose to use theirs.
    public var pace: Double? { usesPace ? wordsPerMinute : nil }

    /// The profile as lines for the writer to follow.
    public var promptText: String? {
        guard !isEmpty else { return nil }
        var lines: [String] = []
        if let wordsPerMinute { lines.append("pace: about \(Int(wordsPerMinute.rounded())) words a minute") }
        if let sentenceWords { lines.append("sentence length: about \(Int(sentenceWords.rounded())) words") }
        if !fillers.isEmpty { lines.append("their fillers (at most one per card): " + fillers.prefix(5).joined(separator: ", ")) }
        if !openings.isEmpty { lines.append("how they open: " + openings.prefix(4).map { "\"\($0)\"" }.joined(separator: " / ")) }
        if !callsToAction.isEmpty { lines.append("how they call to action: " + callsToAction.prefix(4).map { "\"\($0)\"" }.joined(separator: " / ")) }
        if !avoid.isEmpty { lines.append("words they never use: " + avoid.joined(separator: ", ")) }
        let note = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { lines.append("in their words: " + String(note.prefix(300))) }
        return lines.joined(separator: "\n")
    }

    /// Takes a fresh measurement, keeping what the creator wrote: their openings and calls to
    /// action are only suggested when they have none.
    public mutating func adopt(_ measured: CreatorVoiceProfile) {
        wordsPerMinute = measured.wordsPerMinute
        sentenceWords = measured.sentenceWords
        fillers = measured.fillers
        if openings.isEmpty { openings = measured.openings }
        if callsToAction.isEmpty { callsToAction = measured.callsToAction }
        measuredWords = measured.measuredWords
        measuredVideos = measured.measuredVideos
        measuredAt = measured.measuredAt
    }
}

/// Measures a creator's way of talking from what they said in their videos.
public enum VoiceMeasure {
    /// A pause this long ends a sentence; recognisers seldom punctuate speech.
    static let sentencePause = 0.55
    /// A gap longer than this is not talking, and is left out of the pace.
    static let talkingGap = 1.2

    static let fillerWords: [String: [String]] = [
        "tr": ["yani", "şey", "hani", "işte", "aslında", "açıkçası", "tamam", "ee", "ıı", "falan", "resmen"],
        "en": ["like", "basically", "actually", "literally", "honestly", "so", "um", "uh", "you know", "right"],
        "es": ["o sea", "bueno", "pues", "este", "digamos", "tipo", "vale", "eh"],
    ]

    /// Each recording's words, newest first.
    public static func profile(from transcripts: [Transcript], localeIdentifier: String, now: Date = .now) -> CreatorVoiceProfile {
        var talking = 0.0
        var counted = 0
        var sentences: [Int] = []
        var openings: [String] = []
        var endings: [String] = []
        var fillerCounts: [String: Int] = [:]
        let language = Locale(identifier: localeIdentifier).language.languageCode?.identifier ?? "en"
        let fillers = fillerWords[language] ?? fillerWords["en"] ?? []
        var videos = 0

        for transcript in transcripts {
            let words = transcript.words.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            guard words.count >= 8 else { continue }
            videos += 1
            var run = 1
            var sentence: [String] = [words[0].text]
            var firstSentence: [String]?
            var lastSentence: [String] = []
            for index in 1..<words.count {
                let gap = words[index].range.start.seconds - (words[index - 1].range.start.seconds + words[index - 1].range.duration.seconds)
                let span = words[index].range.start.seconds - words[index - 1].range.start.seconds
                if gap < talkingGap, span > 0 {
                    talking += span
                    counted += 1
                }
                if gap >= sentencePause {
                    sentences.append(run)
                    if firstSentence == nil { firstSentence = sentence }
                    lastSentence = sentence
                    run = 0
                    sentence = []
                }
                run += 1
                sentence.append(words[index].text)
            }
            sentences.append(run)
            if firstSentence == nil { firstSentence = sentence }
            lastSentence = sentence.isEmpty ? lastSentence : sentence
            if let firstSentence, (3...14).contains(firstSentence.count) { openings.append(firstSentence.joined(separator: " ")) }
            if (3...16).contains(lastSentence.count) { endings.append(lastSentence.joined(separator: " ")) }

            let lowered = words.map { $0.text.lowercased() }
            let joined = " " + lowered.joined(separator: " ") + " "
            for filler in fillers {
                let hits = joined.components(separatedBy: " \(filler) ").count - 1
                if hits > 0 { fillerCounts[filler, default: 0] += hits }
            }
        }

        let totalWords = transcripts.reduce(0) { $0 + $1.words.count }
        let perMinute = talking > 5 ? Double(counted) / talking * 60 : nil
        let averageSentence = sentences.isEmpty ? nil : Double(sentences.reduce(0, +)) / Double(sentences.count)
        let usedFillers = fillerCounts
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .map(\.key)
        return CreatorVoiceProfile(
            wordsPerMinute: perMinute.map { min(260, max(60, $0)) },
            sentenceWords: averageSentence,
            fillers: Array(usedFillers.prefix(5)),
            openings: Array(unique(openings).prefix(3)),
            callsToAction: Array(unique(endings).prefix(3)),
            measuredWords: totalWords,
            measuredVideos: videos,
            measuredAt: now
        )
    }

    private static func unique(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.filter { seen.insert($0.lowercased()).inserted }
    }
}
