import AVFoundation
import CoreGraphics
import Domain
import Foundation

/// Source-space cropping keeps a filled split-screen video inside its own cell, including rotated
/// and mirrored recordings. Preview and export receive these exact same instructions.
struct VideoFrameGeometry {
    var transform: CGAffineTransform
    var crop: CGRect

    init(natural: CGSize, preferred: CGAffineTransform, placement: VideoPlacement, render: CGSize) {
        let placement = placement.bounded
        let source = CGRect(origin: .zero, size: natural)
        let oriented = source.applying(preferred)
        let width = max(1, abs(oriented.width)), height = max(1, abs(oriented.height))
        let target = CGRect(x: placement.x * render.width, y: placement.y * render.height, width: placement.width * render.width, height: placement.height * render.height)
        let fit = placement.fillsFrame ? max(target.width / width, target.height / height) : min(target.width / width, target.height / height)
        let factor = fit * (placement.zoom ?? 1)
        var transform = preferred.concatenating(CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY))
        if placement.isMirrored {
            transform = transform.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0))
        }
        // Keep the requested point centred as far as the source allows. Clamping by the visible
        // half-width/height prevents an edge face from revealing black outside the source.
        let halfVisibleX = min(0.5, target.width / factor / width / 2)
        let halfVisibleY = min(0.5, target.height / factor / height / 2)
        let requestedX = placement.fillsFrame ? (placement.focusX ?? 0.5) : 0.5
        let requestedY = placement.fillsFrame ? (placement.focusY ?? 0.5) : 0.5
        let focusX = min(max(requestedX, halfVisibleX), 1 - halfVisibleX)
        let focusY = min(max(requestedY, halfVisibleY), 1 - halfVisibleY)
        transform = transform.concatenating(CGAffineTransform(scaleX: factor, y: factor))
            .concatenating(CGAffineTransform(
                translationX: target.midX - width * factor * focusX,
                y: target.midY - height * factor * focusY
            ))
        let crop = target.applying(transform.inverted()).intersection(source)
        let finite = [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy(\.isFinite)
        self.transform = finite ? transform : preferred
        self.crop = crop.isNull || crop.isEmpty || !crop.origin.x.isFinite
            ? CGRect(x: source.midX, y: source.midY, width: 1, height: 1)
            : crop
    }
}

extension VideoComposer {
    struct LayerTrack {
        var layer: VideoLayer
        var track: AVMutableCompositionTrack
        var natural: CGSize
        var preferred: CGAffineTransform
    }

