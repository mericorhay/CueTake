import AVFoundation
import CoreGraphics
import Domain
import Foundation

extension VideoComposer {
    /// A primary clip as the composition laid it, with what a transition needs to reach past its
    /// ends.
    struct ClipSpan {
        var segmentID: Segment.ID
        /// Where it sits on the finished video.
        var start: CMTime
        var end: CMTime
        /// The picture it plays, and the stretch of that file it plays.
        var track: AVAssetTrack
        var sourceStart: CMTime
        var sourceDuration: CMTime
        var assetDuration: CMTime
        var speed: Double
        /// Frozen or reversed: there is no footage beyond the ends to borrow, so the edge frame
        /// is held instead.
        var holdsEdges: Bool
        var frameDuration: CMTime
        /// How the clip is framed a given number of seconds into it.
        var geometry: (Double) -> VideoFrameGeometry

        var length: Double { (end - start).seconds }
    }

    /// Transitions, made by giving each cut a stretch where both clips are drawn.
    ///
    /// The clips keep their places. A second video track carries, for the first half, the next
    /// clip's lead-in and, for the second half, the previous clip's tail; the instructions over
    /// that stretch hold both tracks, each framed as its clip is. The movement itself is not put
    /// into the instructions: the compositor draws it, frame by frame, from the returned regions.
    ///
    /// It used to be eight sampled ramps per transition handed to the system's compositor. Some
    /// iOS builds refuse a ramp whose two ends are equal — a crossfade's incoming clip is nothing
    /// but those — and a refused instruction invalidates the whole video composition, so every
    /// clip played unframed and the transition not at all.
    func applyTransitions(
        _ transitions: [ClipTransition],
        spans: [ClipSpan],
        composition: AVMutableComposition,
        mainTrack: AVMutableCompositionTrack,
        instructions: [AVMutableVideoCompositionInstruction],
        render: CGSize
    ) throws -> (instructions: [AVMutableVideoCompositionInstruction], regions: [TransitionRegion]) {
        guard !transitions.isEmpty, spans.count > 1 else { return (instructions, []) }

        struct Planned {
            var start: CMTime
            var cut: CMTime
            var end: CMTime
            var kind: ClipTransition.Kind
            var outgoing: ClipSpan
            var incoming: ClipSpan
        }

        var planned: [Planned] = []
        for (outgoing, incoming) in zip(spans, spans.dropFirst()) {
            guard let transition = transitions.last(where: { $0.after == outgoing.segmentID }) else { continue }
            let seconds = ClipTransition.usableDuration(transition.duration, outgoing: outgoing.length, incoming: incoming.length)
            guard seconds >= 0.1 else { continue }
            // On the composition's own ticks, so the instructions around it meet exactly.
            let half = CMTime(value: max(1, Int64((seconds / 2 * 600).rounded())), timescale: 600)
            let cut = CMTimeConvertScale(outgoing.end, timescale: 600, method: .roundHalfAwayFromZero)
            guard cut - half >= (planned.last?.end ?? .zero) else { continue }
            planned.append(Planned(start: cut - half, cut: cut, end: cut + half, kind: transition.kind, outgoing: outgoing, incoming: incoming))
        }
        guard !planned.isEmpty,
              let carrier = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return (instructions, []) }

        // The second track: lead-ins and tails, each lasting exactly its half.
        func lay(_ span: ClipSpan, from wanted: CMTime, length half: CMTime, at time: CMTime, tail: Bool) throws {
            let end = carrier.segments.last?.timeMapping.target.end ?? .zero
            if end < time {
                carrier.insertEmptyTimeRange(CMTimeRange(start: end, duration: time - end))
            }
            let sourceLength = CMTime(seconds: half.seconds * span.speed, preferredTimescale: 600)
            var range = CMTimeRange(start: wanted, duration: sourceLength)
            let available = CMTimeRange(start: .zero, duration: span.assetDuration)
            if span.holdsEdges || range.start < .zero || range.end > available.end {
                // Nothing to borrow: hold the frame at that edge.
                let edge = tail ? CMTimeMaximum(span.sourceStart, span.sourceStart + span.sourceDuration - span.frameDuration) : span.sourceStart
                range = CMTimeRange(start: edge, duration: span.frameDuration)
            }
            try carrier.insertTimeRange(range, of: span.track, at: time)
            if abs(range.duration.seconds - half.seconds) > 0.0005 {
                carrier.scaleTimeRange(CMTimeRange(start: time, duration: range.duration), toDuration: half)
            }
        }

        for region in planned {
            let half = region.cut - region.start
            let incomingSpeedLead = CMTime(seconds: half.seconds * region.incoming.speed, preferredTimescale: 600)
            try lay(region.incoming, from: region.incoming.sourceStart - incomingSpeedLead, length: half, at: region.start, tail: false)
            try lay(region.outgoing, from: region.outgoing.sourceStart + region.outgoing.sourceDuration, length: region.end - region.cut, at: region.cut, tail: true)
        }

