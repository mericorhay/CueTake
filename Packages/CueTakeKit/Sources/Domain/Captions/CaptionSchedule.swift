import Foundation

/// The last word on when each caption is on screen, over the whole video.
///
/// Each cue is timed on its own from its words, so two can claim the same moment: a retimed cue
/// reaching into the next, a hand-edited one, the end of one clip and the start of the next. On
/// screen that was two captions stacked, or one replaced mid-word. Settled here, in order:
///
/// - A cue ends before the next one starts. Only one caption is ever on screen.
/// - A cue said right before the next stays until it starts, so a sentence reads as one flow
///   instead of blinking off and on between every few words. A real pause still clears the screen.
public enum CaptionSchedule {
    /// A gap shorter than this between two cues is closed.
    public static let bridgeSeconds = 0.6
    public static let handoffSeconds = 0.02

    public static func settled(_ cues: [PlacedCue]) -> [PlacedCue] {
        var cues = cues.sorted { $0.range.start.seconds < $1.range.start.seconds }
        guard cues.count > 1 else { return cues }
        for index in 0..<(cues.count - 1) {
            let start = cues[index].range.start.seconds
            let end = cues[index].range.end.seconds
            let next = cues[index + 1].range.start.seconds
            let gap = next - end
            var settledEnd = end
            if gap < 0 {
                settledEnd = next - handoffSeconds
            } else if gap < bridgeSeconds {
                settledEnd = next - handoffSeconds
            }
            // Never shorter than a tenth of a second: a cue fully covered by the next is dropped
            // to a flash rather than left overlapping.
            settledEnd = max(start + 0.1, settledEnd)
            cues[index].range = MediaTimeRange(
                start: cues[index].range.start,
                duration: MediaTime(seconds: settledEnd - start)
            )
        }
        return cues
    }
}
