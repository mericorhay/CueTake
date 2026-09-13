import Domain
import Foundation

/// Editing the video by editing what was said.
///
/// This is the feature the transcript was always for. Every other editor asks you to find a moment
/// by looking at a waveform and guessing; if the take is someone talking — and in this app it
/// always is — then the thing you actually want to cut is a *sentence*, and the sentence is right
/// there in the text with a time on it. Delete the words, the footage goes with them.
///
/// All of it runs through one primitive: rebuild a segment from the spans worth keeping. Deleting
/// a phrase, trimming the silences, and later "cut every um" are the same operation with different
/// arithmetic in front of it, which is why none of them needs a new way to mutate the project.
extension EditorModel {
    /// The words of a segment's chosen take, in take-relative seconds.
    public func spokenWords(at index: Int) -> [TimedWord] {
        guard project.segments.indices.contains(index) else { return [] }
        return project.segments[index].selectedTake?.transcript?.words ?? []
    }

    public func hasTranscript(at index: Int) -> Bool {
        !spokenWords(at: index).isEmpty
    }

    /// Rebuilds one segment out of the parts of its take worth keeping.
    ///
    /// Each span becomes a segment of its own, pointing into the same recording at a different
    /// range — the same shape a split produces, and for the same reason: nothing is copied,
    /// nothing is re-encoded, and the file on disk is never touched. The first piece keeps the
    /// original's identity so the timeline does not lose its place.
    public func rebuild(segmentAt index: Int, keeping spans: [ClosedRange<Double>]) {
        guard project.segments.indices.contains(index),
              let take = project.segments[index].selectedTake
        else { return }

        let source = take.sourceRange
        let total = source.duration.seconds
        let clean = spans
            .map { max(0, $0.lowerBound)...min(total, max($0.upperBound, 0)) }
            // Anything shorter than about four frames is not a clip, it is an artefact of the
            // arithmetic, and leaving them in litters the timeline with slivers nobody can select.
            .filter { $0.upperBound - $0.lowerBound > 0.13 }
            .sorted { $0.lowerBound < $1.lowerBound }

        guard !clean.isEmpty else { return }
        // Nothing to do: one span covering the whole take is the take.
        if clean.count == 1, clean[0].lowerBound < 0.02, total - clean[0].upperBound < 0.02 { return }

        record("editor.change.transcript", symbol: "text.cursor")

        let original = project.segments[index]
        let words = take.transcript?.words ?? []
        var rebuilt: [Segment] = []

        for (offset, span) in clean.enumerated() {
            var piece = offset == 0 ? original : original.copyWithNewIdentity()

            var newTake = Take(
                recordingID: take.recordingID,
                sourceRange: MediaTimeRange(
                    start: source.start + MediaTime(seconds: span.lowerBound),
                    duration: MediaTime(seconds: span.upperBound - span.lowerBound)
                ),
                status: take.status
            )

            let kept = words
                .filter {
                    $0.range.start.seconds >= span.lowerBound - 0.001
                        && $0.range.end.seconds <= span.upperBound + 0.001
                }
                .map { word -> TimedWord in
                    var shifted = word
                    shifted.range = MediaTimeRange(
                        start: MediaTime(seconds: word.range.start.seconds - span.lowerBound),
                        duration: word.range.duration
                    )
                    return shifted
                }

            newTake.transcript = kept.isEmpty
                ? nil
                : Transcript(localeIdentifier: project.localeIdentifier, words: kept)

            piece.takes = [newTake]
            piece.selectedTakeID = newTake.id
            piece.estimatedDuration = newTake.sourceRange.duration
            // Captions described the old timing and would be wrong by exactly the amount that was
            // removed. They are read again from the words this piece kept — clearing them, which is
            // what used to happen, made trimming pauses delete every caption in the clip.
            piece.refreshCaptions(
                maxWordsPerCue: project.captionStyle.maxWordsPerCue,
                carrying: original.captions.map { $0.shifted(by: -span.lowerBound) }
            )
            // The script follows the speech. It is what the prompter shows and what alignment
            // works against, and after a cut the old script describes a take that no longer exists.
            if !kept.isEmpty {
                piece.script = kept.map(\.text).joined(separator: " ")
            }

            rebuilt.append(piece)
        }

        project.segments.replaceSubrange(index...index, with: rebuilt)
        project.updatedAt = .now
        inspectedSegment = rebuilt.first?.id
        seek(to: min(playhead, duration))
    }

    /// Removes a stretch of speech, in take-relative seconds.
    public func removeSpoken(at index: Int, from start: Double, to end: Double) {
        guard project.segments.indices.contains(index),
              let take = project.segments[index].selectedTake
        else { return }

        let total = take.sourceRange.duration.seconds
        var spans: [ClosedRange<Double>] = []
        if start > 0.13 { spans.append(0...start) }
        if total - end > 0.13 { spans.append(end...total) }

        // Removing everything is a delete, and saying so is better than leaving a clip of nothing.
        guard !spans.isEmpty else {
            deleteSegment(at: index)
            return
        }
        rebuild(segmentAt: index, keeping: spans)
    }

    /// Gaps between words longer than `threshold`, in take-relative seconds.
    ///
    /// Reported before they are removed, so the button can say how many there are. "Trim 6 pauses"
    /// is a decision; "Trim pauses" is a leap.
    public func silenceGaps(at index: Int, threshold: Double = 0.6) -> [ClosedRange<Double>] {
        let words = spokenWords(at: index)
        guard words.count > 1 else { return [] }

        var gaps: [ClosedRange<Double>] = []
        for (left, right) in zip(words, words.dropFirst()) {
            let gap = right.range.start.seconds - left.range.end.seconds
            if gap > threshold {
                gaps.append(left.range.end.seconds...right.range.start.seconds)
            }
        }
        return gaps
    }

    /// Cuts the long pauses out of a take, keeping a little air around every phrase.
    ///
    /// The padding is not politeness, it is the difference between an edit and a machine gun:
    /// speech cut hard against its own first consonant sounds clipped, and a tenth of a second
    /// either side is enough for the ear to hear a pause rather than a splice.
    public func tightenSilences(at index: Int, threshold: Double = 0.6, pad: Double = 0.12) {
        let words = spokenWords(at: index)
        guard words.count > 1,
              let take = project.segments[index].selectedTake
        else { return }

        let total = take.sourceRange.duration.seconds
        var spans: [ClosedRange<Double>] = []
        var phraseStart = words[0].range.start.seconds
        var phraseEnd = words[0].range.end.seconds

        for word in words.dropFirst() {
            if word.range.start.seconds - phraseEnd > threshold {
                spans.append(Self.padded(phraseStart, phraseEnd, by: pad, within: total))
                phraseStart = word.range.start.seconds
            }
            phraseEnd = word.range.end.seconds
        }
        spans.append(Self.padded(phraseStart, phraseEnd, by: pad, within: total))

        guard spans.count > 1 else { return }
        rebuild(segmentAt: index, keeping: spans)
    }

    private static func padded(
        _ start: Double,
        _ end: Double,
        by pad: Double,
        within total: Double
    ) -> ClosedRange<Double> {
        max(0, start - pad)...min(total, end + pad)
    }
}