        // The base instructions, with the transition stretches cut out of them.
        var result: [AVMutableVideoCompositionInstruction] = []
        for instruction in instructions {
            var pieces = [instruction.timeRange]
            for region in planned {
                let cutOut = CMTimeRange(start: region.start, end: region.end)
                pieces = pieces.flatMap { piece -> [CMTimeRange] in
                    let overlap = CMTimeRangeGetIntersection(piece, otherRange: cutOut)
                    guard overlap.duration > .zero else { return [piece] }
                    var kept: [CMTimeRange] = []
                    if overlap.start > piece.start { kept.append(CMTimeRange(start: piece.start, end: overlap.start)) }
                    if overlap.end < piece.end { kept.append(CMTimeRange(start: overlap.end, end: piece.end)) }
                    return kept
                }
            }
            for piece in pieces where piece.duration > .zero {
                if piece == instruction.timeRange {
                    result.append(instruction)
                    continue
                }
                let copy = AVMutableVideoCompositionInstruction()
                copy.timeRange = piece
                copy.layerInstructions = instruction.layerInstructions
                copy.backgroundColor = instruction.backgroundColor
                result.append(copy)
            }
        }

        // The stretches themselves: both clips, framed as they are either side of the cut.
        let samples = 4
        for region in planned {
            let halves = [
                (from: region.start, to: region.cut, outgoingTrack: mainTrack as AVAssetTrack, incomingTrack: carrier as AVAssetTrack),
                (from: region.cut, to: region.end, outgoingTrack: carrier as AVAssetTrack, incomingTrack: mainTrack as AVAssetTrack),
            ]
            for half in halves {
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: half.from, end: half.to)
                let outgoing = AVMutableVideoCompositionLayerInstruction(assetTrack: half.outgoingTrack)
                let incoming = AVMutableVideoCompositionLayerInstruction(assetTrack: half.incomingTrack)
                let length = (half.to - half.from).seconds
                for step in 0..<samples {
                    let timeA = step == 0 ? half.from : half.from + CMTime(seconds: length * Double(step) / Double(samples), preferredTimescale: 600)
                    let timeB = step == samples - 1 ? half.to : half.from + CMTime(seconds: length * Double(step + 1) / Double(samples), preferredTimescale: 600)
                    guard timeB > timeA else { continue }
                    let ramp = CMTimeRange(start: timeA, end: timeB)
                    // Seconds into each clip at the two ends, held inside the clip.
                    let outA = region.outgoing.geometry(min((timeA - region.outgoing.start).seconds, region.outgoing.length))
                    let outB = region.outgoing.geometry(min((timeB - region.outgoing.start).seconds, region.outgoing.length))
                    let inA = region.incoming.geometry(max((timeA - region.incoming.start).seconds, 0))
                    let inB = region.incoming.geometry(max((timeB - region.incoming.start).seconds, 0))
                    Self.frame(outgoing, from: outA, to: outB, over: ramp)
                    Self.frame(incoming, from: inA, to: inB, over: ramp)
                }
                instruction.layerInstructions = [outgoing, incoming]
                instruction.backgroundColor = CGColor(gray: region.kind == .fadeWhite ? 1 : 0, alpha: 1)
                result.append(instruction)
            }
        }
        let regions = planned.map {
            TransitionRegion(start: $0.start, cut: $0.cut, end: $0.end, kind: $0.kind, mainTrackID: mainTrack.trackID, carrierTrackID: carrier.trackID)
        }
        return (result.sorted { $0.timeRange.start < $1.timeRange.start }, regions)
    }

    /// A clip's framing over part of a transition. A value that does not change is set, not
    /// ramped: a ramp with equal ends is exactly what some AVFoundation builds refuse.
    static func frame(_ layer: AVMutableVideoCompositionLayerInstruction, from a: VideoFrameGeometry, to b: VideoFrameGeometry, over range: CMTimeRange) {
        if a.transform == b.transform {
            layer.setTransform(a.transform, at: range.start)
        } else {
            layer.setTransformRamp(fromStart: a.transform, toEnd: b.transform, timeRange: range)
        }
        if a.crop == b.crop {
            layer.setCropRectangle(a.crop, at: range.start)
        } else {
            layer.setCropRectangleRamp(fromStartCropRectangle: a.crop, toEndCropRectangle: b.crop, timeRange: range)
        }
    }
}

/// A cut where two clips are drawn at once, as the compositor needs to know it.
struct TransitionRegion: Sendable, Equatable {
    var start: CMTime
    var cut: CMTime
    var end: CMTime
    var kind: ClipTransition.Kind
    /// The clips' own track, and the one carrying the borrowed lead-in and tail.
    var mainTrackID: CMPersistentTrackID
    var carrierTrackID: CMPersistentTrackID

    func contains(_ time: CMTime) -> Bool { time >= start && time < end }

    /// Which track shows which clip: before the cut the leaving clip is still on its own track.
    func tracks(at time: CMTime) -> (outgoing: CMPersistentTrackID, incoming: CMPersistentTrackID) {
        time < cut ? (mainTrackID, carrierTrackID) : (carrierTrackID, mainTrackID)
    }

    /// How the two clips are drawn at a moment, eased.
    func look(at time: CMTime) -> TransitionLook {
        let total = (end - start).seconds
        guard total > 0 else { return TransitionLook.at(1, kind: kind) }
        return TransitionLook.at(TransitionLook.eased((time - start).seconds / total), kind: kind)
    }
}
