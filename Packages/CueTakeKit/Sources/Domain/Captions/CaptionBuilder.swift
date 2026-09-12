import Foundation

/// Turns a transcript into caption cues.
///
/// Not an AI task, whatever the category calls it. The transcript already carries the words and
/// when they were said; a cue is a decision about how many of them to show at once, and that is a
/// rule. The rule is the interesting part:
///
/// - A cue breaks at a sentence end even when it is short, because a caption that runs a full stop
///   into the next thought is read as one sentence and misunderstood.
/// - Otherwise it breaks at `maxWordsPerCue`, which is what keeps a caption inside a thumb's width
///   on a phone held at arm's length.
/// - A gap longer than `silenceBreak` also breaks, because the speaker stopped, and holding the
///   previous words on screen through a pause makes the video look frozen.
public enum CaptionBuilder {
    public static func cues(
        from transcript: Transcript,
        maxWordsPerCue: Int = 4,
        silenceBreak: Double = 0.6
    ) -> [CaptionCue] {
        guard !transcript.words.isEmpty else { return [] }

        var cues: [CaptionCue] = []
        var current: [TimedWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            cues.append(
                CaptionCue(
                    text: current.map(\.text).joined(separator: " "),
                    range: MediaTimeRange(
                        start: first.range.start,
                        duration: last.range.end - first.range.start
                    )
                )
            )
            current = []
        }

        for (index, word) in transcript.words.enumerated() {
            if let previous = current.last,
               word.range.start.seconds - previous.range.end.seconds >= silenceBreak {
                flush()
            }

            current.append(word)

            let endsSentence = word.text.hasSuffix(".") || word.text.hasSuffix("?")
                || word.text.hasSuffix("!") || word.text.hasSuffix("…")
            let isLast = index == transcript.words.count - 1

            if endsSentence || current.count >= maxWordsPerCue || isLast {
                flush()
            }
        }

        flush()
        return cues
    }
}
