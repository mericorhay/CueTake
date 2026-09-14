import Domain
import Foundation
import MediaEngine
import SwiftUI

/// When an added video plays: where it starts on the finished video, where it stops, which part of
/// its own file it shows, and cutting it in two.
///
/// Every edge is clamped to the file behind the layer — a layer cannot run past the end of its
/// recording or start before its first frame — so a drag or a stepper can never ask the composer
/// for footage that does not exist.
extension EditorModel {
    /// Seconds of footage the layer's recording has after `sourceStart`.
    func availableFootage(for layer: VideoLayer, from sourceStart: Double) -> Double {
        guard let recording = project.recording(id: layer.recordingID) else { return layer.duration }
        return max(0.2, recording.duration.seconds - sourceStart)
    }

    /// Moves the whole layer so it begins at `seconds`, keeping its length.
    public func moveVideoLayer(_ id: VideoLayer.ID, to seconds: Double, coalescing key: String = "video-layer-move") {
        updateVideoLayer(id, coalescing: "\(key)-\(id)") {
            $0.start = MediaTime(seconds: max(0, seconds))
        }
    }

    /// Moves where the layer stops on the finished video, keeping where it starts.
    public func setVideoLayerEnd(_ id: VideoLayer.ID, to seconds: Double, coalescing key: String = "video-layer-end") {
        guard let layer = project.videoLayers.first(where: { $0.id == id }) else { return }
        let available = availableFootage(for: layer, from: layer.sourceRange.start.seconds)
        let length = min(max(0.2, seconds - layer.start.seconds), available)
        updateVideoLayer(id, coalescing: "\(key)-\(id)") {
            $0.sourceRange.duration = MediaTime(seconds: length)
        }
    }

    /// Moves where the layer starts on the finished video, keeping where it stops: the front is
    /// trimmed (later) or brought back (earlier, as far as the file allows).
    public func setVideoLayerStartEdge(_ id: VideoLayer.ID, to seconds: Double, coalescing key: String = "video-layer-start") {
        guard let layer = project.videoLayers.first(where: { $0.id == id }) else { return }
        let wanted = max(0, seconds)
        let delta = wanted - layer.start.seconds
        // Earlier than the file's first frame is not possible; later than 0.2 s before the end neither.
        let applied = min(max(delta, -layer.sourceRange.start.seconds), layer.duration - 0.2)
        guard abs(applied) > 0.0001 else { return }
        updateVideoLayer(id, coalescing: "\(key)-\(id)") { value in
            if applied > 0 {
                value.trimStart(by: applied)
            } else {
                value.start = MediaTime(seconds: max(0, value.start.seconds + applied))
                value.sourceRange = MediaTimeRange(
                    start: MediaTime(seconds: value.sourceRange.start.seconds + applied),
                    duration: MediaTime(seconds: value.duration - applied)
                )
                value.keyframes = value.keyframes.map {
                    var frame = $0
                    frame.time -= applied
                    return frame
                }
            }
        }
    }

    /// Which second of its own file the layer starts showing, keeping its place and length on the
    /// finished video. What "use a different part of this video" means.
    public func setVideoLayerSourceStart(_ id: VideoLayer.ID, to seconds: Double) {
        guard let layer = project.videoLayers.first(where: { $0.id == id }),
              let recording = project.recording(id: layer.recordingID)
        else { return }
        let total = recording.duration.seconds
        let start = min(max(0, seconds), max(0, total - 0.2))
        let length = min(layer.duration, total - start)
        updateVideoLayer(id, coalescing: "video-layer-source-\(id)") {
            $0.sourceRange = MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: max(0.2, length)))
        }
    }

    /// Whether the playhead is far enough inside the layer to cut it in two.
    public func canSplitVideoLayer(_ id: VideoLayer.ID) -> Bool {
        guard let layer = project.videoLayers.first(where: { $0.id == id }) else { return false }
        let offset = playhead - layer.start.seconds
        return offset > 0.15 && layer.duration - offset > 0.15
    }

    /// Cuts a layer at the playhead into two layers that play one after the other.
    public func splitVideoLayer(_ id: VideoLayer.ID) {
        guard canSplitVideoLayer(id),
              let index = project.videoLayers.firstIndex(where: { $0.id == id })
        else { return }
        let layer = project.videoLayers[index]
        let offset = playhead - layer.start.seconds

        record("editor.change.split", symbol: "scissors")
        var left = layer
        left.sourceRange.duration = MediaTime(seconds: offset)
        left.keyframes = layer.keyframes.filter { $0.time < offset }

        var right = layer
        right.id = UUID()
        right.trimStart(by: offset)
        right.keyframes = right.keyframes.map {
            var frame = $0
            frame.id = UUID()
            return frame
        }

        project.videoLayers[index] = left
        project.videoLayers.insert(right, at: index + 1)
        project.updatedAt = .now
        select(videoLayer: right.id)
    }

    /// Reads frames across a whole recording once, for trimming an added video by its pictures.
    func loadRecordingFrames(_ recordingID: Recording.ID) async {
        guard recordingFrames[recordingID] == nil,
              let mediaDirectory,
              let recording = project.recording(id: recordingID)
        else { return }
        let url = mediaDirectory.appending(
            path: (recording.relativePath as NSString).lastPathComponent,
            directoryHint: .notDirectory
        )
        let frames = await ThumbnailSampler().frames(
            of: url,
            from: 0,
            duration: recording.duration.seconds,
            count: min(16, max(4, Int(recording.duration.seconds / 2)))
        )
        guard !frames.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            recordingFrames[recordingID] = frames
        }
    }

    /// Which stretch of its file an added video plays, chosen on its trim strip.
    ///
    /// The start handle trims the front and the video keeps its end on the timeline; the end
    /// handle trims the back; sliding the window keeps the video where it is on the timeline and
    /// plays another part of the file.
    public func trimVideoLayer(_ id: VideoLayer.ID, sourceStart: Double? = nil, sourceEnd: Double? = nil, slideTo: Double? = nil) {
        guard let layer = project.videoLayers.first(where: { $0.id == id }) else { return }
        if let slideTo {
            setVideoLayerSourceStart(id, to: slideTo)
        }
        if let sourceStart {
            let shift = sourceStart - layer.sourceRange.start.seconds
            setVideoLayerStartEdge(id, to: layer.start.seconds + shift, coalescing: "video-layer-strip-start")
        }
        if let sourceEnd {
            setVideoLayerEnd(id, to: layer.start.seconds + (sourceEnd - layer.sourceRange.start.seconds), coalescing: "video-layer-strip-end")
        }
    }
}
