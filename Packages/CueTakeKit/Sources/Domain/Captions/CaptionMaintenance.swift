import Foundation

// Keeping captions alive through edits.
//
// Every cut used to end with `captions = []`. The reasoning was sound — cues are timed against the
// take, and a take that changed makes those times wrong — but the result was that splitting a clip,
// trimming its pauses or merging two halves quietly deleted its captions, and the user found out
// at export. The transcript already moves with the footage; captions are a reading of the
// transcript, so they can simply be read again. The only thing that cannot be re-derived is what
// the user typed by hand, and that is carried across with the same shift the footage took.

extension Transcript {
    /// The words said between `start` and `end` of take-relative time, rebased so `start` is zero.
    ///
    /// A word belongs to the side its middle falls on. Cutting through a word is common — a split
    /// lands wherever the playhead was — and giving it to both halves would caption it twice.
    public func slice(from start: Double, to end: Double) -> Transcript? {
        let kept = words.compactMap { word -> TimedWord? in
            let middle = word.range.start.seconds + word.range.duration.seconds / 2
            guard middle >= start, middle < end else { return nil }
            var shifted = word
            shifted.range = MediaTimeRange(
                start: MediaTime(seconds: max(0, word.range.start.seconds - start)),
                duration: word.range.duration
            )
            return shifted
        }
        return kept.isEmpty ? nil : Transcript(localeIdentifier: localeIdentifier, words: kept)
    }

    /// This transcript followed by another that starts `offset` seconds later.
    public func appending(_ other: Transcript?, at offset: Double) -> Transcript {
        guard let other else { return self }
        let shifted = other.words.map { word -> TimedWord in
            var moved = word
            moved.range = MediaTimeRange(
                start: MediaTime(seconds: word.range.start.seconds + offset),
                duration: word.range.duration
            )
            return moved
        }
        return Transcript(localeIdentifier: localeIdentifier, words: words + shifted)
    }
}

extension CaptionCue {
    /// The same cue, `seconds` later (or earlier, when negative).
    public func shifted(by seconds: Double) -> CaptionCue {
        var moved = self
        moved.range = MediaTimeRange(
            start: MediaTime(seconds: range.start.seconds + seconds),
            duration: range.duration
        )
        return moved
    }
}

extension Segment {
    /// Reads the captions again from the chosen take's transcript.
    ///
    /// - Parameter edited: cues from before the edit, already shifted into this segment's time.
    ///   Only the hand-edited ones are kept; the rest are rebuilt. Anything that falls outside the
    ///   footage this segment still has is dropped, and automatic cues that would sit on top of a
    ///   kept one give way to it — what the user typed wins over what the machine heard.
    public mutating func refreshCaptions(maxWordsPerCue: Int, carrying edited: [CaptionCue] = []) {
        let length = sourceSeconds
        let kept: [CaptionCue] = edited.compactMap { cue in
            guard cue.isUserEdited else { return nil }
            let start = max(0, cue.range.start.seconds)
            let end = min(length, cue.range.end.seconds)
            guard end - start > 0.1 else { return nil }
            var clamped = cue
            clamped.range = MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: end - start))
            return clamped
        }

        var automatic = selectedTake?.transcript.map {
            CaptionBuilder.cues(from: $0, maxWordsPerCue: maxWordsPerCue)
        } ?? []
        automatic.removeAll { cue in
            kept.contains { $0.range.start < cue.range.end && cue.range.start < $0.range.end }
        }

        captions = (automatic + kept).sorted { $0.range.start < $1.range.start }
    }
}
