import Foundation

/// Who heard the words.
public enum SpeechSource: String, Hashable, Sendable, Codable, CaseIterable {
    /// Apple's recognisers, on the phone.
    case device
    /// Whisper, on the server.
    case cloud
}

/// One stretch of speech as both listeners heard it, and which of the two is used.
///
/// A recording is heard twice, independently, and the two answers are laid side by side in short
/// passages — a breath to a breath. Either listener can be right about a passage and wrong about
/// the next, so the choice is made per passage: the video can take its first sentence from one and
/// the rest from the other.
public struct TranscriptPassage: Identifiable, Hashable, Sendable, Codable {
    public enum Decider: String, Hashable, Sendable, Codable {
        /// The built-in rules, before or without the AI.
        case rule
        case ai
        case user
    }

    public var id: Int
    /// Seconds into the recording.
    public var start: Double
    public var end: Double
    public var device: [TimedWord]
    public var cloud: [TimedWord]
    public var choice: SpeechSource
    public var decidedBy: Decider

    public init(
        id: Int,
        start: Double,
        end: Double,
        device: [TimedWord],
        cloud: [TimedWord],
        choice: SpeechSource = .device,
        decidedBy: Decider = .rule
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.device = device
        self.cloud = cloud
        self.choice = choice
        self.decidedBy = decidedBy
    }

    public func words(from source: SpeechSource) -> [TimedWord] {
        source == .device ? device : cloud
    }

    public var chosen: [TimedWord] { words(from: choice) }

    public func text(from source: SpeechSource) -> String {
        words(from: source).map(\.text).joined(separator: " ")
    }

    /// Whether both listeners heard the same words, ignoring case and punctuation.
    public func agrees(locale: Locale) -> Bool {
        TranscriptVersions.keys(device, locale: locale) == TranscriptVersions.keys(cloud, locale: locale)
    }
}

/// Everything both listeners heard in one recording, in recording seconds.
public struct TranscriptVersions: Hashable, Sendable, Codable {
    public var localeIdentifier: String
    public var passages: [TranscriptPassage]
    /// Whether the server listener answered at all. Without it there is nothing to compare.
    public var hasCloud: Bool

    public init(localeIdentifier: String, passages: [TranscriptPassage], hasCloud: Bool) {
        self.localeIdentifier = localeIdentifier
        self.passages = passages
        self.hasCloud = hasCloud
    }

    /// Lays both answers side by side and picks each passage by rule.
    ///
    /// - Parameter script: what the speaker meant to say, when there is one. The listener closer to
    ///   it is almost always the one that heard right.
    public init(localeIdentifier: String, device: [TimedWord], cloud: [TimedWord]?, script: String = "") {
        self.localeIdentifier = localeIdentifier
        self.hasCloud = cloud != nil
        let locale = Locale(identifier: localeIdentifier)
        let scriptKeys = Set(ScriptText.words(in: script).map { ScriptText.matchKey(for: $0, locale: locale) })
        passages = Self.passages(device: device, cloud: cloud ?? []).map { passage in
            var decided = passage
            decided.choice = Self.ruleChoice(for: passage, scriptKeys: scriptKeys, locale: locale)
            return decided
        }
    }

    public var locale: Locale { Locale(identifier: localeIdentifier) }

    /// The words the video uses: each passage's chosen listener, in order.
    public var merged: Transcript {
        Transcript(localeIdentifier: localeIdentifier, words: passages.flatMap(\.chosen))
    }

    /// Passages where the two listeners disagree — the only ones worth a second opinion.
    public var disputed: [TranscriptPassage] {
        guard hasCloud else { return [] }
        return passages.filter { !$0.agrees(locale: locale) }
    }

    public mutating func choose(_ source: SpeechSource, forPassage id: TranscriptPassage.ID, by decider: TranscriptPassage.Decider) {
        guard let index = passages.firstIndex(where: { $0.id == id }) else { return }
        // A choice the user made is theirs: the AI answering late does not overrule it.
        if decider == .ai, passages[index].decidedBy == .user { return }
        passages[index].choice = source
        passages[index].decidedBy = decider
    }

    /// The passage being said at `seconds` into the recording, or the nearest one within half a second.
    public func passage(at seconds: Double) -> TranscriptPassage? {
        if let inside = passages.first(where: { $0.start - 0.05 <= seconds && seconds < $0.end + 0.05 }) {
            return inside
        }
        return passages
            .min { distance($0, seconds) < distance($1, seconds) }
            .flatMap { distance($0, seconds) < 0.5 ? $0 : nil }
    }

    private func distance(_ passage: TranscriptPassage, _ seconds: Double) -> Double {
        seconds < passage.start ? passage.start - seconds : max(0, seconds - passage.end)
    }

    /// The chosen words inside a take's part of the recording, relative to where the take starts.
    ///
    /// A word belongs to the take its middle falls in, the same rule a split uses.
    public func words(within range: MediaTimeRange) -> [TimedWord] {
        let start = range.start.seconds
        let end = range.end.seconds
        return merged.words.compactMap { word in
            let middle = word.range.start.seconds + word.range.duration.seconds / 2
            guard middle >= start - 0.001, middle < end + 0.001 else { return nil }
            var shifted = word
            shifted.range = MediaTimeRange(
                start: MediaTime(seconds: max(0, word.range.start.seconds - start)),
                duration: word.range.duration
            )
            return shifted
        }
    }

