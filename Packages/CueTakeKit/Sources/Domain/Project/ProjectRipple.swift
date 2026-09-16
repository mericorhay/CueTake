import Foundation

/// What closing a gap in the video did to the things laid over it.
public struct RippleReport: Hashable, Sendable {
    public var removedOverlays = 0
    public var removedEffects = 0
    public var removedAudio = 0
    public var removedVideoLayers = 0
    public var moved = 0

    public init() {}

    public var removedCount: Int { removedOverlays + removedEffects + removedAudio + removedVideoLayers }
}

extension Project {
    /// Closes the gap a deleted clip leaves, so everything after it stays on the picture it was
    /// placed against.
    ///
    /// Texts, pictures, effects, sounds and added videos are pinned to moments on the finished
    /// video. Deleting a clip used to pull the pictures after it earlier and leave everything
    /// else where it was: the "subscribe" text landed on the wrong sentence and the whoosh played
    /// a clip late. Now:
    /// - things after the gap move back by its length;
    /// - things wholly inside the gap belonged to the deleted clip and go with it;
    /// - things that cross the gap lose the part that was over it, and a sound or video that
    ///   starts inside it skips the part that would have played there, so what is left stays in
    ///   sync.
    @discardableResult
    public mutating func closeGap(from gapStart: Double, length: Double) -> RippleReport {
        var report = RippleReport()
        guard length > 0.0001, gapStart.isFinite else { return report }
        let gap = RippleGap(start: gapStart, end: gapStart + length)

        overlays = overlays.compactMap { overlay in
            switch gap.apply(start: overlay.start.seconds, duration: overlay.duration.seconds, minimum: 0.1) {
            case .keep: return overlay
            case .remove:
                report.removedOverlays += 1
                return nil
            case .change(let start, let duration, _):
                var changed = overlay
                changed.start = MediaTime(seconds: start)
                changed.duration = MediaTime(seconds: duration)
                report.moved += 1
                return changed
            }
        }

        effects = effects.compactMap { effect in
            switch gap.apply(start: effect.start.seconds, duration: effect.duration.seconds, minimum: TimelineEffect.minimumLength) {
            case .keep: return effect
            case .remove:
                report.removedEffects += 1
                return nil
            case .change(let start, let duration, _):
                var changed = effect
                changed.start = MediaTime(seconds: start)
                changed.duration = MediaTime(seconds: duration)
                report.moved += 1
                return changed
            }
        }

        audio = audio.compactMap { clip in
            switch gap.apply(start: clip.start.seconds, duration: clip.timelineDuration.seconds, minimum: 0.1) {
            case .keep: return clip
            case .remove:
                report.removedAudio += 1
                return nil
            case .change(let start, let duration, let headCut):
                var changed = clip
                let speed = max(0.1, clip.speed)
                changed.start = MediaTime(seconds: start)
                changed.sourceRange = MediaTimeRange(
                    start: MediaTime(seconds: clip.sourceRange.start.seconds + headCut * speed),
                    duration: MediaTime(seconds: duration * speed)
                )
                if headCut > 0 { changed.fadeIn = MediaTime(seconds: min(0.15, changed.fadeIn.seconds)) }
                report.moved += 1
                return changed
            }
        }

        videoLayers = videoLayers.compactMap { layer in
            switch gap.apply(start: layer.start.seconds, duration: layer.duration, minimum: 0.1) {
            case .keep: return layer
            case .remove:
                report.removedVideoLayers += 1
                return nil
            case .change(let start, let duration, let headCut):
                var changed = layer
                changed.start = MediaTime(seconds: start)
                changed.sourceRange = MediaTimeRange(
                    start: MediaTime(seconds: layer.sourceRange.start.seconds + headCut),
                    duration: MediaTime(seconds: duration)
                )
                if headCut > 0 {
                    changed.keyframes = layer.keyframes.compactMap { frame in
                        var frame = frame
                        frame.time -= headCut
                        return frame.time >= 0 ? frame : nil
                    }
                    changed.focusKeyframes = layer.focusKeyframes?.compactMap { frame in
                        var frame = frame
                        frame.time -= headCut
                        return frame.time >= 0 ? frame : nil
                    }
                }
                report.moved += 1
                return changed
            }
        }

        if let window = captionWindow {
            switch gap.apply(start: window.start.seconds, duration: window.duration.seconds, minimum: 0.1) {
            case .keep: break
            case .remove: captionWindow = nil
            case .change(let start, let duration, _):
                captionWindow = MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: duration))
            }
        }
        return report
    }
}

/// A stretch of the finished video that is going away.
struct RippleGap {
    var start: Double
    var end: Double
    var length: Double { end - start }

    enum Outcome: Equatable {
        case keep
        case remove
        /// New start and length, and how much was cut from the front.
        case change(start: Double, duration: Double, headCut: Double)
    }

    func apply(start itemStart: Double, duration: Double, minimum: Double) -> Outcome {
        let itemEnd = itemStart + duration
        let tolerance = 0.001
        // Entirely before the gap.
        if itemEnd <= start + tolerance { return .keep }
        // Entirely after: moves back.
        if itemStart >= end - tolerance {
            return .change(start: max(0, itemStart - length), duration: duration, headCut: 0)
        }
        // Entirely inside: went with the clip.
        if itemStart >= start - tolerance && itemEnd <= end + tolerance { return .remove }

        let before = max(0, start - itemStart)
        let after = max(0, itemEnd - end)
        let kept = before + after
        guard kept >= minimum else { return .remove }
        if itemStart < start {
            // Starts before: keeps its start, loses the part over the gap.
            return .change(start: itemStart, duration: kept, headCut: 0)
        }
        // Starts inside: begins where the gap was, without the part that was inside it.
        return .change(start: start, duration: after, headCut: end - itemStart)
    }
}
