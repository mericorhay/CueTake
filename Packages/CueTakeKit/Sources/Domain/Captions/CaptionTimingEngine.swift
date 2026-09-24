import Foundation

/// Keeps captions attached to the speech instead of to a fixed, guessed duration.
///
/// The transcript is the clock: a cue starts on its first spoken word, stays long enough to be
/// read, and yields before the next cue. This is also applied when an old project is opened, so
/// projects created before adaptive timing do not keep stale early or lingering captions.
public enum CaptionTimingEngine {
    public static let minimumSeconds = 0.5
    public static let maximumSeconds = 2.2
    public static let charactersPerSecond = 15.0
    public static let spokenTailSeconds = 0.08
    public static let handoffGapSeconds = 0.03

    /// Returns a timing for a generated or untouched cue. User-edited cues intentionally remain
    /// under the user's control and return nil here.
    public static func range(
        for cue: CaptionCue,
        transcript: Transcript,
        nextStart: Double? = nil
    ) -> MediaTimeRange? {
        guard !cue.isUserEdited, !transcript.words.isEmpty else { return nil }

        let expectedWords = max(1, ScriptText.words(in: cue.text).count)
        let cueStart = cue.range.start.seconds
        let cueEnd = cue.range.end.seconds
        var words = transcript.words.filter {
            $0.range.end.seconds > cueStart - 0.12 && $0.range.start.seconds < cueEnd + 0.12
        }

        // A legacy cue can be so long that it overlaps the next sentence. Keep the words nearest
        // its original start and cap them to the cue's own text rather than borrowing later speech.
        if words.count > expectedWords {
            words = Array(words.sorted { $0.range.start.seconds < $1.range.start.seconds }.prefix(expectedWords))
        }

        // If old timings drifted away from the transcript, anchor to the nearest word and take the
        // same number of words as the cue contains. This avoids showing text before anyone speaks.
        if words.isEmpty {
            guard let nearest = transcript.words.min(by: {
                abs($0.range.start.seconds - cueStart) < abs($1.range.start.seconds - cueStart)
            }), let index = transcript.words.firstIndex(of: nearest) else { return nil }
            let end = min(transcript.words.count, index + expectedWords)
            words = Array(transcript.words[index..<end])
        }

        guard let first = words.first, let last = words.last else { return nil }
        return adaptiveRange(
            text: cue.text,
            firstStart: first.range.start.seconds,
            lastEnd: last.range.end.seconds,
            nextStart: nextStart
        )
    }

    /// Timing for a newly generated cue from its exact spoken words.
    public static func range(
        text: String,
        words: [TimedWord],
        nextStart: Double? = nil
    ) -> MediaTimeRange? {
        guard let first = words.first, let last = words.last else { return nil }
        return adaptiveRange(
            text: text,
            firstStart: first.range.start.seconds,
            lastEnd: last.range.end.seconds,
            nextStart: nextStart
        )
    }

    private static func adaptiveRange(
        text: String,
        firstStart: Double,
        lastEnd: Double,
        nextStart: Double?
    ) -> MediaTimeRange {
        let start = max(0, firstStart)
        let spoken = max(0.05, lastEnd - start)
        let reading = Double(max(1, text.count)) / charactersPerSecond
        // Shown for as long as it is being said, and — for a short cue said quickly — a little
        // longer so it can be read, up to `maximumSeconds`. The cap limits only that extension:
        // capping the spoken part took a caption off screen while its words were still coming.
        let readable = min(maximumSeconds, max(minimumSeconds, reading))
        let wanted = max(spoken + spokenTailSeconds, readable)

        // With nothing after it, the cue has all the time it wants; the clip's end still caps it.
        let available = nextStart.map {
            max(0.05, $0 - start - handoffGapSeconds)
        } ?? wanted
        let duration = min(wanted, available)

        return MediaTimeRange(
            start: MediaTime(seconds: start),
            duration: MediaTime(seconds: max(0.05, duration))
        )
    }
}
