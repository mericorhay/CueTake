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
        let factor = placement.fillsFrame ? max(target.width / width, target.height / height) : min(target.width / width, target.height / height)
        var transform = preferred.concatenating(CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY))
        if placement.isMirrored {
            transform = transform.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0))
        }
        transform = transform.concatenating(CGAffineTransform(scaleX: factor, y: factor))
            .concatenating(CGAffineTransform(translationX: target.midX - width * factor / 2, y: target.midY - height * factor / 2))
        self.transform = transform
        self.crop = target.applying(transform.inverted()).intersection(source)
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
    func addVideoLayers(project: Project, directory: URL, composition: AVMutableComposition, base: [AVMutableVideoCompositionInstruction], render: CGSize) async throws -> (instructions: [AVMutableVideoCompositionInstruction], audio: [AVMutableAudioMixInputParameters]) {
        var tracks: [LayerTrack] = []
        var audio: [AVMutableAudioMixInputParameters] = []
        // Added videos play over the main video and end with it; with no main video they set the length.
        let videoEnd = base.last?.timeRange.end.seconds
        for original in project.videoLayers {
            guard let recording = project.recording(id: original.recordingID) else { throw ComposeError.missingMedia(original.recordingID) }
            let asset = AVURLAsset(url: directory.appending(path: (recording.relativePath as NSString).lastPathComponent))
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
                layer.setTransformRamp(fromStart: first.transform, toEnd: last.transform, timeRange: instruction.timeRange)
                layer.setCropRectangleRamp(fromStartCropRectangle: first.crop, toEndCropRectangle: last.crop, timeRange: instruction.timeRange)
                layer.setOpacityRamp(fromStartOpacity: Float(a.opacity), toEndOpacity: Float(b.opacity), timeRange: instruction.timeRange)
                layers.append(layer)
            }
            if let source = base.first(where: { middle >= $0.timeRange.start.seconds && middle < $0.timeRange.end.seconds }) {
                layers += source.layerInstructions
            }
            instruction.layerInstructions = layers
            instructions.append(instruction)
        }
        // A hidden/silent layer can still define the canvas duration.
        if composition.duration.seconds < end {
            composition.insertEmptyTimeRange(CMTimeRange(start: composition.duration, duration: CMTime(seconds: end - composition.duration.seconds, preferredTimescale: 600)))
        }
        return (instructions, audio)
    }
}