    // MARK: - Passages

    /// Cuts both answers at the moments where neither listener heard a word.
    ///
    /// A passage ends at a pause of a little under half a second, or — in speech that never
    /// pauses — at the first gap of any size once it has run for eight seconds, so a passage stays
    /// short enough to compare at a glance.
    static func passages(device: [TimedWord], cloud: [TimedWord]) -> [TranscriptPassage] {
        let tagged = (device.map { ($0, SpeechSource.device) } + cloud.map { ($0, SpeechSource.cloud) })
            .sorted { $0.0.range.start < $1.0.range.start }
        guard !tagged.isEmpty else { return [] }

        var result: [TranscriptPassage] = []
        var current = TranscriptPassage(id: 0, start: tagged[0].0.range.start.seconds, end: tagged[0].0.range.start.seconds, device: [], cloud: [])

        func flush() {
            guard !current.device.isEmpty || !current.cloud.isEmpty else { return }
            result.append(current)
        }

        for (word, source) in tagged {
            let start = word.range.start.seconds
            let hasWords = !current.device.isEmpty || !current.cloud.isEmpty
            let gap = start - current.end
            let long = current.end - current.start > 8
            if hasWords, gap >= 0.45 || (long && gap >= 0) {
                flush()
                current = TranscriptPassage(id: result.count, start: start, end: start, device: [], cloud: [])
            }
            if source == .device { current.device.append(word) } else { current.cloud.append(word) }
            current.end = max(current.end, word.range.end.seconds)
        }
        flush()
        return result
    }

    /// The rule used until — or instead of — the AI.
    ///
    /// 1. One listener heard nothing: the other.
    /// 2. Both heard the same words: the phone, whose timings are measured rather than estimated.
    /// 3. There is a script and one answer is clearly closer to it: that one.
    /// 4. One heard far fewer words: the other — a listener that drops words is the common failure.
    /// 5. Otherwise the server, the stronger model.
    static func ruleChoice(for passage: TranscriptPassage, scriptKeys: Set<String>, locale: Locale) -> SpeechSource {
        if passage.cloud.isEmpty { return .device }
        if passage.device.isEmpty { return .cloud }
        if passage.agrees(locale: locale) { return .device }

        if !scriptKeys.isEmpty {
            let device = closeness(passage.device, to: scriptKeys, locale: locale)
            let cloud = closeness(passage.cloud, to: scriptKeys, locale: locale)
            if abs(device - cloud) >= 0.15 { return device > cloud ? .device : .cloud }
        }

        let deviceCount = Double(passage.device.count)
        let cloudCount = Double(passage.cloud.count)
        if deviceCount < cloudCount * 0.6 { return .cloud }
        if cloudCount < deviceCount * 0.6 { return .device }

        let confidences = passage.device.compactMap(\.confidence)
        if !confidences.isEmpty, confidences.reduce(0, +) / Double(confidences.count) >= 0.85 { return .device }
        return .cloud
    }

    static func closeness(_ words: [TimedWord], to script: Set<String>, locale: Locale) -> Double {
        guard !words.isEmpty else { return 0 }
        let keys = words.map { ScriptText.matchKey(for: $0.text, locale: locale) }
        return Double(keys.filter(script.contains).count) / Double(keys.count)
    }

    static func keys(_ words: [TimedWord], locale: Locale) -> [String] {
        words.map { ScriptText.matchKey(for: $0.text, locale: locale) }.filter { !$0.isEmpty }
    }
}

extension Project {
    /// Uses `source` for one passage of a recording, and reads the words and captions of every clip
    /// cut from that recording again.
    ///
    /// Captions the user typed themselves are kept.
    public mutating func choose(
        _ source: SpeechSource,
        forPassage passage: TranscriptPassage.ID,
        inRecording recordingID: Recording.ID,
        by decider: TranscriptPassage.Decider
    ) {
        guard let recordingIndex = recordings.firstIndex(where: { $0.id == recordingID }),
              recordings[recordingIndex].speech != nil
        else { return }
        recordings[recordingIndex].speech?.choose(source, forPassage: passage, by: decider)
        rereadSpeech(ofRecording: recordingID)
    }

    /// Every take of a recording given the words its versions now choose.
    public mutating func rereadSpeech(ofRecording recordingID: Recording.ID) {
        guard let versions = recordings.first(where: { $0.id == recordingID })?.speech else { return }
        for index in segments.indices {
            var touched = false
            for takeIndex in segments[index].takes.indices where segments[index].takes[takeIndex].recordingID == recordingID {
                let words = versions.words(within: segments[index].takes[takeIndex].sourceRange)
                let transcript = words.isEmpty ? nil : Transcript(localeIdentifier: versions.localeIdentifier, words: words)
                if segments[index].takes[takeIndex].transcript != transcript {
                    segments[index].takes[takeIndex].transcript = transcript
                    if segments[index].takes[takeIndex].id == segments[index].selectedTakeID { touched = true }
                }
            }
            if touched {
                segments[index].refreshCaptions(maxWordsPerCue: captionStyle.maxWordsPerCue, carrying: segments[index].captions)
            }
        }
        updatedAt = .now
    }
}
