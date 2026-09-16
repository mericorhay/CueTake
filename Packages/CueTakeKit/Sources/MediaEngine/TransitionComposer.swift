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
    /// that stretch draw both tracks, animated. Everything else on the timeline is untouched.
    func applyTransitions(
        _ transitions: [ClipTransition],
        spans: [ClipSpan],
        composition: AVMutableComposition,
        mainTrack: AVMutableCompositionTrack,
        instructions: [AVMutableVideoCompositionInstruction],
        render: CGSize
    ) throws -> [AVMutableVideoCompositionInstruction] {
        guard !transitions.isEmpty, spans.count > 1 else { return instructions }

        struct Region {
            var start: CMTime
            var cut: CMTime
            var end: CMTime
            var kind: ClipTransition.Kind
            var outgoing: ClipSpan
            var incoming: ClipSpan
        }

        var regions: [Region] = []
        for (outgoing, incoming) in zip(spans, spans.dropFirst()) {
            guard let transition = transitions.last(where: { $0.after == outgoing.segmentID }) else { continue }
            let seconds = ClipTransition.usableDuration(transition.duration, outgoing: outgoing.length, incoming: incoming.length)
            guard seconds >= 0.1 else { continue }
            let half = CMTime(seconds: seconds / 2, preferredTimescale: 600)
            let cut = outgoing.end
            regions.append(Region(start: cut - half, cut: cut, end: cut + half, kind: transition.kind, outgoing: outgoing, incoming: incoming))
        }
        guard !regions.isEmpty,
              let carrier = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return instructions }

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

        for region in regions {
            let half = region.cut - region.start
            let incomingSpeedLead = CMTime(seconds: half.seconds * region.incoming.speed, preferredTimescale: 600)
            try lay(region.incoming, from: region.incoming.sourceStart - incomingSpeedLead, length: half, at: region.start, tail: false)
            try lay(region.outgoing, from: region.outgoing.sourceStart + region.outgoing.sourceDuration, length: region.end - region.cut, at: region.cut, tail: true)
        }

        // The base instructions, with the transition stretches cut out of them.
        var result: [AVMutableVideoCompositionInstruction] = []
        for instruction in instructions {
            var pieces = [instruction.timeRange]
            for region in regions {
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

        // The stretches themselves, sampled so the movement eases.
        let samples = 8
        for region in regions {
            let total = (region.end - region.start).seconds
            let first = (from: region.start, to: region.cut, outgoingTrack: mainTrack as AVAssetTrack, incomingTrack: carrier as AVAssetTrack)
            let second = (from: region.cut, to: region.end, outgoingTrack: carrier as AVAssetTrack, incomingTrack: mainTrack as AVAssetTrack)
            for half in [first, second] {
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: half.from, end: half.to)
                let outgoing = AVMutableVideoCompositionLayerInstruction(assetTrack: half.outgoingTrack)
                let incoming = AVMutableVideoCompositionLayerInstruction(assetTrack: half.incomingTrack)

                let steps = samples / 2
                let base = (half.from - region.start).seconds
                var incomingOnTop = false
                var white = false
                for step in 0..<steps {
                    let a = base + (total / 2) * Double(step) / Double(steps)
                    let b = base + (total / 2) * Double(step + 1) / Double(steps)
                    let lookA = TransitionLook.at(TransitionLook.eased(a / total), kind: region.kind)
                    let lookB = TransitionLook.at(TransitionLook.eased(b / total), kind: region.kind)
                    incomingOnTop = lookA.incomingOnTop || lookB.incomingOnTop
                    white = lookA.whiteBackground
                    let timeA = region.start + CMTime(seconds: a, preferredTimescale: 600)
                    let timeB = step == steps - 1 ? half.to : region.start + CMTime(seconds: b, preferredTimescale: 600)
                    guard timeB > timeA else { continue }
                    let ramp = CMTimeRange(start: timeA, end: timeB)

                    // Seconds into each clip at the two ends of this ramp, held inside the clip.
                    let outA = region.outgoing.geometry(min((timeA - region.outgoing.start).seconds, region.outgoing.length))
                    let outB = region.outgoing.geometry(min((timeB - region.outgoing.start).seconds, region.outgoing.length))
                    let inA = region.incoming.geometry(max((timeA - region.incoming.start).seconds, 0))
                    let inB = region.incoming.geometry(max((timeB - region.incoming.start).seconds, 0))

                    Self.ramp(outgoing, from: Self.placed(outA, lookA.outgoing, render: render), to: Self.placed(outB, lookB.outgoing, render: render), over: ramp)
                    Self.ramp(incoming, from: Self.placed(inA, lookA.incoming, render: render), to: Self.placed(inB, lookB.incoming, render: render), over: ramp)
                }
                instruction.layerInstructions = incomingOnTop ? [incoming, outgoing] : [outgoing, incoming]
                instruction.backgroundColor = CGColor(gray: white ? 1 : 0, alpha: 1)
                result.append(instruction)
            }
        }
        return result.sorted { $0.timeRange.start < $1.timeRange.start }
    }

    /// A clip's framing with a transition's movement on top.
    struct PlacedLayer {
        var transform: CGAffineTransform
        var crop: CGRect
        var opacity: Float
    }

    static func placed(_ geometry: VideoFrameGeometry, _ layer: TransitionLook.Layer, render: CGSize) -> PlacedLayer {
        let cx = render.width / 2, cy = render.height / 2
        let move = CGAffineTransform(translationX: -cx, y: -cy)
            .concatenating(CGAffineTransform(scaleX: layer.scale, y: layer.scale))
            .concatenating(CGAffineTransform(translationX: cx + layer.dx * render.width, y: cy + layer.dy * render.height))
        let transform = geometry.transform.concatenating(move)
        var crop = geometry.crop
        if let visible = layer.visible {
            let region = CGRect(
                x: visible.x * render.width,
                y: visible.y * render.height,
                width: max(0, visible.width) * render.width,
                height: max(0, visible.height) * render.height
            )
            let inSource = region.applying(transform.inverted()).intersection(geometry.crop)
            crop = inSource.isNull || inSource.width < 1 || inSource.height < 1
                ? CGRect(x: geometry.crop.minX, y: geometry.crop.minY, width: 1, height: 1)
                : inSource
            if inSource.isNull || inSource.width < 1 || inSource.height < 1 {
                return PlacedLayer(transform: transform, crop: crop, opacity: 0)
            }
        }
        return PlacedLayer(transform: transform, crop: crop, opacity: Float(min(max(layer.opacity, 0), 1)))
    }

    static func ramp(_ layer: AVMutableVideoCompositionLayerInstruction, from a: PlacedLayer, to b: PlacedLayer, over range: CMTimeRange) {
        layer.setTransformRamp(fromStart: a.transform, toEnd: b.transform, timeRange: range)
        layer.setCropRectangleRamp(fromStartCropRectangle: a.crop, toEndCropRectangle: b.crop, timeRange: range)
        layer.setOpacityRamp(fromStartOpacity: a.opacity, toEndOpacity: b.opacity, timeRange: range)
    }
}
