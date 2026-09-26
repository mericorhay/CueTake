import Foundation

/// Hand edits to a segment's captions: retyping, retiming, splitting, joining.
///
/// Kept here rather than in a screen so the rules hold wherever an edit comes from, and so they
/// can be tested without one. The rules are few and all of them are about not producing a caption
/// nobody can read: at least a fifth of a second on screen, never outside the clip's own footage,
/// and never on top of the cue beside it.
extension Segment {
    /// The shortest time a caption stays up. Below this it is a flash, not something read.
    public static let shortestCaption = 0.2

    private func captionIndex(_ id: CaptionCue.ID) -> Int? {
        captions.firstIndex { $0.id == id }
    }

    /// Where a cue may start and end without leaving the clip or overlapping its neighbours.
    public func captionBounds(for id: CaptionCue.ID) -> ClosedRange<Double> {
        guard let index = captionIndex(id) else { return 0...max(0, sourceSeconds) }
        let lower = index > 0 ? captions[index - 1].range.end.seconds : 0
        let upper = index + 1 < captions.count ? captions[index + 1].range.start.seconds : max(sourceSeconds, lower)
        return lower...max(lower, upper)
    }

    public mutating func setCaptionText(_ id: CaptionCue.ID, to text: String) {
        guard let index = captionIndex(id), captions[index].text != text else { return }
        captions[index].text = text
        captions[index].isUserEdited = true
    }

    /// Moves a cue's start and end by the given seconds, clamped to what the rules allow.
    public mutating func nudgeCaption(_ id: CaptionCue.ID, start deltaStart: Double = 0, end deltaEnd: Double = 0) {
        guard let index = captionIndex(id) else { return }
        let bounds = captionBounds(for: id)
        let cue = captions[index]

        var start = cue.range.start.seconds + deltaStart
        var end = cue.range.end.seconds + deltaEnd
        start = min(max(bounds.lowerBound, start), bounds.upperBound - Self.shortestCaption)
        end = max(min(bounds.upperBound, end), start + Self.shortestCaption)
        end = min(end, bounds.upperBound)
        guard end - start >= Self.shortestCaption - 0.001 else { return }

        captions[index].range = MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: end - start))
        captions[index].isUserEdited = true
    }

    /// Whether a cue has enough words to become two.
    public func canSplitCaption(_ id: CaptionCue.ID) -> Bool {
        guard let index = captionIndex(id) else { return false }
        return ScriptText.words(in: captions[index].text).count > 1
    }

    /// Cuts a cue in two at its middle word.
    ///
    /// Timed at the moment that word was said when the transcript knows it, and in proportion to
    /// the letters otherwise — the second half of a caption should appear when the second half of
    /// the sentence is spoken, not at the halfway mark of the clock.
    public mutating func splitCaption(_ id: CaptionCue.ID) {
        guard let index = captionIndex(id), canSplitCaption(id) else { return }
        let cue = captions[index]
        let words = ScriptText.words(in: cue.text).map(String.init)
        let cut = words.count / 2
        let firstText = words[..<cut].joined(separator: " ")
        let secondText = words[cut...].joined(separator: " ")

        let start = cue.range.start.seconds
        let end = cue.range.end.seconds
        let spoken = (selectedTake?.transcript?.words ?? []).filter {
            $0.range.start.seconds >= start - 0.02 && $0.range.start.seconds < end
        }
        var split: Double
        if spoken.count == words.count {
            split = spoken[cut].range.start.seconds
        } else {
            let share = Double(firstText.count) / Double(max(1, firstText.count + secondText.count))
            split = start + (end - start) * share
        }
        split = min(max(split, start + Self.shortestCaption), end - Self.shortestCaption)
        guard split > start, split < end else { return }

        var first = cue
        first.text = firstText
        first.range = MediaTimeRange(start: cue.range.start, duration: MediaTime(seconds: split - start))
        first.isUserEdited = true

        let second = CaptionCue(
            text: secondText,
            range: MediaTimeRange(start: MediaTime(seconds: split), duration: MediaTime(seconds: end - split)),
            styleOverride: cue.styleOverride,
            position: cue.position,
            isUserEdited: true,
            scale: cue.scale
        )

        captions[index] = first
        captions.insert(second, at: index + 1)
    }

    public func canMergeCaption(_ id: CaptionCue.ID) -> Bool {
        guard let index = captionIndex(id) else { return false }
        return index + 1 < captions.count
    }

    /// Joins a cue with the one after it: both texts, from the first's start to the second's end.
    public mutating func mergeCaptionWithNext(_ id: CaptionCue.ID) {
        guard let index = captionIndex(id), index + 1 < captions.count else { return }
        let next = captions.remove(at: index + 1)
        captions[index].text = [captions[index].text, next.text].filter { !$0.isEmpty }.joined(separator: " ")
        captions[index].range = MediaTimeRange(
            start: captions[index].range.start,
            duration: next.range.end - captions[index].range.start
        )
        captions[index].isUserEdited = true
    }

    public mutating func removeCaption(_ id: CaptionCue.ID) {
        captions.removeAll { $0.id == id }
    }
}
