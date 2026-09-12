import Foundation

/// What was actually said in a take, with word timings.
public struct Transcript: Hashable, Sendable, Codable {
    public var localeIdentifier: String
    public var words: [TimedWord]

    public init(localeIdentifier: String, words: [TimedWord]) {
        self.localeIdentifier = localeIdentifier
        self.words = words
    }

    public var text: String { words.map(\.text).joined(separator: " ") }
}

public struct TimedWord: Hashable, Sendable, Codable {
    public var text: String
    /// Relative to the start of the take that owns the transcript.
    public var range: MediaTimeRange
    public var confidence: Double?
    /// Index into `ScriptText.words(in: segment.script)` when alignment matched this word.
    /// Nil for ad-libs and filler words.
    public var scriptWordIndex: Int?

    public init(text: String, range: MediaTimeRange, confidence: Double? = nil, scriptWordIndex: Int? = nil) {
        self.text = text
        self.range = range
        self.confidence = confidence
        self.scriptWordIndex = scriptWordIndex
    }
}

/// Where the speaker currently is in the script. Produced by live speech tracking,
/// consumed by the teleprompter.
public struct ScriptPosition: Hashable, Sendable {
    public var segmentID: Segment.ID
    public var wordIndex: Int

    public init(segmentID: Segment.ID, wordIndex: Int) {
        self.segmentID = segmentID
        self.wordIndex = wordIndex
    }
}