    /// Every movie gets its own video/audio track so overlapping footage shares one player clock.
    func addVideoLayers(project: Project, directory: URL, composition: AVMutableComposition, base: [AVMutableVideoCompositionInstruction], render: CGSize) async throws -> (instructions: [AVMutableVideoCompositionInstruction], audio: [AVMutableAudioMixInputParameters], tracks: [CMPersistentTrackID: VideoLayer.ID]) {
        var tracks: [LayerTrack] = []
        var audio: [AVMutableAudioMixInputParameters] = []
        // Added videos play over the main video and end with it; with no main video they set the length.
        let videoEnd = base.last?.timeRange.end.seconds
        for original in project.videoLayers {
            guard let recording = project.recording(id: original.recordingID) else { throw ComposeError.missingMedia(original.recordingID) }
            let asset = AssetCache.shared.asset(for: directory.appending(path: (recording.relativePath as NSString).lastPathComponent))
            guard let source = try await asset.loadTracks(withMediaType: .video).first else { throw ComposeError.noVideoTrack(recording.id) }
            let duration = try await asset.load(.duration)
            let start = CMTime(seconds: max(0, original.sourceRange.start.seconds), preferredTimescale: 600)
            var length = min(CMTime(seconds: original.duration, preferredTimescale: 600), duration - start)
            if let videoEnd {
                length = min(length, CMTime(seconds: max(0, videoEnd - max(0, original.start.seconds)), preferredTimescale: 600))
            }
            guard length.seconds > 0.001, original.start.seconds.isFinite else { continue }
            let at = CMTime(seconds: max(0, original.start.seconds), preferredTimescale: 600)
            let range = CMTimeRange(start: start, duration: length)
            var layer = original
            layer.sourceRange = MediaTimeRange(start: MediaTime(seconds: start.seconds), duration: MediaTime(seconds: length.seconds))
            layer.start = MediaTime(seconds: at.seconds)
            if !layer.isHidden, let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try track.insertTimeRange(range, of: source, at: at)
                let natural = try await source.load(.naturalSize)
                let preferred = try await source.load(.preferredTransform)
                tracks.append(LayerTrack(layer: layer, track: track, natural: natural, preferred: preferred))
            }
            if !layer.isMuted, let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
               let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let available = try await sourceAudio.load(.timeRange)
                let audioRange = CMTimeRangeGetIntersection(range, otherRange: available)
                if audioRange.duration.seconds > 0 {
                    try track.insertTimeRange(audioRange, of: sourceAudio, at: at + audioRange.start - range.start)
                    let input = AVMutableAudioMixInputParameters(track: track)
                    input.setVolume(Float(min(max(layer.volume, 0), 1)), at: at)
                    audio.append(input)
                }
            }
        }

        let lastBase = base.last?.timeRange.end.seconds ?? 0
        let layersEnd = tracks.map(\.layer.end).max() ?? 0
        let end = max(lastBase, videoEnd == nil ? layersEnd : 0, composition.duration.seconds)
        guard end > 0 else { throw ComposeError.nothingToCompose }
        var boundaries = [0.0, end]
        for item in base { boundaries += [item.timeRange.start.seconds, item.timeRange.end.seconds] }
        for item in tracks {
            boundaries += [item.layer.start.seconds, min(item.layer.end, end)]
            boundaries += item.layer.orderedKeyframes.map { item.layer.start.seconds + $0.time }
            boundaries += item.layer.orderedFocusKeyframes.map { item.layer.start.seconds + $0.time }
        }
        // Quantise once. Adjacent instructions share the same tick and cannot overlap by rounding.
        let ticks = Set(boundaries.filter { $0.isFinite && $0 >= 0 && $0 <= end }.map { Int64(($0 * 600).rounded()) }).sorted()
        var instructions: [AVMutableVideoCompositionInstruction] = []
        for (from, to) in zip(ticks, ticks.dropFirst()) where to > from {
            let start = CMTime(value: from, timescale: 600), stop = CMTime(value: to, timescale: 600)
            let middle = (start.seconds + stop.seconds) / 2
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: start, end: stop)
            instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
            var layers: [AVVideoCompositionLayerInstruction] = []
            for item in tracks.reversed() where middle >= item.layer.start.seconds && middle < item.layer.end {
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: item.track)
                let a = item.layer.placement(at: start.seconds)
                let b = item.layer.placement(at: stop.seconds)
                let first = VideoFrameGeometry(natural: item.natural, preferred: item.preferred, placement: a, render: render)
                let last = VideoFrameGeometry(natural: item.natural, preferred: item.preferred, placement: b, render: render)
                // A value that does not change is set, not ramped: some AVFoundation builds refuse a
                // ramp with equal ends, and one refusal makes the whole video composition invalid.
                if first.transform == last.transform {
                    layer.setTransform(first.transform, at: start)
                } else {
                    layer.setTransformRamp(fromStart: first.transform, toEnd: last.transform, timeRange: instruction.timeRange)
                }
                if first.crop == last.crop {
                    layer.setCropRectangle(first.crop, at: start)
                } else {
                    layer.setCropRectangleRamp(fromStartCropRectangle: first.crop, toEndCropRectangle: last.crop, timeRange: instruction.timeRange)
                }
                if a.opacity == b.opacity {
                    layer.setOpacity(Float(a.opacity), at: start)
                } else {
                    layer.setOpacityRamp(fromStartOpacity: Float(a.opacity), toEndOpacity: Float(b.opacity), timeRange: instruction.timeRange)
                }
                layers.append(layer)
            }
            if let source = base.first(where: { middle >= $0.timeRange.start.seconds && middle < $0.timeRange.end.seconds }) {
                layers += source.layerInstructions
                if let background = source.backgroundColor { instruction.backgroundColor = background }
            }
            instruction.layerInstructions = layers
            instructions.append(instruction)
        }
        // A hidden/silent layer can still define the canvas duration.
        if composition.duration.seconds < end {
            composition.insertEmptyTimeRange(CMTimeRange(start: composition.duration, duration: CMTime(seconds: end - composition.duration.seconds, preferredTimescale: 600)))
        }
        var ids: [CMPersistentTrackID: VideoLayer.ID] = [:]
        for item in tracks { ids[item.track.trackID] = item.layer.id }
        return (instructions, audio, ids)
    }
}
